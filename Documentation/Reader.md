# The reader

Chapters are paginated, not scrolled, the text is set by TextKit, and the page fills the screen.
Most of what follows exists because one of those three forced it.

## Why not SwiftUI, and why not CoreText

SwiftUI `Text` has no justified alignment, which ruled it out first.

CoreText was the next choice and had to be abandoned as well, because it does not hyphenate.
`hyphenationFactor` and `usesDefaultHyphenation` are TextKit settings and do nothing to a
`CTFramesetter`. Soft hyphens are not a way round it: CoreText will break a line at one and then draw
no hyphen, so a word splits with nothing to show for it, which is worse than not breaking at all. That
was measured, not assumed: a hyphenated line was rendered and its glyphs read back.

Hyphenation matters more here than it would in an English-only reader. Russian words are long, the
column is narrow, and a justified line that cannot break a word stretches the spaces between its
letters instead. `NSLayoutManager`
hyphenates from the system's own dictionaries, in whichever language the text says it is in, and draws
the hyphen.

The cost is that TextKit has to stay on the main actor, which the rest of the design works around.

## Setting the text

`ChapterContent` parses the chapter's HTML, works out which language it is in, and binds the words a
line must not be broken between. All of it happens in a detached task, since none of it is the main
actor's business.

`Typography` is that binding. TextKit will break a line at any space it likes, and both traditions
forbid some of those breaks, though not the same ones:

- Russian will not let a line end on a one- or two-letter preposition, nor begin with a dash.
- English is easier on short words but keeps an abbreviation with the name that follows it.
- Both keep a number with its unit, and an initial with its surname.

An ordinary space followed by a word joiner says so before the text is laid out: one elastic space
that no line may break at. A plain no-break space would be simpler, but it's rigid, and a justified
line pushes the slack it can't take into the gaps between letters.

`ChapterPagination` then sets the chapter as one `NSAttributedString` from a `ChapterTextStyle`: face,
size, line spacing, letter spacing, justification, colour. Margins are deliberately not part of that
style, because they shrink the frame rather than the text. The language the parser detected rides along
as `languageIdentifier`, which is what picks the hyphenation dictionary.

Justification is settled per language, and the style carries both answers because which language a
chapter is in isn't known until it has been parsed. Russian is justified by default: its hyphenation
dictionary is good and its words are long enough to fill a line. English is left-aligned by default,
since a justified narrow column of short words pulls them apart. The reader can set either.

### Hyphenating a justified column

TextKit finds its own break points and settles for fewer than the dictionary knows, which in a narrow
justified column leaves lines it stretches instead of lines it breaks. `hyphenationFactor = 1` moves
one line in a page.

So the breaks are marked before the text is laid out. `Typography.hyphenated` walks every word through
`CFStringGetHyphenationLocationBeforeIndex` and puts a soft hyphen at each position the language's own
dictionary allows, keeping two letters either side of a break. TextKit always sees a soft hyphen, and
draws a hyphen when it breaks there.

Measured on one chapter, 19pt serif at 24pt margins: 34 pages before, 33 after; four hyphens on a page
became seven, and the line that had been stretched letter by letter to fill its measure now breaks the
word after it.

Two things follow from putting characters into the text:

- **Positions are counted without them.** A soft hyphen lands roughly every eight characters, so a
  position that counted them would move the moment the alignment changed. `ChapterLayout` converts
  both ways at its edge, and the rest of the app only ever sees offsets into the text as it arrived.
- **The work happens once.** Marking a chapter costs about as much as laying it out, so it runs in the
  same detached task that parses it, not on every re-pagination. `ChapterContent` carries the marked
  paragraphs beside the plain ones and the layout picks by alignment.

A line broken at a soft hyphen counts as a hyphenated line for the page rules, which is what keeps a
hyphen off the foot of a page. The page's accessibility label strips them.

A chapter opens with its number and title above the body, and `ChapterHeading` leaves the number out
when the chapter's own title already carries one: "Chapter 4" over "Chapter 4. The Road" reads like a
bug. The first chapter of a book is preceded by a title page carrying the cover, title, author and
series.

Most chapters also arrive with their number and title as the opening paragraphs of the body, which put
the same words on the page twice, once in the heading's face and once in the body's. Those paragraphs
are dropped. They are read together rather than one at a time, since a title the contents give as one
line usually reaches the body as two, and each is given up only while everything read so far is still
the opening of the heading, so a chapter whose text merely starts on the same word keeps it. The
comparison is made on letters and digits alone, because by then the text carries the soft hyphens and
word joiners the typesetter put in.

### Filling a justified line

TextKit opens a line's spaces to about 3.1 times the width the font gives one, then takes whatever is
still missing from between the letters. Nothing moves that ceiling: hyphenation, kerning, tracking and
ligatures each justify identically. Past it the words visibly come apart.

