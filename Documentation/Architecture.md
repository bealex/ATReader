# Architecture

Two modules with a hard line between them.

```
Frameworks/AuthorToday/   the service: HTTP, models, decryption. No SwiftUI, no app concepts.
Code/                     the app: screens, session, cache, background work.
```

The package knows nothing about screens; the app knows nothing about headers, endpoints or ciphers.
Anything service-shaped that leaks into `Code/` is a mistake, and so is the reverse.

## The package

`AuthorTodayClient` is a `Sendable` final class. Its only mutable state is a credential pair (token and
account id) behind a `Mutex`, so it can be shared freely and passed off the main actor, which the
background sweep depends on.

Endpoint methods are split across extensions by area (`+Account`, `+Catalog`, `+Work`, `+Reader`) over
a small internal `Endpoint` struct and one `send` path that decodes or throws the service's error
envelope.

Two decisions to know about:

- Enums that mirror service values conform to `DefaultingDecodable`, so an unrecognised member decodes
  to a fallback instead of throwing. The service adds enum members over time and a reader should
  survive meeting one. Where a field can change *type* rather than value, the containing model gets a
  hand-written `init(from:)`; see `LoginResult`.
- `ChapterText` is decrypted before it leaves the package. Callers get HTML and the cipher stays an
  implementation detail. `ChapterHTML` then flattens that HTML into `Paragraph` values, so the reader
  view has nothing to parse.

## The app

Screens follow the house pattern: a namespace `enum` holding an `@Observable @MainActor final class
Model` and a `struct Component: View`, split across `<Screen>.Model.swift` and
`<Screen>.Component.swift`. Models hold `private(set)` state and take their dependencies at init.

```
App/          entry point, RootScreen (signed-in vs signed-out), AppRoute
Components/   CoverImage, WorkRow, WorkSummary, shared across every list
Screens/      Login, Library, Search, Top, Work, Reader, Profile
Services/     SessionStore, KeychainStore, BookCache, CatalogFeed,
              ChapterUpdateService, BackgroundRefresh, ReaderSettings
```

### Routing

Each tab owns a `NavigationStack` over a shared `AppRoute` enum, and every stack resolves routes
through one `AppRouteDestination` view. A book opened from search, from the charts or from the library
therefore lands on the same screen with the same behaviour, without the tabs sharing navigation state.

### Session

`SessionStore` owns the client and the signed-in user, and is the only thing that touches
`KeychainStore`. It exposes three states (restoring, signed out, signed in) and `RootScreen` switches
on them. Token and account id go to the keychain; nothing sensitive reaches user defaults.

### One row type, three sources

The library, the catalogue and a work's own details return three different shapes for the same idea.
`WorkSummary` is the single presentation struct they all map into, so `WorkRow` serves every list.
Adding a fourth source means adding an initialiser, not a view.

### CatalogFeed

Search and the charts hit the same endpoint with different queries, so they share one paging engine.
It de-duplicates by id across pages, since the service occasionally repeats an entry near a page
boundary, tracks `isLastPage`, and rolls the page number back if a page fails so a retry doesn't skip
content.

## The reader

Chapters are paginated rather than scrolled, and the whole thing is built on CoreText rather than
SwiftUI `Text`. Two reasons forced that: SwiftUI has no justified alignment, and pagination has to
agree exactly with drawing.

`ChapterPagination` builds the chapter as one `NSAttributedString` from a `ChapterTextStyle` (face,
size, line spacing, justification, colour) and then walks it a page at a time, asking
`CTFrameGetVisibleStringRange` what actually fitted in each frame. `ChapterPageView` draws a page by
handing the *same* framesetter the range for that page, so a page can never show something pagination
didn't measure. Margins are deliberately not part of the style: they shrink the frame, not the text.

The view triggers re-pagination whenever the page size or the style changes. The reader's position
survives it because the model remembers a character offset rather than a page number. A larger font
means the same text spans more pages, so the page index alone is meaningless across a restyle.

