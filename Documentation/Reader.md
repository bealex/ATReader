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

A paragraph's lines depend on nothing outside it, so the reader composes only the paragraphs around the
page being read, away from the main actor. An attributed string can't cross from one thread to another,
so each chapter's `ColumnComposer.Setter` sets its own copy of the chapter and hands back plain values:
where each line breaks and how it's filled. `ChapterLayout` builds a line's `CTLine` from those only
when a page draws it. Text laid out whole, a note in an aside, is composed on up to four workers at
once; a fifth adds no speed, because every change to an attributed string takes a lock UIFoundation
shares across the process.

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

### Whose heading the page shows

A chapter usually arrives with its number and title as the first paragraphs of the body, and the reader
sets a heading of its own above that, so both are on the page. Which one goes depends on what the body
wrote them as. Written as ordinary text, the body's copy is the one to lose: it is the same words in
the body's own face. Written as headings, the book is naming its own chapters, and the reader's heading
goes instead, since a book that sets out its divisions is left to set them out. A title standing in the
body is set in a face of its own for that reason.

### How a paragraph is told from the one before it

By an indent or by the air above it, and the two traditions never mix. Russian indents the first line
and leaves no gap between paragraphs; English parts its paragraphs with space and indents nothing.
`ChapterTextStyle.indents(_:)` settles it from the language the chapter was read as, the way
justification is already settled.

### Verse

A poem is set as the poet broke it, and the book says which blocks are poems rather than the reader
guessing it from how short the lines are. FB2 marks verse outright, `<v>` inside a `<poem>`, and the
parser carries that across as `data-verse="1"` on the block, which reaches the page as
`Paragraph.isVerse`. A short-line heuristic would catch dialogue, list items, addresses and signatures,
all of which are short for reasons of their own.

Such a block is never justified and never hyphenated: a line of verse ends where it ends, and filling
it to the measure or breaking a word across it are both the page overruling the poem.

A line too long for the column runs over, and the runover stands against the far edge. Set at the near
edge it reads as the next line of the poem rather than as the rest of this one, which is the whole
complaint against wrapping verse like prose. A poem the book centred keeps its own axis, where a
runover already reads as a continuation. `ColumnComposer.origin(of:drawn:ruler:)` settles it, off
`ParagraphRuler.isVerse`, which the typesetter puts on the run as `.verseLine`.

A quotation is held off both edges, but not evenly: the air is laid four parts at the near edge to one
at the far, so it reads as a passage moved over rather than as text that was narrowed. The total is what
it was, which matters because a poem quoted as an epigraph keeps the measure it had and every line it
lost would be a line that had to run over. `ChapterPagination.insetBias` is the four.

The name under a quotation stands at the far edge of that quotation rather than of the page, since an
epigraph is held off both edges and its attribution belongs to the passage. The book says which block
is one by what it is, `<text-author>`, so nothing has to be read off how the line was set.

Verse keeps whatever else the block is. A poem quoted as an epigraph is both held off both edges and
broken into lines, and taking only the first of those set it as justified prose.

### Links

A stretch of words pointing somewhere else in the book is drawn underlined and carries where it points
on its own glyph run, which is how a finger finds it without counting characters back through the soft
hyphens the line was set with. Following one remembers where it was followed from, and the way back
stands in the bottom corner for half a minute before it fades: a reader who was going to take it has
taken it by then.

Which chapter holds a given place is worked out once, behind the reading, by walking the book's
chapters and noting every block that says what the book knows it by.

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

### A plate that will not fit the room left

A picture is sized against the whole page, so one standing at two thirds of it can follow no text at
all: it lands on a page of its own, and the page before it ends wherever the text ran out. That's the
half-empty page a reader notices.

So a plate at the foot of a page may give up depth to finish it. `PageCutter` settles that inside the
break search rather than after it, because how much a plate gives up depends on which break falls, and
the search is what's choosing the break. A page ending on a plate that can shrink enough is costed as
full, so the run of breaks that closes the gap is the cheapest one and wins on its own merits.

