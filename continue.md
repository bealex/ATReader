# Where this left off

`main` carries the column rewrite, the picture work and the spacing fix. Every check and every test is
green: 21 package tests, 79 app tests, 22 UI tests with the four search ones skipped.

## What changed

**The column breaks its own lines.** `ColumnComposer` marks the break points, costs every arrangement
of a paragraph's breaks against how hard its lines have to be pushed to fill, and settles the three
levers that fill them. CoreText measures and draws. TextKit is out of the reader entirely.

- `Code/Services/ParagraphRuler.swift` measures one paragraph once, so the width of any piece of it is
  a subtraction, and finds every place it may break.
- `Code/Services/ColumnComposer.swift` holds the levers, the cost and the breaker.
- `Code/Services/ChapterLayout.swift` is down to page breaking and drawing, 432 lines from 1596.

**The reader draws pictures.** An `<img>` is a line of the column with a depth of its own, so the page
breaker already knows what to do with a plate too deep for the space left. Colour art shows as it is
and fades on a dark page; anything monochrome is redrawn in the page's own two colours, and "Follow the
page" in Appearance sends colour art down that path too.

- `Code/Services/BookImages.swift` reads a picture, decides what it is made of, and draws it.
- `Code/Services/FB2/FB2Parser.swift` keeps the binaries the text points at; `BookImport` writes them
  out beside the book.
- `Code/Components/PagePicture.swift` is the title page's cover, on the same rules.

**Books arrive zipped, and their file is kept.** `ZipArchive` reads an archive without a dependency,
and an imported book's own text is kept beside it so the book screen's menu can re-read it in place
when the parser learns something new. That menu is what an older book needs to gain pictures.

- `Code/Services/FB2/ZipArchive.swift` reads the central directory and inflates a member.
- `Code/Services/FB2/LocalBooks.swift` holds where a kept file lives and squeezes it on the way in.
- `BookImport.reimport(workId:)` is the second reading; it never deletes, since removing a book takes
  the reading position with it.

**A line no longer pulls its words apart to fill itself.** An over-open line is priced by how wide its
gaps actually stand rather than by the share they took of the room they had, so a hyphen is now the
cheaper answer wherever one is available. The reported line went from gaps at five times a space to two
and a half.

- `SpacingTests` holds every column to 3.2 spaces, and writes `spacing.txt` beside the renders.
- `Fixtures/Reports/<name>/` is a debug report unzipped. `PageReport` reads it, three suites walk them
  all, and `Scripts/app.sh test` names the directory. A page reported as badly set becomes a fixture by
  being dropped there.

Read `Documentation/Reader.md` on filling a line, on what the breaker weighs besides the fill, and on
pictures. Then `Documentation/History/2026-09/2026-09-04.md` for the spacing measurements, and
`2026-09-03.md` for the column and the pictures.

## Worth looking at next

- **`gapStretch` 1.6 against `letterStretch` 0.035 is still a first setting.** It decides how much
  colour a loose line takes rather than holes, and it was chosen by looking at rendered pages. The
  comfortable ceiling it puts at 2.6 spaces is where nearly every line in the corpus now sits, so
  lowering it is the next thing that would visibly tighten the column.
- **Nothing exercises English ragged-right.** It goes through the same breaker with the levers off and
  the tests are all Russian, so the ragged edge has been read once and never measured.
- **Composition could leave the main actor.** CoreText is thread-safe; what holds it here is `UIFont`
  and drawing into a UIKit context. Moving it would take `BookPagination`'s whole-book pass off the
  main thread, which is the one pass long enough to be felt.
- **One reported page is a thin corpus.** `Fixtures/Reports` holds the one page that was wrong. Every
  page reported from here on belongs there, and until there are several the suites over them prove
  little.
- **Pictures have never been seen in the app itself.** They are verified by rendering: unit tests on
  generated art, and `IllustratedBookTests` on a real FB2. Nothing has yet watched the setting toggle
  or a theme change move a plate on a device, and nothing has watched the re-import menu run.
- **No colour art has been through the real path.** The sample book's 29 plates are all one ink, so the
  colour branch and the dark-page fade are covered by generated pictures only.

## Still open from before

- **The book as a corpus.** Whole chapters parsed from an FB2, and the whole book as a timing pass over
  `FB2Parser` and `BookPagination`, are both unwritten. No book text belongs in this repository; name a
  file in the environment and skip where it's absent, the way `IllustratedBookTests` does.
- **Search is off the tab bar.** `SearchScreen` is untouched and its two UI tests skip. One line in
  `RootScreen` brings the tab back.
- **The tab bar snaps on a pop** rather than travelling with the screen. Putting the stack around the
  tabs fixes the animation and costs the search tab, per-tab paths, and stability: it crashed on a tab
  switch followed by a push, because `navigationDestination` sat on the `TabView`. Reverted in
  `bad7a81`. My reading is that it isn't worth the trade.

## Working here

    Scripts/app.sh build | deploy | test | clean          # never call xcodebuild directly
    Scripts/app.sh deploy --device --device-id <udid>      # two devices are paired, so name one
    Scripts/check.sh                                       # the gate; stop on it, don't commit through it

To see a change instead of arguing about it:

    TEST_RUNNER_AT_RENDER_DIR=$PWD/build/renders/after Scripts/app.sh test --only ATReaderTests

`PageRenderTests` writes a page per setting with a rule down each margin, and `SpacingTests` writes
`spacing.txt` beside them: the loosest lines of every column checked, worst first. Render before a
change and after it, and compare the two directories. Adding `TEST_RUNNER_AT_TEST_BOOK=…` naming an
illustrated FB2 makes `IllustratedBookTests` take a real book through import and write the pages
carrying plates, one per theme and one per setting.

The reader also carries a debug button in debug builds, beside contents and appearance. It writes the
page's text, the settings it was set at, every line's geometry with the reason it stands short, and a
picture of the window.

## Two habits worth keeping

Measure before changing anything. The letters-and-gaps split looked right in the arithmetic and looked
like the old setting on the page; what settled it was rendering both.

A test that records an issue costs ten minutes. `xcodebuild` spends 600 seconds collecting diagnostics
from the simulator after any failure, so a long wait means something failed, not that the layout is
slow. Tune against `spacing.txt` from a passing run rather than against failure output.
