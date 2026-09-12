# The reader

Chapters are paginated, not scrolled, the column breaks its own lines, and the page fills the screen.
Most of what follows exists because one of those three forced it.

## Why the breaking is ours

SwiftUI `Text` has no justified alignment, which ruled it out first.

TextKit can set a justified column, but it can't choose where a line ends and how that line is filled
as one decision. It breaks greedily, taking all it can each time and justifying whatever it took, so a
line standing before a long word is left holding too little and has to open wide, while the text that
would have filled it sits above it in lines already settled.

So `ColumnComposer` breaks each paragraph itself. Every arrangement of its breaks is costed by how hard
the lines it makes have to be pushed to reach the measure, and the cheapest wins. `ParagraphRuler`
measures the paragraph once beforehand, so the width of any piece of it is a subtraction rather than a
fresh measurement, which is what makes costing every arrangement affordable. CoreText measures and
draws, and chooses nothing.

CoreText on its own would be no better. It treats a soft hyphen as a place it may break a word and then
draws no hyphen there, which is worse than not breaking at all. That's an objection to letting
`CTTypesetter` pick the breaks. This column marks its own break points and draws its own hyphens, so
CoreText is left with the shaping of a line whose text is already settled.

Hyphenation matters more here than it would in an English-only reader. Russian words are long, the
column is narrow, and a justified line that can't break a word has to stretch instead.
`Typography.hyphenated` walks every word through the system's dictionary for the language the text is
in and marks every break that dictionary allows.

`ColumnComposer` sets a chapter's paragraphs away from the main actor, on up to four workers at once,
since a paragraph's lines depend on nothing outside it. An attributed string can't cross from one thread to
another, so each worker typesets its own copy of the chapter and hands back plain values: where each
line breaks and how it's filled. `ChapterLayout` builds a line's `CTLine` from those only when a page
draws it, so measuring a book draws nothing. A fifth worker adds no speed, because every change to an
attributed string takes a lock UIFoundation shares across the process.

## Setting the text

`ChapterContent` parses the chapter's HTML, works out which language it is in, and binds the words a
line must not be broken between. All of it happens in a detached task, since none of it is the main
actor's business.

`Typography` is that binding. A line may break at any space, and both traditions forbid some of those
breaks, though not the same ones:

- Russian will not let a line end on a one- or two-letter preposition, nor begin with a dash.
- English is easier on short words but keeps an abbreviation with the name that follows it.
- Both keep a number with its unit, and an initial with its surname.

An ordinary space followed by a word joiner says so before the text is laid out: one elastic space
that no line may break at. A plain no-break space would be simpler, but it's rigid, and a justified
line pushes the slack it can't take into the gaps between letters.

### Which dash is which

Files write dashes with whatever key was to hand, and one publisher's habit runs through every book it
sets. Both sample FB2 files carried no em dash at all: every dash between words and every dash opening
a line of speech was a spaced en dash, roughly 3,000 of them per book.

The traditions differ, so the rule is settled per language:

- **Russian** puts тире (—) between words and at the head of a line of speech, and a hyphen only inside
  a word. A spaced en dash or a spaced hyphen is the wrong mark outright.
- **English** keeps the spaced en dash as a convention of its own, so that one is left alone. Only a
  spaced hyphen is promoted to it.
- **Both** set a range between figures with an en dash.

A dash inside a word is never touched. Russian is full of them, and a book of `кто-то` rewritten with
тире would be unreadable.

Every replacement is one character for one, because a reading position is an offset into this text and
a substitution that changed its length would move the reader's place in every book already on the
device. That rules out folding `--` into an em dash, which is the one common repair this doesn't make.

Putting the dashes right comes before binding, since binding reads them, and so does the layout when it
decides which lines open on the dash of speech.

`ChapterPagination` then sets the chapter as one `NSAttributedString` from a `ChapterTextStyle`: face,
size, line spacing, letter spacing, justification, colour. Margins are deliberately not part of that
style, because they shrink the frame rather than the text. The language the parser detected rides along
as `languageIdentifier`, which is what picks the hyphenation dictionary.