`Rules.plateGivesUp` is the floor: a third of its own depth. Past that it reads as a different picture
rather than as the same one set smaller, so it keeps the page of its own and the page before it stays
short. A plate standing alone is left as it is, since it's got the whole page already, and text gives
up nothing at all, or a page would quietly set its own lines tighter than the column did.

What the plate loses in depth it loses in width, so it keeps its shape, and it is drawn centred on the
measure rather than on where it was first set. Four things walk a page's lines: the drawing, a tap
looking for a note, a tap looking for a link, and the selection. They all read the depth through
`ChapterLayout.depth(of:on:)`, since a walk that disagreed with the drawing by a plate's worth would
put every tap below it on the wrong line.

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

The words picked off the page can be marked from their own menu, which covers the stretch picked
instead of the whole page it sits on. Two marks of one book never share a place, so a second one made
exactly where one already stands is left alone.

Every mark the page carries hangs as a ribbon in the gutter, against the line it begins on, so the
page says which words are marked and not merely that it's marked somewhere. It's contoured in the
page's own ink rather than filled, which keeps it a mark in the margin of the book instead of chrome
laid over it. It shrinks with the margin it hangs in, and a page set with no margin at all keeps it at
the page's edge. `ChapterLayout.line(atPosition:onPage:)` says which line that is, walking the page
exactly as the page is drawn.

They stand under their chapters in the contents and in the book's details, with how far into the
chapter each one is, and open the book where they stand. `LocalStore` is where they live, like
everything else the reader does.

### Finding a mark once the offsets have moved

A mark carries the words it stands on, and is found again by searching the chapter for them. Offsets
survive a change of font, the text they count being unchanged, and they don't survive the book being
read again: a parser that has learned something writes different text and everything past the change
shifts.

That search and the offsets a page is cut at have to count the same characters, which is the one thing
that will quietly break it. `Typography.bound` puts a word joiner into every space that may not be
broken at, a reading position counts those, and the text the search runs over has to keep them. It
strips the soft hyphens, because a position doesn't count those either. `BookmarkOffsetTests` pins
both halves: the chapter runs as long as the text a mark is found in, and a mark made on a page is
found on the page it was made on.

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

The pan watches the touches without taking them, so the page's tap still hears a touch the pan has
begun on, and a flick of a few points lifts inside a tap's tolerance. `PageTurnView` drops the tap from
any touch it has taken as a drag, or a short flick forward turns two pages. The recognizer reports
each finger coming down, and that clears the mark for the next touch.

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

`ColumnComposer` breaks the chapter's paragraphs into lines, and `PageCutter` cuts one page out of
those lines at a time: forwards from where the page starts, or backwards from where it ends. The search
reads each line many times, so it takes a flattened copy of the lines, `PageCutter.Slug`, carrying a
line's depth and the handful of things a rule asks about it and nothing that has to be reference-counted.

Cutting by hand rather than flowing the text through page-sized containers is what makes the rules
possible. None of these is allowed at a break:

- a hyphen at the foot of a page,
- an orphan: a paragraph's first line alone at the bottom,
- a widow: a paragraph's last line alone at the top of the next page,
- a heading with fewer than two lines of its chapter under it,
- a break between scenes at the head of a page.

Titles stand in air, and `TitleBlock` says how much. Titles that touch are one block however many
levels they carry, the block takes the air of the biggest title in it, and the air goes round the
outside rather than between its lines: eight lines above a first-level title, six above a subtitle,
three above a third-level one and a single line above anything smaller. A block given three lines or
more is parted from the text under it by two; one given less is not, since a gap under a title and
none above it would read as belonging to the text that follows.

Counted in lines of the page rather than in the gap paragraphs take between them, because that gap is
a fraction of the reader's line spacing and comes to nothing at a tight setting.

A chapter's own heading is the first-level title of the block it opens, so it takes the eight. Where
the chapter starts a page, all but two lines of that are cut: there is nothing above it there to stand
clear of, eight would push the heading well down its own opening page, and none would leave it hard
against the top edge. `ChapterLayout` does the cutting, since only it knows where the
chapter begins. For the same reason no page may open on a title standing in three lines or
more: the air would fall off the top with nothing left to say, so the break goes before the air.

