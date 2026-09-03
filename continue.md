# Where this left off

`main` is at `d4abc7f`, tree clean, every check and every test green. The device carries that build.

## Read first

- `Documentation/Reader.md`, the section on filling a justified line. It describes the column as it now
  stands, including the two levers and the reason a line records when it stays short.
- `Documentation/History/2026-09/2026-09-02.md`, which carries the day's findings and the measurements
  behind them.

## The one thing left half-done

**Letters before gaps.** Tracking down a line reads as colour where the same space gathered into the
gaps reads as holes, so the letters should take their share first and the gaps take only what is left.
The column does the reverse today.

Written the other way round the layout collapses: 122 rendering checks fail and lines draw at a
fraction of their width. The piece a line is set in is one measure wide and holds a single line, and
`loosened` checks up front that every glyph fitted. Tracking applied after that check pushes the text
past the measure, since kern is added after every character including the last, so `spread x letters`
comes out a shade over the slack. What doesn't fit is never laid out, and the runs then point at
glyphs that aren't there.

To finish it: apply the tracking, lay the piece out again, check `glyphRange(for:)` still covers every
glyph, and back the spread off until it does. Run the whole rendering matrix before believing it.

## Also open

- **`theEdgeHolds` only counts short lines.** It allows a fifth of the lines to stand short, which
  is loose enough to have passed a page that was visibly wrong. Now that a line carries the reason it
  was left short, that check can ask for the reason instead of counting.
- **The letter spreading in `tightenedText` may be dead.** It was written before the column filled from
  the gaps and the letters together, and may no longer be reached. Worth measuring; if nothing reaches
  it, take it out.
- **The book as a corpus.** A page taken off a device already drives `DevicePageTests`. Whole chapters
  parsed from an FB2, and the whole book as a timing pass over `FB2Parser` and `BookPagination`, are
  both still unwritten. No book text belongs in this repository; name a file in the environment and skip
  where it is absent, the way `DevicePageTests` does.
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

The reader carries a debug button in debug builds, beside contents and appearance. It writes the page's
text, the settings it was set at, every line's geometry with the reason it stands short, and a picture
of the window, and offers the zip to share. That report is what found the last two defects.

To run the tests against a page from one:

    TEST_RUNNER_AT_TEST_PAGE=~/Downloads/atreader-test-page.txt Scripts/app.sh test --only ATReaderTests

The prefix carries: `xcodebuild` strips it and hands the rest to the test process. Without it the page
never arrives and the tests pass having read nothing, which looks exactly like passing.

## Two habits worth keeping

Measure before changing anything. Five readings of `loosened` in a row explained a short line and a
measurement contradicted each one. What settled it was the column recording its own reason.

Look at the page. One rendered page with a rule down the measure answered in a glance what four rounds
of arithmetic had not, and showed that the setting I had been treating as broken was correct.