So `ChapterLayout` sets those lines itself. It lays the line out again on its own, the way the font
sets it, then draws each word shifted right of where it landed, so all the slack sits between words
and none of it inside them. Spaces open to twice what TextKit allows itself before the words read as
too far apart to be one line.

Two rules shape the result:

- **The dash opening a paragraph of speech keeps the gap the font gives it.** That dash stands at the
  column's left edge as much as the margin does, and stretching the gap after it lands the first letter
  somewhere different in every paragraph, bending the edge down the page. The rest of the line takes
  the slack. Every line opening on a dash is set here, however TextKit left it. Otherwise the gap is
  the font's on the lines TextKit could fill and stretched on the rest.
- **A line that still can't be filled is left short.** A line standing under its measure reads; words
  pulled to pieces don't.
- **A line ending in a hyphen or a comma sets that mark outside the measure.** Those marks are mostly
  the white space around them, so an edge that lines them up with the letters reads as notched wherever
  one falls. Hanging a fraction of the mark past the margin puts the letters back on the line the rest
  of the column keeps. A fraction, not the whole character: hang a comma entirely and the edge bulges
  where the commas are.

Hanging is why a line ending in punctuation is set here at all. Only a line the app sets itself can put
a character outside the measure, so those lines join the crowded ones and the speech lines on this
path, whatever TextKit made of them. A line ending in a letter needs no hang and keeps TextKit's
setting. TextKit draws the hyphen a line breaks on rather than storing it, so the measurement takes
that hyphen's width. The soft hyphen standing in the text has none.

## Cutting the column into pages

`ChapterLayout` sets the chapter as a single column, in slices with a yield between them so a long
chapter never blocks a page turn, and then cuts that column into pages line by line.

Cutting by hand rather than letting TextKit flow the text through page-sized containers is what makes
the rules possible. None of these is allowed at a break:

- a hyphen at the foot of a page,
- an orphan: a paragraph's first line alone at the bottom,
- a widow: a paragraph's last line alone at the top of the next page,
- a heading with fewer than two lines of its chapter under it.

The breaks are chosen for the chapter at once rather than a page at a time. Filling each page in turn
and handing whatever a rule rejects to the next one meant that wherever a rule bit, that one page paid
all of it: a page four lines short between two full ones. So every run of breaks is costed instead, a
page's shortfall counted in lines and squared, and the cheapest run wins. Squaring is what shares the
loss out, since one line missing from each of four pages costs a quarter of what four missing from one
does.

Rules aren't traded against depth. Breaking one costs so much more than any unevenness that they still
decide where a page may break, and evenness only chooses among the breaks they allow. Grading them, so
that a hyphen at a page foot could be bought to even a page out, was tried and dropped: over eight
chapters it bought about half a line of evenness for four hyphens in 173 pages.

A chapter's last page is costed too, so the page before it gives up lines rather than let a chapter end
on a line or two of its own.

What the rules still leave behind is spread between the lines of the page instead of collecting at its
foot. Every page but a chapter's last comes down to the same depth: each gets its own leading, up to
3pt of air per gap, and a gap may be squeezed by 0.75pt to pull one more line on. A page that ends a
chapter keeps its ragged bottom, since it stops where the chapter stops.

Measured over eight generated chapters at a measure of 15.4 lines: 150 of 166 pages carry 14 or 15
lines, 14 carry 13 and two carry 12. The 15-line pages are full, and 3pt of air per gap closes the
14-line ones to within 3pt of full. What the leading can't close is the 13- and 12-line pages, which
are as short as the rules force them to be; raising the 3pt cap is the lever if they ever matter.

What it still doesn't do: nothing caps consecutive hyphenated lines, and a paragraph's last line may
be one short word. Both need control over line breaking rather than page breaking.

## Chapters that run on

A chapter starts on the page the one before it ended on when what is left of that page holds a decent
piece of it: six lines and a quarter of the page, after the air between them. Otherwise it starts a
page of its own.

`ChapterLayout` takes a `startOffset` for that and makes its first page shorter by exactly that much,
and the reader draws such a page from two pieces, one per chapter.

That offset is what makes a chapter's page breaks depend on the chapter before it, whose breaks depend
on the one before that. Measuring a chapter on its own therefore answers differently from measuring it
after reading into it, and the text used to move under the reader when the two disagreed: a chapter
opened from the contents took a page of its own and then jumped up the page as soon as the reader
turned back into the chapter before it.

So `BookPagination` measures the book in one pass, in order from its first chapter, and keeps only
where each chapter starts and how far it runs. Every layout afterwards takes its offset from that pass,
so a chapter sits in the same place however the reader reaches it. The pass throws each layout away as
it goes, so a book of any length costs one chapter's memory at a time, and it runs again whenever the
style or the page size changes, which is what those measurements depend on.

It measures only text the device already holds. Fetching a whole book to find out where its pages fall
would turn opening one chapter into a download of all of them, so a chapter that isn't here yet ends
the run-on and the chapter after it starts a page of its own.