A heading is set as two lines: what the chapter is, small and spaced above, and what it is called,
large under it. A file usually writes both into one string, so `HeadingNumbering` parts it: a word the
heading opens with that names a part of a book, the numeral after it, and the name that follows. What
it will not part, it leaves whole. "Часть тела" opens with a word it knows and is a part of nobody.
Russian numbers a chapter with an ordinal, so a cardinal at the front is the name counting something:
"Глава Три товарища" is a chapter called after the three. English says "Chapter One" and is read
either way. Where a heading carries no number of its own it is given the chapter's count instead, and
where it carries one, the book's own words are used: a book with a prologue in it disagrees with the
count and is right.

A break between scenes is drawn with the marks the book wrote it with, a row of stars or a single
asterism alike, and a file that leaves only a blank line is drawn with nothing. Which blocks are one is `BookHTML.isSceneBreak(_:)`, and it
is the only test: a row of asterisks, or the asterism, and nothing else. Books write a break either as
a blank line or as a subtitle carrying those marks, and both arrive as the same thing.

A subtitle that carries words is a heading and divides the book; one that carries only those marks
parts two scenes and leaves the chapter whole. That distinction is worth the asking, even though it
means asking what a paragraph holds rather than only how it's marked up. A book that marks
every one of its scene breaks that way otherwise comes out as a contents of a hundred and more unnamed
pieces, with the mark itself swallowed by the cut: one reported file carried thirty-seven chapters and
a hundred and thirty-four breaks. Anything else centred, an epigraph among them, is left alone, since
a paragraph is centred for all sorts of reasons.

A book filed before that was written carries its subtitles as centred paragraphs, and its breaks
stand in no air until the file it came from is read again.

A page is chosen against the two pages beyond it rather than on its own. Filling each page in turn and
handing whatever a rule rejects to the next one meant that wherever a rule bit, that one page paid all
of it: a page four lines short between two full ones. So every run of breaks over the page and the two
after it is costed, a page's shortfall counted in lines and squared, and the page at the near end of
the cheapest run is the one cut. Squaring is what shares the loss out, since one line missing from each
of four pages costs a quarter of what four missing from one does. Past the lines composed the chapter
goes on, so the run may stop on any page the last of them would fit on.

Cut backwards the same way, the chapter's start is the one edge that doesn't go on. A chapter reached
from behind begins wherever its lines run out, so its opening page may come out short. That page sinks:
its lines stand at the foot of it and run straight on to the page after, and the air falls above the
title, where a printed book leaves it.

Forwards and backwards needn't agree about where a page breaks, and the reader never has to find out.
It keeps the sheets it has shown until the page changes shape, so a turn back and forth shows the same
pages, and a page further off is cut afresh from the one beside it.

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

## Chapters that run on

A chapter starts on the page the one before it ended on when what is left of that page holds a decent
piece of it: six lines and a quarter of the page, after the air between them. That measurement counts
lines, and a heading stands far taller than a line, so the page answers instead of the arithmetic: the
chapter's opening is cut into the room left and asked how much of its own text landed. Fewer than three
lines and it takes a page of its own, which is what keeps a title from standing alone at the foot of a
page with its text overleaf. A division the book names among its top ones always opens a page.

A chapter of a heading and nothing else, which is how a part title is filed, lets the chapter after it
follow on the same page.

`BookLayout` does this in both directions. Forwards, the page that ends a chapter takes the next
chapter's opening under it, set to start `Page.top` points down. Backwards, a chapter's opening that
came out short, at the foot of its page, takes the end of the chapter before it above. A page shared that
way is drawn from two pieces, one per chapter, and each draws only its own lines.

A chapter whose text the device hasn't got, and can't fetch, is a page of its own saying so, and the
book goes on either side of it.

## What the reader can set

The appearance sheet is three panels behind a segmented picker that never scrolls away, since the
sheet is half the screen on purpose and everything below the first scroll of a single long form is out
of sight.

