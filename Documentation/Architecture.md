# Architecture

Eight modules, and every edge points one way.

```
                        DesignSystem            BookKit
                             ↑                  ↑  ↑  ↑
                             |      ┌───────────┘  |  └───────────┐
                             |      |              |              |
                             |  BookFormats   BookStorage   BookRenderer
                             |      ↑              ↑              ↑
                             └──────┴──────┬───────┴──────────────┘
                                           |
                            Litres →     Code/  ← AuthorTodayBooks → AuthorToday
```

`BookKit` is where the others meet: what a book, a chapter and a paragraph are, and the protocols that
keep the arrows pointing down. Those are `BookLoader`, the three store roles, `PictureLibrary` and
`BookFormat`. It imports Foundation and nothing else.

Nothing below `Code/` knows how a book is fetched, parsed, laid out, drawn or stored except the one
module whose job that is. What is left in `Code/` is screens, the session, the daily sweep, and the ten
or so lines that hand one module to another.

Three rules the compiler cannot state are checked by `Scripts/check-modules.sh` instead: nothing that
models a book or talks to a service may draw one, only `AuthorTodayBooks` may meet `AuthorToday`, and
`BookRenderer` may never see `DesignSystem`. `Litres` sits outside all of it on Foundation alone: it
fetches files and knows nothing about what a book is, so `Code/` is where a download becomes one. The reader page is set by whoever is reading, and a
system imposed on it would be a system imposed on someone else's book.

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
Components/   CoverImage, BookRow, BookBadges, BookFormatting, DebugReport
Screens/      Login, Library, Series, Search, Top, Work, Reader, Litres, Profile, DesignSystem (Debug)
Services/     SessionStore, CatalogFeed, ChapterUpdateService, BackgroundRefresh,
              ReaderSettings, ReaderFaceNames, BookInbox, BookImporting, Renderers
