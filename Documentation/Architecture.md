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
Components/   CoverImage, WorkRow, WorkBadge, FlowLayout, LoadingOverlay, WorkSummary,
              ChapterPageView, PageTurnView
Screens/      Login, Library, Search, Top, Work, Reader, Profile
Services/     SessionStore, KeychainStore, LocalStore, CoverCache, CatalogFeed,
              ChapterContent, Typography, ChapterPagination, ChapterLayout,
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

### The library

The service's shelves (`Reading`, `Saved`, `Finished`) are the reader's own filing and say nothing
dependable about where they have got to, so the app ignores them and works the state out itself:

- **finished** — written to its end and read to its end. Both, or it isn't finished.
- **caught up** — read as far as it goes, with the author still writing.
- everything else is being read.

The list opens on the books that aren't finished, and the toolbar filter switches to the finished ones
or to all of them, with the count beside each counted through the same rule. The library state the
service keeps is left doing the one job it does honestly: whether a book is in the library at all. The
book page adds or removes it, a long press in the list removes it, and nothing else writes it.

The shelf carries no navigation bar. It has room to name itself, and search belongs to the tab bar,
where the search tab takes the search role. The library keeps a field of its own, because filtering it
by title isn't the same question as searching the catalogue.

Books in a series stand together in one card, latest book first, so a set reads as a set; a book in no
series is a card of its own. A series can carry more than one author, so the author belongs to the row
rather than the card's heading. The newest book comes first, by the service's own update time. Reading
a book is not a change to it, so the list holds still while the reader reads instead of rearranging
under them, and books the service dates identically keep a fixed order rather than whatever the
grouping happened to produce. Rows are buttons rather than `NavigationLink`s, which is the only way a
row goes without a disclosure chevron.

The plus button reads an FB2 file into the library. See [LocalBooks.md](LocalBooks.md).

How far the reader has got is a ring on the cover, always 30pt across whatever the cover's size, with
a tick in place of the figure once the book has been read to its end.

### The book page

The chapter list is a checklist. The device keeps one reading position per book, so the rest is
arithmetic on the chapter order: everything before the chapter it names has been read, the chapter
itself is filled as far as the position goes, and the rest are untouched. A chapter that costs money
carries a `$` in place of its mark, and the ones without it in a paid book are the free ones.

Whether a book still has to be bought is read off what is locked rather than off `isPurchased`: the
service leaves that field out for a guest, and a missing field is not a "no". A sold book with a
chapter closed to this reader has not been bought. A list row has no contents to go on, so it shows
the marker only where the service positively says the book is unbought.

The blurb is cut to five lines with a control to open it. Whether it was cut at all takes measuring: a
hidden copy with no limit is laid out at the same width, and being taller than the visible one is what
puts the control there.

### CatalogFeed

Search and the charts hit the same endpoint with different queries, so they share one paging engine.
It de-duplicates by id across pages, since the service occasionally repeats an entry near a page
boundary, tracks `isLastPage`, and rolls the page number back if a page fails so a retry doesn't skip
content.

## The reader

Chapters are paginated rather than scrolled, the text is set by TextKit, and a page fills the screen.
`ChapterContent` parses and binds the text away from the main actor, `ChapterPagination` sets it,
`ChapterLayout` cuts the column into pages under a compositor's rules, `PageTurnView` turns them and
`ChapterPageView` draws one.

It is the most intricate part of the app and has its own document: [Reader.md](Reader.md). Read it
before changing anything about layout, pagination or the page turn.

## Covers

`CoverCache` is an actor over a directory in Application Support rather than Caches. A shelf that
empties itself the first time the device runs low on space is worse than one that holds a bounded
number of small files, so it keeps 2000 covers and drops the least recently used beyond that.

A cover is downloaded once, downsampled through ImageIO on the way in (which never allocates the
full-size bitmap), stored as JPEG and handed back already decoded for display, so the main thread never
decodes one. Concurrent requests for the same URL share one download. `CoverImage` loads when its row
appears, and the library warms the whole shelf in the background once it has loaded, so covers are
there before the row is.

Decoded covers are kept on the main actor as well, so a view rebuilt under a new identity draws its
cover in its first frame. A page turn does exactly that to the reader's title page, and going back
through the actor made the cover blink each time.