- **Type** — typeface and weight, then text size, line spacing, letter spacing and page margins, then
  how lines are set: alignment per language, and hyphenation.
- **Colour** — whether the page follows the system, and the theme or themes it turns between.
- **Options** — the screen and the pictures.

Every slider has a step either side of it (`SteppedSlider`): the drag gets near and the steps settle
it, without a finger over the answer. Margins step by four points, since a point either way on a
hundred-point range is not a step anyone means.

Following the system means two themes, one for its light hours and one for its dark, and the page
turns with it; not following it means one theme whatever the system is doing.

What the system is showing is asked of the **scene**, in `SystemAppearance`, and not of a window or of
SwiftUI's environment. The reader holds the window to the page's own light or dark for as long as a
book is open, so a window asked then answers with the page: a page following the system would be
following itself, and would latch to whichever it opened on. An override reaches down from a window
and never up to the scene it sits in. The answer is taken when the app becomes active and whenever the
scene's traits change. "Match the system" used to be a theme of its
own and meant exactly what the switch does; a reader who chose it keeps what they chose.

Hyphenation is the reader's to turn off. The chapter is composed from the text as hyphenated or as
bound, so turning it off re-breaks every line. A justified
column reads far better with it, since the only other way to reach the measure is to pull the words
apart.

## Where the reader stopped

The position is written 400ms after a page turn, so a run of turns writes once. Two moves are written
through instead of waited on: leaving a chapter, since the mark on the book's cover jumps by a whole
chapter and the reader may be gone before the wait is out, and leaving the book.

Leaving is the transition beginning rather than the screen gone: `Navigator.aboutToGo` fires from the
presented screen's `viewWillDisappear`, a drag's included, and the reader writes there. The shelf draws
a cover's mark from the store and the zoom photographs that cover as the book starts closing, so a
shelf told afterwards animates the old mark home and corrects it once the book has landed.

## Nothing is measured ahead

The book is never laid out as a whole. Opening it cuts the page the reader stopped on, starting on the
line their position falls in, and the sheet either side of it after that. A turn moves onto a sheet
already cut and cuts the next one behind it. A change of size or style, a folding screen opening
included, throws away the few sheets around the reader and cuts the one on screen again at the same
place. Composing a page costs a few milliseconds, so none of it is kept between openings.

The chapters' prepared text is still kept, in `chapter_content`: parsing and hyphenating it is the
larger share of the work, and it depends on nothing about the page.

## How far into the book

The foot of a page says how far into the book it stands: a bar, the share of the book up to the end of
the page, and how many pages the whole book comes to. A page number would need every page before it cut,
which is what the reader no longer does. While the controls are away, and the status bar with them, the
bar stands alone; the figures come with the controls, at half the running head's size, off its ends so
it doesn't move: how long the book is before the bar, how far in the reader is after it.

The share is counted in characters. Each chapter carries its length and a place in it counts its own,
so the figure is exact wherever the reader is and however little has been laid out.

The length in pages comes from `BookLength`, from the book's length and the setting alone: how many
characters of ordinary prose one line holds, measured on a sample in the book's language, times the
lines a page holds, less a hundredth for openings, pictures and the air between paragraphs. It changes
with the type and the size of the page, so unfolding a screen changes it too.

On a spread the bar stands once, under both pages, as the title stands once over them.

## The page

A page fills the screen. There is no navigation bar and no strip below the text: the book's title and
how far into the book the page stands are drawn on the page itself, so a turn carries them along with
everything else. Each page says where it stands, since the pages either side of it are on screen during
a turn.

The page ignores the safe area, so its size and the notch and home-indicator insets come from the
window rather than from the layout. Two reasons: an overlay is laid out inside the safe area even when
the view under it is not, and a toolbar coming and going would otherwise re-paginate the chapter.

### The band the running heads stand in

