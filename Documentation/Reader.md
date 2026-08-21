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

A no-break space says so before the text is laid out.

`ChapterPagination` then sets the chapter as one `NSAttributedString` from a `ChapterTextStyle`: face,
size, line spacing, letter spacing, justification, colour. Margins are deliberately not part of that
style, because they shrink the frame rather than the text. The language the parser detected rides along
as `languageIdentifier`, which is what picks the hyphenation dictionary.

A chapter opens with its number and title above the body, and `ChapterHeading` leaves the number out
when the chapter's own title already carries one: "Chapter 4" over "Chapter 4. The Road" reads like a
bug. The first chapter of a book is preceded by a title page carrying the cover, title, author and
series.

## Cutting the column into pages

`ChapterLayout` sets the chapter as a single column, in slices with a yield between them so a long
chapter never blocks a page turn, and then cuts that column into pages line by line.

Cutting by hand rather than letting TextKit flow the text through page-sized containers is what makes
the rules possible. A break moves back up to four lines to avoid any of these:

- a hyphen at the foot of a page,
- an orphan: a paragraph's first line alone at the bottom,
- a widow: a paragraph's last line alone at the top of the next page,
- a heading with fewer than two lines of its chapter under it.

Four lines left on the page outranks all of them. Two lines of pull-back turned out not to be enough:
a run of hyphenated lines defeats it, and the leaks only closed at four.

A chapter whose last page would carry a line or two is fed from the page before it.

What the rules leave behind is spread between the lines of the page instead of collecting at its foot.
Each page gets its own leading, up to 3pt of air per gap, and a gap may be squeezed by 0.75pt to pull
one more line on. A page left half empty is the end of a chapter, and keeps its ragged bottom.

Measured over four chapters of a novel, with instrumentation since removed: no hyphens at a page foot,
no widows, one orphan in 87 pages, and pages steady at a median of 15 lines.

What it still doesn't do: nothing caps consecutive hyphenated lines, and a paragraph's last line may
be one short word. Both need control over line breaking rather than page breaking.

## Chapters that run on

A chapter starts on the page the one before it ended on when what is left of that page holds a decent
piece of it: six lines and a quarter of the page, after the air between them. Otherwise it starts a
page of its own.

`ChapterLayout` takes a `startOffset` for that and makes its first page shorter by exactly that much,
and the reader draws such a page from two pieces, one per chapter. Layouts are therefore prepared in
order forwards, since each one depends on where the one before it ended. A chapter opened from the
contents starts a page of its own, and is laid out again if the reader later reads into it from the
chapter before.

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

A tap in the middle third brings back the status bar and the controls, a second tap sends them away,
and turning a page sends them away too. They are the reader's own bar rather than the navigation
stack's, which is what lets them fade in over the page instead of sliding the page down, and the bar
carries a background of its own so the running head doesn't show through it.

Only that background runs up to the screen edge. Insetting the bar by hand as well would push its
controls a notch's worth too low, because the overlay is already laid out inside the safe area.

The buttons are round Liquid Glass, 36pt across, which is what the system draws in a toolbar. A square
label under the glass is what keeps all three the same circle whatever the glyph inside.

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