Because a page can show a chapter that hasn't arrived yet, the model's layout cache is observed, not
ignored: a neighbour landing has to redraw the page already on screen.

## The page

A page fills the screen. There is no navigation bar and no strip below the text: the book's title and
the page number are drawn on the page itself, so a turn carries them along with everything else. Each
page names its own chapter and number, since the pages either side of it are on screen during a turn
and belong to their own chapters.

The page ignores the safe area, so its size and the notch and home-indicator insets come from the
window rather than from the layout. Two reasons: an overlay is laid out inside the safe area even when
the view under it is not, and a toolbar coming and going would otherwise re-paginate the chapter.

Drawn text is invisible to VoiceOver, so each page publishes its text as its own accessibility element.

## Turning a page

The whole effect comes from one rule: page `n + 1` always sits above page `n`. Turning forward slides
page `n + 1` in from the right; turning back slides that same page off to the right and uncovers page
`n`. One offset drives both directions, so a half-finished turn can be reversed with no special
handling.

Dragging forward, the incoming page eases in from the right edge to meet the finger over 0.3s and from
then on is held 20pt inside its own leading edge, so the finger is on the page it is pulling. Sliding
it in by the finger's travel alone would leave its edge wherever the drag happened to start, which
reads as pushing a page along from a distance. Re-targeting that animation on every gesture event keeps
it smooth however fast the finger moves.

What lands the turn is the finger's own travel, not how far the page has come, and a flick back cancels
it however far it had got. A turn in flight is dropped when the app leaves the screen, since the
gesture that would have finished it is gone.

The page behind draws back by 5% and darkens as the page in front covers it, and the page in front
carries a shadow along its edge, so the two read as one in front of the other whichever way the turn is
going.

At the end of the book, or before its start, there is no page to turn to and the current one
gives instead: it follows the finger through a rubber band that yields less the harder it is pulled,
reaching at most a fifth of the width, and springs back when the finger lifts.

Taps on either outer third turn forward, and swiping right is the way back. Turning past the end of a
chapter hands over to the next one, and past the start goes back to the previous chapter's last page.
The page the turn animates onto is the neighbouring chapter's own page, so the chapter swaps under the
animation and the reader sees one continuous turn.

Taps that arrive while a turn is still animating are queued instead of dropped, and the queue drains
as each turn commits, running faster while it has a backlog. A burst of taps stacks pages through and
settles where the reader asked.

The system's swipe-from-the-edge-to-go-back gesture is switched off here, because it competes with
swiping back a page. SwiftUI has no modifier for that without also hiding the back button, so
`backSwipeDisabled()` reaches the enclosing `UINavigationController` and re-enables it on the way out.

## The controls

A tap in the middle third brings back the status bar and the navigation bar, a second tap sends them
away, and turning a page sends them away too. The bar is the navigation stack's own, so the back
button, the chapter's name and the two sheet buttons sit and size themselves the way the system draws
them everywhere else. It carries the page's own colour rather than glass, because the running head
passes underneath, and a shadow below it so a bar the colour of the page still has an edge.
`readerBarAppearance` sets both on the enclosing `UINavigationController`: `toolbarBackground` takes a
colour but has no way to ask for a shadow.

It holds the window's light or dark as well, for as long as the reader is on screen.
`preferredColorScheme` did that before, and SwiftUI applies it by overriding the window rather than the
view: leaving the reader reverted SwiftUI's own side of it and left the window's, so the library came
back light underneath a navigation bar and a search field that were still dark. The override has one
owner now, taken when the bar is taken and given back when it is.

Showing it moves no text: the page ignores the safe area and takes its size from the window, so
nothing pagination depends on changes when a bar appears.

## Staying ahead of the reader

Nothing in a turn waits for work that could have been done earlier:

- Parsing, language detection and word binding run in a detached task.
- The chapters either side are laid out while the reader is busy with this one, so crossing a chapter
  break costs a page turn instead of a round trip.
- Chapter bodies come from `LocalStore` before the service is asked, and land there when they arrive.

A chapter over 239 KB is long enough that the reader should be told what is happening, so the layout
reports how far it has got and the page shows a progress bar instead of a spinner. Ordinary chapters
are a fiftieth of that and never see it.

Re-pagination runs whenever the page size or the style changes, and the old layout stays on screen
until the new one is ready. The reader's position survives it because the model keeps a character
offset rather than a page number: a larger font means the same text spans more pages, so a page index
means nothing across a restyle. That offset is also the only reading position that survives a
relaunch, since the service accepts the one it is sent and stores nothing.

A page turn writes it 400ms later, so a run of turns writes once. Leaving the reader and the app
leaving the screen give that wait up: `flushPosition` writes at once and reports upstream whatever the
last coarse step sent, because a suspended app never runs a task that is still waiting.