Justification is settled per language, and the style carries both answers because which language a
chapter is in isn't known until it has been parsed. Russian is justified by default: its hyphenation
dictionary is good and its words are long enough to fill a line. English is left-aligned by default,
since a justified narrow column of short words pulls them apart. The reader can set either.

### Hyphenating a justified column

The breaks are marked before anything is measured. `Typography.hyphenated` walks every word through
`CFStringGetHyphenationLocationBeforeIndex` and puts a soft hyphen at each position the language's own
dictionary allows, keeping two letters either side of a break. The column takes those as break points
of its own and draws a hyphen wherever it uses one. A soft hyphen has no width, so a line that breaks
on one is measured with the width of the hyphen that will stand in its place.

A hyphen the author wrote is a break point as well, `кто-` before `то`, with two letters wanted either
side and nothing added, since the hyphen is already there.

Two things follow from putting characters into the text:

- **Positions are counted without them.** A soft hyphen lands roughly every eight characters, and the
  marks are the typesetter's rather than the book's, so a position that counted them would not answer
  to the text as it was written. `ChapterLayout` converts both ways at its edge, and the rest of the
  app only ever sees offsets into the text as it arrived.
- **The work happens once.** Marking a chapter costs about as much as laying it out, so it runs in the
  same detached task that parses it, not on every re-pagination. `ChapterContent` carries the marked
  paragraphs beside the plain ones, and the layout sets from the marked ones whatever the alignment.

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

### Filling a line

A line has three levers, and the first two move together rather than in turn:

- **The gaps between the words**, opened by up to 1.6 times the width the font gives a space.
- **The letters**, tracked apart by up to 3.5% of the type size.
- **The glyphs**, drawn up to 1.2% wider.

The first two reach their ceiling at the same moment, so the share each takes falls out of the line
instead of being settled in advance: a line of a few long words leans on its letters, a line of many
short ones leans on its gaps. Tracking spread down a line reads as colour where the same space gathered
into the gaps reads as holes, which is why the letters take a share from the start rather than only
what the gaps leave over.

Past that point the gaps go on alone, out to six times a space, and the tracking stops. Letters set
further apart than that stop reading as colour and start reading as a different face. The glyphs are
the last lever and by far the smallest, because widening one changes its weight, which shows sooner
than space does.

What a gap costs out there is counted in space widths, not as a share of the room it has left. The room
runs a long way, so a share of it says nothing about how wide the gap looks: half a space past the
comfortable point costs about what breaking a word costs, and a whole space past it costs more than
breaking two. So the breaker goes looking for something better first, and a line only stands wide open
where it has a single gap to fill itself from and nothing to rearrange.

The levers run the other way too. A line may close its gaps by three tenths of a space and its letters
by a fiftieth of the type size, which is what sets a paragraph a fraction too wide without breaking a
word, and what lets a line draw a word up from the one below it. Room to set a line tight is also what
makes the breaking a choice at all: if a line could only be opened, filling each one as full as it goes
would be the cheapest arrangement there is and no rearranging could beat it.

Three rules stand outside the arithmetic:

- **The dash opening a paragraph of speech keeps the gap the font gives it.** That dash stands at the
  column's left edge as much as the margin does, and stretching the gap after it lands the first letter
  somewhere different in every paragraph, bending the edge down the page. The rest of the line takes
  the slack.
- **A line ending in a hyphen or a comma sets that mark outside the measure.** Those marks are mostly
  the white space around them, so an edge that lines them up with the letters reads as notched wherever
  one falls. A fraction of the mark hangs rather than the whole character: hang a comma entirely and
  the edge bulges where the commas are.
- **A line none of the levers can fill stands short and records why.** A line under its measure reads;
  words pulled to pieces don't. The debug report prints the reason and the tests ask for it, since from
  outside the decision can only be guessed at.

### What the breaker weighs besides the fill

Filling is most of what a line costs, but four other things are priced against it:

- **A broken word**, so a hyphen is taken only where it buys more than it costs.
- **A second broken word directly under the first**, dearer again, which is what keeps hyphens from
  stacking down the page.