Both heads are set at `Context.runningHeadScale` of the book's own text size, and the band the layout
keeps clear at the head and foot of the page is that head's line and three quarters as much again of
air. One number sets both, so the band is always as deep as what stands in it. Set the head from
anything the band can't see and it grows onto the first line of the page.

Nothing on the page follows the system's type size. The reader sets the text's size themselves, the
head follows that, and a head stays in proportion to the page it heads at every size they can choose.

Drawn text is invisible to VoiceOver, so each page publishes its text as its own accessibility element.

## One page or two

What fills the screen is a *sheet*, and a sheet carries one page or two. `PageSpread` settles which,
from the size of the window, the device's own bands, the size the book is set at and the margins the
reader chose. Two pages where each half still holds a column worth reading and stands taller than it is
wide; one otherwise, held to a measure the eye can track back across and stood in the middle of
whatever room is left.

A phone in portrait comes out exactly as it always did, to the point. A phone is narrower than the
shortest measure at every size the reader can choose, so nothing here ever reaches it.

The shape test is what a window with plenty of width and little depth runs into. A large phone on its
side has the width for two pages and just enough depth to keep them page-shaped, so it opens like a
small book. Flatten that window further and the two halves would each come out landscape, which reads
as a screen split down the middle rather than as a book, so one page is kept and held to a measure
instead.

### The measure, and the air around it

The measure is counted in ems rather than points: 36 of them at the widest, 17 at the narrowest worth
standing two of. A line holds about the same number of characters however large the reader sets the
text, which is the only thing a measure is for, and 36 ems at the size most people read at is close to
what the system's own readable width comes to. A measure in points would have been a comfortable line
at 19 points and a dozen words at 30.

The narrowest measure is what makes a spread give up its second page. A reader who widens the margins
or the text past the point where two columns still read gets one page instead, and that page is wider
than either column was. It's the one time a wider margin widens the text.

A spread's air is one band, and it has three of them: the two edges and the binding. They are equal.
Whatever the measure leaves over is parted between the three rather than pushed out to the sides, so
the two pages stand evenly on the sheet instead of drifting apart with a hairline between them. No band
is narrower than the two margins that meet in the binding, and none narrower than the least a binding
takes, which is what a reader who has turned the margins off altogether still gets.

The sides of the device's own safe area are spent outside all of this, so the bands are equal within
the room the text may actually occupy: a phone on its side keeps its text clear of the notch and still
parts its pages by what it parts them from the glass.

One page on a sheet wider than 36 ems still has air at its edges with the margins turned off, and that
air is the measure: the page is held to it and centred, and what's left over stands outside it.

Both the head and the foot of a page keep a band of their own even where the device asks for none. An
edge with no notch and no indicator behind it gave the running head four points of air and stood it
against the glass, while the foot kept the indicator's room, and the page came out lopsided. The
running heads, the controls and the way back are all set on that band rather than on the window's own,
which is what keeps a control on the line its head is set on.

Everything below the spread knows only about a page. A page is measured, drawn and hit-tested in its
own coordinates, and the spread's whole job is to say how big one is and where on the sheet it stands.
So the sides of the device's safe area are spent outside the spread rather than in its gutter, which is
what makes both pages the same size: a chapter set for one is set for the other.

A tap arrives in the sheet's coordinates and is carried onto whichever page it landed on before
anything is asked about it. What comes back out, a note's marker or the box around picked words, is
carried the other way, since an aside is hung over the sheet.

### What each page names, and what the sheet names

The book's title and how far into it the reader is both belong to the sheet on a spread, each set once
in the middle: the title over the binding, the bar under it. Drawn per page the title came out as the
same words twice a few inches apart, which reads as a fault rather than as a running head. On a phone the
sheet is the page, and the page carries both.

A sheet carrying the book's own title page takes no running head at all, since that page already says
what the book is called, and neither does one carrying no text. `Sheet.showsTitle` is the whole of that
rule. The band each page keeps for a head is unchanged either way, so the text still starts where it
always did.

## Turning a page