`CoverURL` is the other half. The service returns two different shapes for `coverUrl`: `work/details`
and the library give a full `https://cm.author.today/…` URL, while the catalogue gives a bare path like
`2026/07/25/<hash>.jpg`. Feeding that path to `URL(string:)` produces a schemeless URL that
`URLSession` rejects with "unsupported URL", which is why catalogue covers silently failed to load at
all. `CoverURL.absolute` passes absolute URLs through and rebuilds relative ones against the CDN,
asking it to resize on the way, which alone turns a ~450 KB original into ~50 KB.

## Offline and updates

Positions come back from the service even though they never go to it. `adoptServerPositions` reads
`/v1/account/reading-progress` when the library loads and takes any position newer than the device's
own, which is how a book read on the website opens here where it was left. Progress arrives as a
percentage of the chapter, and the chapter's stored length turns it into the offset the reader works
in; where the device has no contents for that book yet, the position lands at the chapter's start.

Reading progress is otherwise the device's own. The service accepts what it is sent and stores nothing, so its
figure only moves when the reader reads somewhere else; `LocalStore` keeps a column beside each book
that the reader writes as it goes and that "mark as read" fills.

That column is worked out again rather than remembered. A fraction goes stale the moment the author
publishes, because all of yesterday's book is less than all of today's, and a book left at 100% would
sit on the Finished shelf with a chapter in it nobody has read. The position doesn't go stale: it names a chapter
and an offset into it. So `LocalStore` works the fraction out again from the position and the chapter
lengths whenever either is written, which is what puts a book back on the Reading shelf the moment it
grows.

`LocalStore` is an actor over one SQLite file in Application Support, excluded from backup because
everything in it is re-fetchable. It holds the books and their shelves, tables of contents, chapter
bodies, chapter text the typesetter has already been through, and the reading position.

One thing in it isn't: a book imported from a file is here and nowhere else. See
[LocalBooks.md](LocalBooks.md).

Reading positions live here and nowhere else. The service accepts `reader/update-progress` and stores
nothing (see [API.md](API.md)), so the character offset the store keeps is the only position that
survives a relaunch.

Every screen is store-first and service-authoritative: it paints what the device has, then replaces it
when the network answers. What the network answers is written to the store and read back from it, and a
screen assigns a field only where the stored value differs, so a refresh behind a page someone is
already reading moves the parts that moved and nothing else. A loading overlay covers the screen only
while there is nothing on it, since the stored copy is the whole point of keeping one. A failure while
stored content is on screen sets an offline flag rather than raising an error, because a readable book
beats a message about refreshing it.

`ChapterUpdateService` is the sweep. It walks the library, stores every book and its contents, counts
the chapters the device has never seen, downloads their bodies and then spends what's left of its
budget backfilling chapters that are still missing, so a book being read converges on being readable
offline. It sweeps the books the reader has started and not finished, which is the set that can have a
chapter they haven't seen. The budget is smaller in the background, where the window is short and overrunning it
gets the app killed.

Two things drive it:

- `BackgroundRefresh` registers a daily `BGAppRefresh` task via SwiftUI's `.backgroundTask`, and
  re-submits the next request on every run so the chain continues.
- The library screen sweeps behind every load and every pull-to-refresh, and once a day sweeps the
  whole shelf.

The foreground path isn't a nicety. iOS doesn't promise background windows, and on the simulator
`BGTaskScheduler.submit` never fires, so without it the badge could go stale indefinitely.

Reloading the shelf cannot answer "is there anything new to read?", because the shelf carries no
chapters. What it does carry is each book's update time, and a book whose time has moved is the only
one worth asking for a table of contents, which keeps the sweep behind a refresh to a request or two
and leaves the list responsive while it runs. The daily pass walks every book and spends the download
budget; only that pass dates `lastCheckedAt`, and clearing a book's count when the reader opens it
doesn't, or reading daily would push the next full pass a day out every time.

`UpdateBadge` keeps per-book counts in user defaults, which the UI reads synchronously while drawing,
and sets the app icon badge through `UNUserNotificationCenter`. Opening a book clears its share.

## Testing seams

`SessionStore.applyUITestOverrides` is a `#if DEBUG` hook reading launch arguments:
`-at-ui-test-guest` browses with the guest token, and `-at-ui-test-token <token>` adopts a real one.
`RootScreen` reads one more, `-at-ui-test-reader <workId>`, which opens straight into the reader.
Together they let a test reach any screen without typing credentials, and all of it compiles out of
release builds.

Reader settings are read through `UserDefaults`, which also reads `-key value` launch arguments, so a
test pins the typography it depends on rather than inheriting whatever the last run left behind.

See [Testing.md](Testing.md).