- **A broken tie.** The binder holds a short preposition to the word after it so that no line ends on
  one, and that pair can be wider than what a line has left. Where the gap it would leave reads worse
  than the broken rule, the breaker gives up the tie rather than the line.
- **A stub last line.** A paragraph's last line takes whatever is left, but one holding less than a
  sixth of the measure reads as a mistake, so the line above it gives a word down.

Ragged-right paragraphs go through the same breaker with the levers switched off, so the edge is as
even as the words allow and no line is stretched to make it so. They're hyphenated like any other
setting, a word that breaks shortening the rag.

## Pictures

A picture is a line of the column like any other. It has a depth, the page breaker treats it as one
tall line, and the slack around it is spread the way the slack around a paragraph is. So a plate never
runs off the foot of a page.

`BookHTML` reads an `<img>` as a block of its own and `ChapterPagination` sets it as a single
character carrying the picture on an attribute of that character. One character rather than none, so a
reading position counts a picture the way it counts a paragraph and stays put across a change of font.
Drawn art says nothing to VoiceOver, so the page names it in place of that character.

A picture takes the whole measure, but is never blown up past one of its own pixels to the point: a
small decoration stays small rather than becoming a blurred plate. One too deep for the page gives up
width until it fits.

### Which colours a picture takes

Nothing in a file says whether a picture is colour art or line work, so `BookImages` reads it off the
pixels. A picture counts as colour when more than a fiftieth of its solid pixels carry any.

- **Colour art is shown as it was drawn**, faded a little on a dark page so it doesn't glare beside the
  text.
- **Anything monochrome is redrawn in the page's own two colours.** Line art, a grey scan and a black
  plate on nothing all go this way.

A monochrome picture keeps its own light and dark. What is black in the file lands on the deeper of the
page's two colours and what is white lands on the paler one, whichever of the foreground and the
background each of those happens to be. So a drawing is never turned into a negative of itself: on a
night page it comes out as pale paper with dark ink, in the theme's own colours rather than the file's.

What is kept is how dark each pixel is, alpha included, as a grey picture of its own. Whatever was
never drawn on counts as light, since the paper is what showed through there. The page lays its paler
colour down whole and paints the deeper one over it through that shading, which is what turns a grey
into a mixture of the two rather than one or the other.

Holding the shading rather than a tinted copy is what makes the reader's own setting cheap. "Follow the
page" in Appearance sends colour art down the same path for the cost of two fills, rather than a second
reading of the picture. Reading one means looking at every pixel, so it happens once, away from the
main actor, and what comes back is plain bytes that cost nothing to wrap as a `CGImage`.

### Where a picture sits on the page

A page's spare room is spread between its lines, and what no amount of leading can absorb goes around
the pictures instead of collecting at the foot of the page. Each picture is centred in everything the
page gave it, its own line's spacing included, so what stands above it matches what stands below.

A page that ends a chapter keeps its ragged bottom, since its text stops where the chapter stops. Its
spare room therefore stands after the last line rather than being spread through the page, and only a
picture standing at the end of one has any of that room beneath it to be centred in. That is the page a
part title makes: a heading, a plate, and nothing after it. A picture with the chapter's last words
below it already sits where it belongs and is left alone.

The title page's cover answers to both rules, being a page of the book. Covers elsewhere in the app are
drawn plainly, since there's no page tint out there to answer to.

## Notes

A note is an aside the text points at, and a book carries them two ways. A chapter from the service
anchors into itself, `<a href="#n1">1</a>`, with the note's own words further down under `id="n1"`. A
file keeps its notes in a body of their own at the end, far past the chapter that refers to them, so
`FB2Parser` carries each note down to the chapters whose anchors name it and writes it out as the same
markup. Everything after that reads one shape.

`BookHTML` lifts the words out, drops the block that held them, and records where each marker stands.
A note nothing points at stays in the chapter as ordinary text, since it was never a note; an anchor
with nothing behind it stays as the characters it always was, rather than opening an empty popup. An
anchor carrying its words on a `title` attribute is read the same way as one pointing at a block.

