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
Services/     SessionStore, KeychainStore, LocalStore, CatalogFeed, ChapterLayout,
              ChapterUpdateService, BackgroundRefresh, ReaderSettings
```

### Routing

Each tab owns a `NavigationStack` over a shared `AppRoute` enum, and every stack resolves routes
through one `AppRouteDestination` view. A book opened from search, from the charts or from the library
therefore lands on the same screen with the same behaviour, without the tabs sharing navigation state.

### Session

`SessionStore` owns the client and the signed-in user, and is the only thing that touches
`KeychainStore`. It exposes three states (restoring, signed out, signed in) and `RootScreen` switches
on them. Token, its expiry, the account id and the last known `UserInfo` go to the keychain; nothing
sensitive reaches user defaults.

The session is meant to outlive the token. Tokens last a day, and three things keep one current:

- `AuthorTodayClient` retries a request once behind a refresh when the service rejects the token, and
  reports every token it adopts through `credentialsDidChange`, which is what persists it.
- `SessionStore.refresh()` renews a token within twelve hours of expiry at launch and every time the
  app comes back to the foreground.
- Only a rejected token signs the reader out. A launch with no network restores the stored user and
  sets `isOffline`, so the app opens on the library rather than the sign-in screen.

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

Chapters are paginated rather than scrolled, and the text is laid out by TextKit rather than by SwiftUI
`Text`, which has no justified alignment.

CoreText was the first choice and had to be abandoned: it does not hyphenate. `hyphenationFactor` and
`usesDefaultHyphenation` are TextKit settings and do nothing to a `CTFramesetter`, and although CoreText
will break a line at a soft hyphen, it draws no hyphen when it does, which leaves a word split with
nothing to show for it. Without hyphenation a justified narrow column pulls the letters of a Russian
word apart to fill the line. `NSLayoutManager` hyphenates from the system's own dictionaries, in
whichever language the run carries.

`ChapterPagination` builds the chapter as one `NSAttributedString` from a `ChapterTextStyle` (face,
size, line spacing, justification, colour). Margins are deliberately not part of the style: they shrink
the frame, not the text. `ChapterContent` parses the HTML and works out the language away from the main
actor, and that language goes onto the text as `languageIdentifier`, which is what picks the
hyphenation dictionary.

`ChapterLayout` is the result: one chapter laid out for one style and one page size. It is set as a
single column, in slices with a yield between them so a long chapter never blocks a turn even though
TextKit has to stay on the main actor, and then cut into pages line by line. `ChapterPageView` takes a
layout and a page index and does nothing but draw, which means a page can never show something
pagination didn't measure.

### What the page breaker will not do

Cutting the column by hand rather than letting TextKit fill page-sized containers is what makes the
rules possible. A break moves back up to four lines to avoid any of these, stopping at four lines left
on the page, which is the one rule that outranks the others:

- a hyphen at the foot of a page,
- an orphan: a paragraph's first line alone at the bottom,
- a widow: a paragraph's last line alone at the top of the next page,
- a heading with fewer than two lines of its chapter under it.

A chapter whose last page would carry a line or two is fed from the page before it. What the rules leave
behind is spread between the lines of the page rather than dumped at its foot: each page gets its own
leading, up to 3pt of air per gap, and a gap may be squeezed by 0.75pt to pull one more line on. A page
left half empty is the end of a chapter, and keeps its ragged bottom.

Measured over four chapters of a novel: no hyphens at a page foot, no widows, one orphan in 87 pages,
and pages steady at a median of 15 lines.

Some line breaks are wrong before pagination sees them, and the two languages disagree about which.
`Typography` binds them with no-break spaces when the chapter is parsed: Russian will not end a line on
a one- or two-letter preposition nor begin one with a dash; English keeps an abbreviation with the name
after it. Both keep a number with its unit and an initial with its surname.

### Chapters that run on

A chapter starts on the page the one before it ended on when what is left of that page holds a decent
piece of it: six lines and a quarter of the page, after the air between them. `ChapterLayout` takes a
`startOffset` for that, its first page being shorter by exactly that much, and the reader draws such a
page from two pieces, one per chapter. Layouts are therefore prepared in order forwards, since each one
depends on where the one before it ended; a chapter opened from the contents starts a page of its own,
and is laid out again if the reader later arrives at it from the chapter before.

Nothing in a turn waits for work that could have been done earlier:

- Parsing and language detection run in a detached task.
- The model lays out the chapters either side of the current one while the reader is busy with it, so
  crossing a chapter break costs a page turn rather than a round trip.

A chapter over 239 KB is long enough that the reader is told what is happening: the layout reports how
far it has got and the page shows a progress bar instead of a spinner.

The view triggers re-pagination whenever the page size or the style changes, and the old layout stays
on screen until the new one is ready. The reader's position survives it because the model remembers a
character offset rather than a page number. A larger font means the same text spans more pages, so the
page index alone is meaningless across a restyle.

A chapter opens with its number and title set above the body, and the first chapter of a book is
preceded by a title page carrying the cover, title, author and series. `ChapterHeading` leaves the
number out when the chapter's own title already carries one, since "Chapter 4" above "Chapter 4. The
Road" reads like a bug.

A page fills the screen. There is no navigation bar and no strip below the text: the book's title and
the page number are drawn on the page itself, so a turn carries them along with the text. Because the
page ignores the safe area, its size and the notch and home-indicator insets come from the window
rather than from the layout, which also keeps a toolbar appearing from re-paginating the chapter.

A tap in the middle third brings back the status bar and the controls, a second tap sends them away,
and turning a page sends them away too. The controls are Liquid Glass where the system has it, and
plain buttons on iOS 18. The bar is the reader's own rather than the navigation stack's, so it fades in
over the page instead of sliding the page down, and it carries a background of its own
so the running head doesn't show through it. Only that background runs up to the screen edge: the
overlay is laid out inside the safe area even though the page under it is not, so insetting the bar by
hand as well would push its controls a notch's worth too low.

A turn in flight is dropped when the app leaves the screen, since the gesture that would have finished
it is gone.

`PageTurnView` handles the turn. The entire effect comes from one rule, that page `n + 1` always sits
above page `n`, so a single offset drives both directions: turning forward slides page `n + 1` in from
the right, turning back slides that same page off to the right and uncovers page `n`. A half-finished
turn can therefore be reversed with no special handling. Progress runs `0…1`, where `0` is the resting
state and `1` is committed, and the gesture measures against the turn's own direction so a reversed
finger unwinds it.

Dragging forward, the incoming page eases in from the right edge to meet the finger over 0.3s and from
then on is held 20pt inside its own leading edge, so the finger is on the page it is pulling.
Sliding it in by the finger's travel alone would leave the page's edge wherever the drag happened to
start, which reads as pushing a page along from a distance. Re-targeting the run-in animation on every
gesture event keeps it smooth however fast the finger moves. What lands the turn is the finger's own
travel, not how far the page has come, and a flick back cancels it however far it had got.

The page behind draws back by 5% and darkens as the page in front covers it, and the page in front
carries a shadow along its edge, so the two read as one in front of the other whichever way the turn is
going.

At the very end of the book, or before its very start, there is no page to turn to and the current one
gives instead: it follows the finger through a rubber band that yields less the harder it is pulled,
reaching at most a fifth of the width, and springs back when the finger lifts.

Taps on either outer third turn forward and swiping right is the way back. Turning past the end of a
chapter hands over to the next one, and past the start goes back
to the previous chapter's last page. The page the turn animates onto is the neighbouring chapter's own
page, so the chapter swaps under the animation and the reader sees one continuous turn.

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

`CoverCache` is an actor over a directory in Application Support rather than Caches. A shelf that
empties itself the first time the device runs low on space is worse than one that holds a bounded
number of small files, so it keeps 2000 covers and drops the least recently used beyond that.

A cover is downloaded once, downsampled through ImageIO on the way in (which never allocates the
full-size bitmap), stored as JPEG and handed back already decoded for display, so the main thread never
decodes one. Concurrent requests for the same URL share one download. `CoverImage` loads when its row
appears, and the library warms the whole shelf in the background once it has loaded, so covers are
there before the row is.

`CoverURL` is the other half. The service returns two different shapes for `coverUrl`: `work/details`
and the library give a full `https://cm.author.today/…` URL, while the catalogue gives a bare path like
`2026/07/25/<hash>.jpg`. Feeding that path to `URL(string:)` produces a schemeless URL that
`URLSession` rejects with "unsupported URL", which is why catalogue covers silently failed to load at
all. `CoverURL.absolute` passes absolute URLs through and rebuilds relative ones against the CDN,
asking it to resize on the way — that alone turns a ~450 KB original into ~50 KB.

## Offline and updates

`LocalStore` is an actor over one SQLite file in Application Support, excluded from backup because
everything in it is re-fetchable. It holds the books and their shelves, tables of contents, chapter
bodies and the reading position.

Reading positions live here and nowhere else. The service accepts `reader/update-progress` and stores
nothing (see [API.md](API.md)), so the character offset the store keeps is the only position that
survives a relaunch.

Every screen is store-first and service-authoritative: it paints what the device has, then replaces it
when the network answers. A failure while stored content is on screen sets an offline flag rather than
raising an error, because a readable book beats a message about refreshing it.

`ChapterUpdateService` is the sweep. It walks the library, stores every book and its contents, counts
the chapters the device has never seen, downloads their bodies and then spends what's left of its
budget backfilling chapters that are still missing, so a book on the Reading shelf converges on being
readable offline. The budget is smaller in the background, where the window is short and overrunning it
gets the app killed.

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