A turn moves a sheet, so on a spread both pages go at once, the way they do in a book. `PageTurnView`
counts in sheets and knows nothing else about them: what it's handed is a count, an index and a
builder, and on a phone a sheet is simply a page. The reader hands it one sheet and the two beside it,
so every turn lands past the end of the one and the model moves along its own run of sheets.

The whole effect comes from one rule: sheet `n + 1` always sits above sheet `n`. Turning forward slides
sheet `n + 1` in from the right; turning back slides that same sheet off to the right and uncovers
sheet `n`. One offset drives both directions, so a half-finished turn can be reversed with no special
handling.

A sheet is cut before it is needed, so a turn draws pages that already exist. Where one isn't ready, a
chapter still on its way from the service, the turn lands on a blank sheet that fills in as the text
arrives.

Dragging forward, the incoming page eases in from the right edge to meet the finger over 0.3s and from
then on is held 20pt inside its own leading edge, so the finger is on the page it is pulling. Sliding
it in by the finger's travel alone would leave its edge wherever the drag happened to start, which
reads as pushing a page along from a distance. Re-targeting that animation on every gesture event keeps
it smooth however fast the finger moves.

What lands the turn is the finger's own travel, not how far the page has come, and a flick back cancels
it however far it had got. A turn in flight is dropped when the app leaves the screen, since the
gesture that would have finished it is gone.

A turn the finger has let go of runs on for a fifth of a second, and a finger that arrives inside it
lands that turn at once and takes a page of its own. A drag only ever steers the turn it began.

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

## Finding a passage

The glyph that opens things also opens a bar at the foot of the page, on the line the progress is
set on. It holds the words to look for, how many places in the book carry them, and the way through
those places.

What stands at its far end depends on the keyboard, since the two are never both wanted. With the
keyboard up the reader is still typing and wants it out of the way, so the bar offers that; with it
down they're reading the places found and want the way to the next, so the bar offers the previous and
the next.

### Standing the bar clear of the keyboard

Three things have to be true at once here, and each of them is easy to get wrong on its own.

An overlay is laid out in the frame of what it covers. The page turns the safe area down, so the
overlay carrying the bar has the window's own foot for a bottom: nothing lifts it, and the bar sits
under the keyboard. So the keyboard is measured, in `KeyboardCover`.

What is measured is the overlap with the window, not the keyboard's height. The frame it publishes is
in screen coordinates and says how big the keyboard is, which is a different question: an iPad window
that doesn't fill the screen is covered by only the part of the keyboard that reaches into it.
Converting the frame into the window and intersecting is the only reading that holds in both cases,
and that wants a real `UIWindow`, which is why a view of no size sits in the bar's background to own
one. It listens for `keyboardWillChangeFrame`, not `keyboardWillShow`: a keyboard changes depth when
its own bar comes and goes, and a height read once is wrong from then on.

Then SwiftUI has to be told to stop. It lifts a view it believes the keyboard covers, and this one is
already moved by the measurement, so both at once is the same keyboard counted twice: about 110 points
of it on a phone. The bar stands at the foot of a layer of its own that turns the whole safe area down,
so the layer's foot is the window's and nothing moves it but the measurement.

That foot is the whole of the defect it had. Turning off the keyboard's lift alone left the bar keeping
the device's band for its own floor, while the keyboard it was padded by was measured from the window's
foot with that band already underneath it. The band was counted twice and the bar floated a home
indicator's worth above the keys.

Whichever stands deeper places it: the line the progress is set on, or the keyboard. Deeper rather
than one or the other, since both are now measured from that same foot.

With the keyboard away the bar stands where the progress does, an inset above the device's own
band. Not where the round controls stand: those are centred on the running head's line and hang below
it, which suits a mark the size of a fingertip and not a bar the width of the page.

`ReaderSearchUITests` measures the gap, and the number it allows is wider than the design's own air. A
test sees the keys alone, while the frame the keyboard publishes reaches about 44 points higher over the
row of guesses above them, and that is what the bar is placed against.

The search runs on the words submitted, not on every keystroke. It walks the book a chapter at a time,
pulling any chapter that isn't on the device yet, and publishes what it has after each one, so the
count climbs while the reader reads and the way through works before the walk is done. It carries the
reader to the first place at or past the page they were on the moment that much of the book has been
looked through.