**The marker keeps the characters the text gave it.** A reading position is an offset into that text,
so renumbering a marker would move the reader's place in every book already on the device. What
changes is how it is set: `ChapterPagination` gives those characters a smaller face, raises them off
the line and hangs the note's id on them, the way a picture hangs on the character standing for it.
The raise is short of a printed superscript's, because the column takes its line height and its
baseline from the body font and a marker climbing past the body's own ascent would foul the line above.

**The offset is negative.** The page draws through a flipped text matrix, so CoreText's own upwards is
the page's downwards, and asking for a positive rise sinks every marker below its line.
`NoteMarker.baselineOffset(forFontSize:)` is where that sign lives, so there is one place to read it
and one thing to test.

Markers travel as offsets into the text as it arrived, not as it was set. Binding and hyphenation both
put characters in, so a mark counted straight through would drift a little further with every word
joiner and soft hyphen before it; `ChapterContent` counts only the characters the text came with, the
same way a reading position is counted.

`ParagraphRuler` measures the real attributed text rather than a font of its own, so a marker set
smaller measures smaller and the lines around it are filled to the width they actually take.

### Figures off the line

A formula writes `CH<sub>3</sub>OH`, and the page used to read it as `CH3OH`, because the markup is
flattened with one pass that strips every tag. `<sub>` and `<sup>` are fenced first, with private-use
characters the stripper has no opinion about, and read back out of the flat text as ranges. So the
characters the text arrived with are the characters that come out, and every reading position stays
where it was.

`ChapterContent` moves those ranges when binding and hyphenation put characters in, the way it moves a
note's marker, and `ChapterPagination` sets them at the marker's size. `ScriptMarker` says how far one
drops below the line; a lifted one takes `NoteMarker.rise`, and both signs are the flipped matrix's.

### Tapping one

A marker is two or three points across, and it stands inside the third of the page that turns it. So
the page is asked about a note before the turning zones see the tap, and a marker's target is widened
to a finger's width about its own middle, which makes it findable without moving it.

The tap is resolved the way the page is drawn: the same walk down the lines, then the marker's own
glyph run, which carries the note's id. Reading it off the run saves counting characters back through
the soft hyphens the line was set with.

The note opens as a `Callout` hung over the marker, in the page's own colours and face, since these are
the book's words rather than the app's chrome. Its text goes through `BookTextView`, which runs the
typesetter over it: a note is hyphenated and filled the way a page is. That view lays out with a margin
of its own, because the column hangs a line-ending comma or hyphen outside its measure and without one
those marks fall off the edge.

Drawn text is invisible to VoiceOver and a marker cannot be touched there, so the page offers its notes
as actions of its own instead.

## Bookmarks

A bookmark is a stretch of a chapter rather than a point in it: what a reader marks is what they can
see, and a page set in one face is a different page set in another. The bar's own button marks what
is on the screen, or clears every mark the page stands on, and a page carrying two chapters marks
both stretches.

A mark stopping exactly where the next page begins belongs to the page before it. Counted the other
way, every page would open showing itself already marked.

They stand under their chapters in the contents and in the book's details, with how far into the
chapter each one is, and open the book where they stand. `LocalStore` is where they live, like
everything else the reader does.

## Picking text off the page

A drawn page has no selection of its own, so `ChapterSelection` works out every part of one. Which
character a point is over comes from the same walk down the lines the page is drawn by, then
`CTLineGetStringIndexForPosition`. That index counts the line as CoreText was given it, carrying none of
the soft hyphens or word joiners the typesetter put in, so it is converted back by counting the
characters that are not those: the same arithmetic the note markers travel by.

Word boundaries treat those buried marks as part of the word, so a hyphenated break does not split
`кто-то` in two, and a press landing in a gap takes the word before it rather than nothing. What comes
out is the text as written, with the typesetter's own marks stripped.

A press is `UILongPressGestureRecognizer` rather than SwiftUI's. `LongPressGesture` carries no place of
its own, and the zero-distance drag usually paired with it to find one swallows every tap on the page:
the taps that turn it, open a note, and show the controls all went that way. The recognizer reports its
own place, fires while the finger is still down so the words light up under it rather than when it comes
up, and is set not to cancel the touches around it. It hangs on the window, the one view certain to see
every touch, and ignores a press that began outside the page.