`PageTurnView` handles the turn. The entire effect comes from one rule, that page `n + 1` always sits
above page `n`, so a single offset drives both directions: turning forward slides page `n + 1` in from
the right, turning back slides that same page off to the right and uncovers page `n`. A half-finished
turn can therefore be reversed with no special handling. Progress runs `0…1`, where `0` is the resting
state and `1` is committed, and the gesture measures against the turn's own direction so a reversed
finger unwinds it.

Taps on either outer third turn forward; the middle third is a dead zone. Turning past the end of a
chapter hands over to the next one, and past the start goes back to the previous chapter's last page.

Taps that arrive while a turn is still animating are queued rather than dropped, and the queue drains
as soon as each turn commits, running faster while it has a backlog. A burst of taps therefore stacks
pages through in quick succession and settles on the page the reader asked for.

The system's swipe-from-the-edge-to-go-back gesture is switched off here, because it competes with
swiping back a page. SwiftUI has no modifier for that without also hiding the back button, so
`backSwipeDisabled()` reaches the enclosing `UINavigationController` and re-enables the gesture on the
way out.

Drawn text is invisible to VoiceOver. `ChapterPageView` therefore publishes the page's text as its own
accessibility label, and `PageTurnView` exposes next and previous page actions. Anything that changes
how the page draws must keep that in step.

### Covers

`CoverCache` is an actor over a directory in Caches. A cover is downloaded once, downsampled through
ImageIO on the way in (which never allocates the full-size bitmap) and stored as JPEG, so scrolling
back through a list costs nothing and a second launch shows covers immediately. Concurrent requests for
the same URL share one download, and `CoverImage` loads only when its row appears, so a 30-item page
fetches the handful of covers actually on screen. Horizontal strips use `LazyHStack` for the same
reason: a plain `HStack` builds every card up front.

`CoverURL` is the other half. The service returns two different shapes for `coverUrl`: `work/details`
and the library give a full `https://cm.author.today/…` URL, while the catalogue gives a bare path like
`2026/07/25/<hash>.jpg`. Feeding that path to `URL(string:)` produces a schemeless URL that
`URLSession` rejects with "unsupported URL", which is why catalogue covers silently failed to load at
all. `CoverURL.absolute` passes absolute URLs through and rebuilds relative ones against the CDN,
asking it to resize on the way — that alone turns a ~450 KB original into ~50 KB.

## Offline and updates

`BookCache` is an actor over a directory in Application Support, excluded from backup because
everything in it is re-fetchable. It stores tables of contents, chapter bodies, the reading shelf, and
per-book snapshots of which chapter ids were present at the last sweep.

The reader is cache-first and network-authoritative: it paints the stored copy immediately, then
replaces it if the network answers. If the network fails while a cached copy is on screen, the failure
is recorded as an offline flag rather than an error, because a readable book beats an error message
about refreshing it.

`ChapterUpdateService` is the sweep. It walks the Reading shelf, diffs each table of contents against
the stored snapshot, downloads the bodies of newly published chapters (capped per run so a long absence
can't run away with data), prunes books that left the shelf, and records the counts.

Two things drive it:

- `BackgroundRefresh` registers a daily `BGAppRefresh` task via SwiftUI's `.backgroundTask`, and
  re-submits the next request on every run so the chain continues.
- The library screen runs the same sweep in the foreground when a day has passed.

The foreground path isn't a nicety. iOS doesn't promise background windows, and on the simulator
`BGTaskScheduler.submit` never fires, so without it the badge could go stale indefinitely.

`UpdateBadge` keeps per-book counts in user defaults, which the UI reads synchronously while drawing,
and sets the app icon badge through `UNUserNotificationCenter`. Opening a book clears its share.

## Testing seams

`SessionStore.applyUITestOverrides` is a `#if DEBUG` hook reading launch arguments:
`-at-ui-test-guest` browses with the guest token, and `-at-ui-test-token <token>` adopts a real one. It
lets UI tests reach any screen without typing credentials, and compiles out of release builds entirely.

See [Testing.md](Testing.md).