```

`Services/` is composition, not a layer that got left behind. `SessionStore` builds the client from
constants a build phase on the app target writes; `BackgroundRefresh`'s identifier has to agree with
the Info.plist; `ChapterUpdateService` badges the app icon; `Renderers` is where the typesetter is
handed a store and a picture shelf. None of those can see what they need from inside a package.

### Routing

The tabs and the stacks under them are UIKit. `MainTabs` builds a `UITabBarController`, and each tab
that opens a book is a `UINavigationController` with its screen at the root; the profile pushes nothing
full-height and keeps a stack of its own. A `Navigator` per tab pushes an `AppRoute`, and one
`AppRouteDestination` view resolves it, so a book opened from search, from the charts or from the
library lands on the same screen with the same behaviour.

Two things only UIKit can say. The bar slides out of the way as a list is pulled up when UIKit is
tracking that list itself, which under a `TabView` holding a collection view went in one step and came
back in another. And a pushed screen takes the tab bar with it, which is `hidesBottomBarWhenPushed`
and has no equivalent from outside a `TabView`.

A hosting controller built inside a representable inherits no environment, so `AppDressing` carries
what the app hands its screens and hands it to each of them again, every push included.

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
`Book` is the single presentation struct they all map into, so `BookRow` serves every list.
Adding a fourth source means adding an initialiser, not a view.

### The library

The service's shelves (`Reading`, `Saved`, `Finished`) are the reader's own filing and say nothing
dependable about where they have got to, so the app ignores them and works the state out itself:

- **finished** — written to its end and read to its end. Both, or it isn't finished.
- **caught up** — read as far as it goes, with the author still writing.
- everything else is being read.

The list opens on the books that aren't finished, and the toolbar filter switches to the finished ones
or to all of them.

The filter keeps or hides a whole card rather than picking through it. A series with anything left in
it is still being read and arrives entire, the books already finished included: those are what the
reader is reading through, and a series showing only its unread half would hide where they had got to.
Only a series read to its last book counts as finished, so every card lands under exactly one of the
two. The count beside a filter is books rather than rows, since a series kept for one unread book
brings the rest of itself along, and what helps is how much is left to read.

The library state the service keeps is left doing the one job it does honestly: whether a book is in the
library at all. The book page adds or removes it, a long press in the list removes it, and nothing else
writes it.

The shelf's name and the two menus that act on the whole of it are the navigation bar's. Search
belongs to the tab bar, and the search tab shows what it finds in the library as the same shelves.

A card is one writer's: their series first, then their books that belong to none. Spellings of one
name, with and without a patronymic or in either order, are one writer (`WriterNames`). Leading a book
gives a writer a card, and a co-written book stands on the card of every writer it names who has one; an
anthology would otherwise deal a card to each of its fifteen writers. A series written together from its
first book goes to every card whole, and so does a series the reader put together out of several
writers' runs. Otherwise the shared books stand on the co-author's card on their own, since a run
missing the lead writer's volumes would show them as gaps.

The newest book comes first, by the service's own update time. Reading a book isn't a change to it, so
the list holds still while the reader reads, and books the service dates identically keep a fixed order.

Inside a series a book is called by its title with the series' name and index taken off
(`SeriesNumbering.title`):

- **Name and figure** go from either end: "Name 3. Subtitle", "Name – 3. Subtitle" and
  "Subtitle (Name-3)" are all "Subtitle".
- **A volume word** ("Том 2", "Книга 2") goes where 2 is the volume the file states. Any other figure
  numbers a part of a smaller cycle and becomes "/2".
- **A colon** after the series' name starts the book's own title, so "Name: Subtitle" keeps the name,
  unless the series' other titles read "Name 2: Subtitle", when it goes from all of them alike.
- **Nothing left** means the title was the series' name and its index, and the book is called by the name.

A book's volume is what it states first: the `<sequence>` number in its FB2, or the one the service
gives. A figure read off the titles (`SeriesNumbering.read`) only numbers a book that states none, and
only a figure that changes from title to title counts, so the 99 in "99 Worlds – 2" is part of the name.

Books under one series name are one run when they share a writer, so a volume whose co-author is named
first stays in its series. A label unrelated writers file books under, such as "LitRPG", stays apart.

Whatever the reader says about one book's series is one row in `book_series_override`: the series'
name, the volume, and where they dragged the book. Merging books into a series writes its name into
each book's row, and correcting a book on its details page or from its menu on the shelf writes the
same field, so naming a merged series joins it and naming any other leaves it. The row is laid over the
book whenever the store hands it out, because the service replaces a book's stored copy every time it
answers. An empty name takes the book out of every series, a volume of nought gives it none, and "Use
what the book says" deletes the row. A series name the reader wrote files its books by the name alone,
whoever wrote them, and offers "Break up this series", which clears the name again.

A book marked read or unread turns between cover and spine on its own hinge, the way a whole card does.
A book that leaves a card fades where it stood while the rest close up.

A row has two tap targets: the cover opens the book, and everything else opens its page. Gestures rather
than a button and a link, because the cover sits inside the row's own target and the inner gesture is
the one that wins; nested buttons leave which of the two answers a tap up to SwiftUI. A link would also
draw a disclosure chevron, which is not wanted here. For VoiceOver the row stays one element carrying a
`Read` action, which is how a secondary target is offered.

Inside a series, a book the reader has finished with is one line: a tick and its title. A long series is
read in order, so the books behind the reader only have to stay findable, and given a cover and three
lines each they push the one being read off the screen. A book read to the end of what is written but
still gaining chapters is not collapsed, nor is one carrying new chapters: the next chapter is what the
reader is waiting for, and a collapsed row is the wrong place to be told it arrived.

More than three of those lines in a row fold again, into one line carrying the volumes they cover and
nothing else: the first number, an ellipsis, the last. Four titles behind the reader are four lines
saying the same thing, and a reader twenty books into a series wants the shelf to open on book
twenty-one. Three or fewer stays as it is, being quicker to read past than a line asking to be tapped.
A run whose books carry no numbers has nothing to fold into, so it stays as it is too.

The run has to be sequential, so a book still being read, or a volume missing from the shelf, splits one
long run into two short ones. Tapping the folded line opens it and the next drag on the shelf closes it
again, so nothing accumulates behind a reader scrolling past. Picking books out leaves every row
showing, since a fold would hide the books the reader is reaching for.

The plus button reads an FB2 file into the library. See [LocalBooks.md](LocalBooks.md).

How far the reader has got is a ring on the cover, always 30pt across whatever the cover's size, with
a tick in place of the figure once the book has been read to its end.

### How the shelf is drawn

The library is a `UICollectionView` and everything on it is drawn by hand. `LibraryList` holds the
collection view with a section per author, `AuthorCardView` is the cell, and inside it a `ShelfView`
stands books where `ShelfLayout` puts them. The SwiftUI left around the list owns the sheets and the
alert.

Two things needed it. A book that lands in a different row when a run refolds is the same book, and only
a layout owning every book on the card can say so: as separate SwiftUI rows it was one book leaving and
a different one arriving, which could be carried across but never turned. And a spine is a blurred,
resaturated copy of its own cover, which as a live filter costs a filter per book. `SpinePrint` draws
each one once into a picture and keeps it, so the turn moves a bitmap.

A card knows its own height and the layout is told it. Asking the cell instead, through self-sizing, is
a crash: the card answers from the turn's clock, that disagrees with the layout, the layout invalidates
and asks again, and the clock has moved by then. It never settles, and the collection view trips over
itself a dozen passes down. Heights are `.absolute`, `AuthorCardView.height(across:)` interpolates
between where the card was and where it is going, and the turn's clock invalidates the layout each frame.

Nothing on the shelf is drawn while it scrolls:

- **Every picture is printed once.** A cover is `CoverPrint`, its artwork cut to the board with the
  edge and crease on it, so no cover carries a mask; a spine is `SpinePrint`; the bookcase is
  `BookcasePrint`, a point-wide lid and row for each slot height, stretched across the card by layers
  that share them, with its rounded corners laid on as caps in the screen colour.
- **A book shows a stand-in until its picture is at hand.** The bare board and the bare spine are one
  stretchable picture each, printed before the list is built. The real picture is printed off the main
  actor and fades in over the stand-in (`ArrivalMotion`). Only the side of a book that can be seen is
  printed, and a card that leaves the screen gives up what it was waiting for.
- **Cards measure once.** `LibraryList` keeps each card's height with a hash of what it turns on, and
  works it out again only when that changes. `BookShapes` keeps every book's cover shape and spine
  thickness by book, and the model keeps the library, its cards and its counts until the books, the
  filter, merged series or name aliases change.
- **Books are made ahead.** Views for books come from one pool every shelf shares, filled a few at a
  time after the list appears, and a book makes its gap views and cover marks only when it needs them.

`-at-demo-books 2390` makes up a library of that many books in a Debug build, with covers the cover
cache paints on demand, for looking at how the shelf copes with a big one.

Nothing is built until the cover shapes are read back. A book whose shape nobody has measured is taken
for the commonest one, so a shelf laid out before that read lands stands every book at the wrong height
and shuffles the lot when it arrives.

A book is zoomed into out of the very board its artwork is on. The shelf hands that view over and
`Navigator` gives it to the pushed screen as its `preferredTransition`, so nothing stands in for it.

Menus are described once, as `Deed` values, because the shelf sets them out in UIKit and the rows still
set them out in SwiftUI. Written twice they would drift, and the reader would find a different menu
depending on which of the two they pressed.

### What a book is made of

A spine is printed rather than composed: `SpinePrint` fills the box with the cover, blurs it, and draws
the shading, the head and foot lines and the writing into one picture, keyed by everything that changes
how it comes out.

**The treatment follows the book, not the room.** The blurred cover is measured before anything is done
to it, and a dark book takes the dark treatment, white writing and a dark plate, whatever mode the
device is in: what the writing has to stand against is the picture under it, and a shelf holds both kinds
of book at once. Only a book whose cover has not arrived falls back to the shelf's own scheme.

The whole library's spines are printed before it is scrolled. `SpinePress` walks the cards in the order
they stand, pulls each book's cover off the disk and hands the order to a press of its own: an actor
holding a CoreImage context nobody else draws with, at utility priority, away from the main actor.
Nothing in the drawing belongs to the main thread, so it takes the screen's density and that context as
arguments rather than reading either from wherever it runs. The cache holds ten thousand spines or a
hundred megabytes of them, whichever binds first.

A spine printed on its own artwork is handed back whatever is in memory now. Covers are dropped long
before spines are, and one dropped to make room for another doesn't make the spine printed on it
wrong.

A cover is a board: square along the edge it is bound on, rounded at the two corners that are handled,
and creased where it meets the spine. `Board.crease(_:)` holds that crease in points, and both the
cover's own gradient and a missing volume's face read from it.

A volume the reader doesn't hold is drawn as the book that isn't there would be: a spine's shape and
shading on the edge, a cover's on the face, both at half strength. It turns with its run rather than
sitting still while the books either side of it move.

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

Chapters are paginated rather than scrolled, the column breaks its own lines, and a page fills the
screen. `ChapterContent` parses and binds the text away from the main actor, `ChapterPagination` sets
it, `ParagraphRuler` measures a paragraph once, `ColumnComposer` chooses every break in it together
with how each line is filled, several paragraphs at once and off the main actor, `ChapterLayout` cuts the column into pages under a compositor's rules,
`PageTurnView` turns them and `ChapterPageView` draws one.

A picture is a line of that column with a depth of its own, so the page breaker treats a plate the way
it treats any other line. `BookImages` reads one, decides whether it is colour art or line work, and
draws it in the page's own colours where it is the latter.

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

`held(for:)` answers from memory or the disk and never goes out for a cover, which is what anything
working ahead of a list wants. `SpinePress` reads through it as it prints, and the library's collection
view prefetches with it for the cards about to appear.

Decoded covers are kept on the main actor as well, so a view rebuilt under a new identity draws its
cover in its first frame. A page turn does exactly that to the reader's title page, and going back
through the actor made the cover blink each time. It is bounded by cost as well as by count, since
warming a whole library would otherwise fill it with full-size bitmaps.

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