The offsets are the trap. A chapter is searched as the book wrote its blocks, which carry no soft
hyphens and no heading; the reader sets a heading above them, so the chapter as it's laid out counts a
fixed amount more than the search did. So the jump doesn't trust the offset. It looks for the same
words in the laid-out chapter and takes the match nearest that offset. The shift is the same
everywhere in a chapter and separate sayings of a phrase are thousands of characters apart, which
leaves the nearest match the one the search meant. `FindInBookTests` pins it: the blocks and the
laid-out chapter agree on every place, and the nearest match is always the right one.

## The controls

A tap in the middle third brings back the status bar and the controls, a second tap sends them away,
and turning a page sends them away too.

The controls are the reader's own views rather than a toolbar, and each is a `GlassRow` of its own:
Close on the leading side, the bookmark on the trailing side, and one glyph beside it for everything
that opens something. The chapter list, the appearance form and the debug report live under that glyph.

Three panes rather than one. The bar is read over a page, so what stands on it is what's wanted while
reading, and the two that stay are the two that act on the page behind them. Grouping the menu in with
the bookmark read as a bar of odds and ends.

The two forms hang on the glyph rather than on the rows in the menu. A menu is gone by the moment its
row acts, and a popover hung on something gone has nothing left to point at, so it points at the glyph,
which is what the reader touched. They stand on the line the running head is set on, their middle on its middle,
so the two read as one line across the top of the page. A navigation bar can't do that: it centres what
it is given on its own height and reads no offset asking for anything else, which is why toolbar items
sat a bar's worth below the book's name.

Where they stand is asked of the system. A folding iPhone keeps a vertical bar down one side of the
screen in place of the bars at the top, and `DeviceBand` reads which side from `toolbarVerticalEdge`
(iOS 27.1). Where there is one, the controls go down that column as the system's own buttons do: 24pt
in from the edge, the way out 120pt down so it clears the clock, the other two at the foot. No inset
reports how far the status items reach, so that depth is a number of the reader's own. `GlassRow` takes
an axis so a column of buttons is still one pane of glass.

The bar's column arrives as a side inset, 84pt on an unfolded Duo, and the window gives it back the
moment the status bar is hidden. The page makes no room for it: `DeviceBand.pageInsets` leaves that
side out, so a spread is set to the whole width and hiding the status bar with the controls moves
nothing. The price is paid while the controls are up, when the clock and the buttons stand over the
page's outer edge and can cover the end of a line. Guessing the side from the insets can't work, since
the inset comes and goes, and said nothing at all of a window wider than it is tall.

The pages are laid over the sheet rather than stacked in it. A page is as tall as the window, and one
that takes part in the layout makes the sheet taller than the safe area it is offered. SwiftUI centres
that overflow before `ignoresSafeArea` widens anything, so the page lands half the difference between
the top and bottom insets away from the window's corner. An upright iPhone hides it, its top inset
being the deeper one. A Duo has none at the top and 34pt at the foot, and set every page 17pt high.

The reader keeps a navigation stack with its bar hidden, for the window `readerBarAppearance` reaches
through it: the page's own colour behind the corners the stack rounds, and the window held to the
page's light or dark for as long as the reader is on screen. `preferredColorScheme` did that before,
and SwiftUI applies it by overriding the window rather than the view: leaving the reader reverted
SwiftUI's own side of it and left the window's, so the library came back light underneath a navigation
bar and a search field that were still dark. The override has one owner now, taken when the reader
appears and given back when it goes.

The status bar goes with the controls. A presented screen only owns the status bar if it says so, and
an over-full-screen presentation leaves it with whoever is underneath, so `Navigator` sets
`modalPresentationCapturesStatusBarAppearance` on the screen it presents. The reader's own
`statusBarHidden` is what answers from there.

Showing the controls moves no text: the page ignores the safe area and takes its size from the window,
so nothing pagination depends on changes when they appear.

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