**The page holds still while anything covers it**: words being picked, the aside offered for them, or
a note. `PageTurnView.isCovered` tells four things so: the drag that turns a page, the end of that
drag, the tap zones and the press. The layer an aside lays over the page answers taps, and the page
ignores them too, or one tap would put the aside away and turn the page as well. The press has to be
told because it hangs on the window and hears a finger held on the aside itself. Only a press's start
is refused, since the words it's picking cover the page as soon as it begins. A turn already under way
is dropped when a press takes hold, because a finger can cover the eight points that start one inside
the time a press takes to be held.

The page answers sideways drags and hands on the rest. A screen pushed with a zoom transition is
closed by dragging it back down, which is the drag that turns a page, so the turn is
`PageDragGesture`: a pan of UIKit's that fails on a drag up or down the page before it begins, which
is what leaves that drag to the transition. SwiftUI's `DragGesture` could not, since it recognises in
every direction and takes the touch at eight points, and the book could never be closed by dragging
it. The recognizer hangs on the window as the press does, so it also asks whether anything is
presented over the page before taking a touch.

The transition answers only a drag going down. Its dismissal takes one in any direction by default,
so a drag in from the leading edge closed the book instead of turning back a page; `Navigator` gives
every zoomed screen an `interactiveDismissShouldBegin` that asks for down.

The reader is presented over the app rather than pushed into it, so there is no stack under it to
answer for: no tab bar to take away on the way in and hand back on the way out, and no navigation bar
belonging to the screen underneath. Re-laying all of that out in the middle of the zoom is what the
transition used to jump on. The reader carries a stack of its own for its bar, and a Close button,
since a presented screen has no back button.

Lifting the finger opens a `Callout` over the words: look up, translate, copy. The paint under them is
`Design.Surface.picked`, and the page ticks as it goes: firmer for the first word, lighter for each one
taken in after it, softer again when the aside arrives.

## Cutting the column into pages

`ColumnComposer` sets the chapter as a single column, and `PageCutter` cuts that column into pages
line by line, away from the main actor. The search that chooses the breaks reads each line twenty-odd
times, so it takes a flattened copy of the column, `PageCutter.Slug`, carrying a line's depth and the
handful of things a rule asks about it and nothing that has to be reference-counted.

Cutting by hand rather than flowing the text through page-sized containers is what makes the rules
possible. None of these is allowed at a break:

- a hyphen at the foot of a page,
- an orphan: a paragraph's first line alone at the bottom,
- a widow: a paragraph's last line alone at the top of the next page,
- a heading with fewer than two lines of its chapter under it,
- a break between scenes at the head of a page.

Titles stand in air, and `TitleBlock` says how much. Titles that touch are one block however many
levels they carry, the block takes the air of the biggest title in it, and the air goes round the
outside rather than between its lines: twelve lines above a first-level title, six above a subtitle,
three above a third-level one and a single line above anything smaller. A block given three lines or
more is parted from the text under it by two; one given less is not, since a gap under a title and
none above it would read as belonging to the text that follows.

Counted in lines of the page rather than in the gap paragraphs take between them, because that gap is
a fraction of the reader's line spacing and comes to nothing at a tight setting.

A chapter's own heading is the first-level title of the block it opens, so it takes the twelve. Where
the chapter starts a page, all but two lines of that are cut: there is nothing above it there to stand
clear of, twelve would push the heading a third of the way down its own opening page, and none would
leave it hard against the top edge. `ChapterLayout` does the cutting, since only it knows where the
chapter begins. For the same reason no page may open on a title standing in three lines or
more: the air would fall off the top with nothing left to say, so the break goes before the air.

A break between scenes is a row of stars, which books write as a subtitle and which is set as one.
The level comes from the markup and only from the markup: `BookHTML` reads it off a heading element,
and `FB2Parser` writes a file's `<subtitle>` out as one. What a paragraph holds is never asked, since
a paragraph is centred for all sorts of reasons and an epigraph is not a title.

A book filed before that was written carries its subtitles as centred paragraphs, and its breaks
stand in no air until the file it came from is read again.

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

Measured over eight generated chapters at 19pt serif and 24pt margins, a measure of about 26 lines:
every one of the 25 pages that doesn't end a chapter carries 24, 25 or 26 lines, and the leading closes
that spread. The eight short pages are the eight chapter endings, which stop where their chapters stop.

## Chapters that run on

A chapter starts on the page the one before it ended on when what is left of that page holds a decent
piece of it: six lines and a quarter of the page, after the air between them. That measurement counts lines, and
a heading stands far taller than a line, so the page answers instead of the arithmetic: the chapter is laid out at that offset and asked
how much of its own text landed. Fewer than three lines and it takes a page of its own, which is what
keeps a title from standing alone at the foot of a page with its text overleaf.

A chapter of a heading and nothing else, which is how a part title is filed, runs to a single page and
lets the chapter after it follow on the same one.

`ChapterLayout` takes a `startOffset` for that and makes its first page shorter by exactly that much,
and the reader draws such a page from two pieces, one per chapter. Whether a page gets its second piece
is settled from the offsets the two layouts were built at rather than from `BookPagination`'s pass,
because the layouts are what draw: `BookPagination.sharesLastPage(of:with:context:)` asks whether the
next chapter was set to begin at or below where the previous one's text stops.

That offset is what makes a chapter's page breaks depend on the chapter before it, whose breaks depend
on the one before that. Measuring a chapter on its own therefore answers differently from measuring it
after reading into it, and the text used to move under the reader when the two disagreed: a chapter
opened from the contents took a page of its own and then jumped up the page as soon as the reader
turned back into the chapter before it.

So `BookPagination` measures the book in one pass, in order from its first chapter, and keeps only
where each chapter starts and how far it runs. Every layout afterwards takes its offset from that pass,
so a chapter sits in the same place however the reader reaches it. A chapter the pass hasn't reached
has no offset to take, and isn't laid out at all until it does: the reader reads two chapters ahead,
and one set from a guessed offset is drawn over the page it turns out to share. The pass throws each layout away as
it goes, so a book of any length costs one chapter's memory at a time, and it runs again whenever the
style or the page size changes, which is what those measurements depend on.

It measures only text the device already holds. Fetching a whole book to find out where its pages fall
would turn opening one chapter into a download of all of them, so a chapter that isn't here yet ends
the run-on and the chapter after it starts a page of its own.

The book's length in the footer is the pages the pass has measured plus a guess for the rest. Every
chapter carries its length in characters, and within one book set one way pages follow characters
closely, so the unmeasured text is counted at the rate the measured text ran. Each chapter the pass
measures behind the reader turns part of the guess into pages, and a chapter the device hasn't got yet
stays a guess.

Because a page can show a chapter that hasn't arrived yet, the model's layout cache is observed, not
ignored: a neighbour landing has to redraw the page already on screen.

## Keeping the lines

Where a chapter's lines fall depends on the text and the setting, and not on where the chapter starts
on its page. So the lines are what is kept, in `chapter_column`, and cutting them into pages is done
afresh every time.

A column is filed under a hash of the setting's fingerprint and the chapter's own text. The
fingerprint carries `ChapterLayout.rulesVersion`, so a change to where a line may break throws away
every column broken under the old rules instead of drawing yesterday's lines. The rows are written as
zlib-compressed JSON by `ColumnCoding`.

A chapter carrying a picture is composed the long way and nothing is kept: what such a line holds is a
decoded image, and writing one down would put the picture in the database twice.

`ColumnCacheTests` sets a chapter twice and compares the second run to the first line for line, then
shortens the kept column to prove the second run is set from it rather than composed again and
happening to agree. A mistake here reads as text laid out subtly wrong, never as a crash, so the check
has to be that exact.

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

The system's swipe-from-the-edge-to-go-back gesture never reaches the page, since the reader is
presented rather than pushed and the stack it would belong to is behind it. A drag in from the leading
edge turns back a page, like any other sideways drag.

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
- Chapter bodies come from `SQLiteBookStore` before the service is asked, and land there when they arrive.

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
