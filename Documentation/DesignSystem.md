# Design system

Everything outside the reader page is built from `Design`, in the `DesignSystem` package. Two rules hold it
together:

- **Every length is a multiple of three.** The one exception is the hairline, which is a device pixel and
  not a length at all.
- **Five colours carry a fact.** Anything else on screen is a system surface or a system label.

The reader page is deliberately outside both. Its type, its margins and its five tints belong to
whoever is reading, and `ReaderSettings` owns them. Don't pull reader values into `Design`, and don't
apply `Design` to the page.

## What's in it

| Group | Holds |
| --- | --- |
| `Space` | Seven steps from 3 to 36, all multiples of `unit`. |
| `Radius` | Three fixed, plus `cover(width:)` for a cover that rounds in proportion to itself. |
| `Stroke` | The hairline and the ring. |
| `Size` | Eight fixed dimensions, from an 18pt mark to a 120pt cover. |
| `Palette` | The five meanings, and the one opacity every tinted ground and edge is drawn at. |
| `Surface` | Screen, card and fill, plus the edge colour and `ground(_:)` for a tinted pill. |
| `Style` | Nine roles, each one system text style, so the whole app follows Dynamic Type. |
| `Shade` | Two depths and the page-turn cast, applied with `.shade(_:)`. |
| `Control` | What a button is set in: the action and the bar glyph. Neither is a text role. |
| `actionLabel()` | The shape of a full-width action, so two on one screen agree on height. |
| `barGlyph()` | An icon-only button in a bar: its type, and a hit area a finger can find. |
| `RowStack` | Items side by side, all on one baseline. |
| `Callout` | A short aside: set to a width, scrolling once it outgrows its depth. |
| `CalloutShape` | The card and its pointer as one path. |
| `CalloutPlacement` | Which side of a thing an aside takes, and where it slides to. |
| `CalloutMotion` | How an aside comes and goes. |
| `callout(over:item:ground:)` | Hangs an aside over something in a view's own space. |
| `sitsOnTheLine()` | What a boxed label wears so its ground sits on the line rather than under it. |
| `LineGlyph` | A symbol set as text, so a row's baseline runs through it. |
| `Style.spine` | What is printed on a book's spine: under the smallest role, and narrowed. |
| `Size.coverWidth(across:ideal:spacing:)` | The width that fits a whole number of covers into a row. |

## The five colours

| Name | Means | Where |
| --- | --- | --- |
| `accent` | Theirs to act on, or how far they've got | Progress ring, chapter mark, selected chip, library mark, top three in the chart |
| `positive` | Finished | The Finished badge |
| `caution` | Something between the reader and the page | The costs-money badge, a paid chapter |
| `alert` | Wrong | Error lines, the new-chapter count |
| `neutral` | A fact with no colour of its own | Ongoing, likes, last updated |

Indigo and pink are retired. Ongoing and likes are facts rather than states, so they take the neutral
tint and let their glyph carry the meaning.

Labels stay as `.primary`, `.secondary` and `.tertiary`. The system already names those better than a
wrapper would, and wrapping them would hide which one is in play.

## Actions

A full-width action wears `.actionLabel()` on its label and `.controlSize(.small)` on the button.
Prominence is the only thing that varies: `.borderedProminent` for the one thing a screen is for,
`.bordered` for the rest, `role: .destructive` where it takes something away.

A button is not a sentence, so neither of its two sizes is one of the seven text roles. They live in
`Design.Control`: the action at 18 points medium, a shade over a heading, because it carries the one
thing a screen is for; the bar glyph at 20 points regular, because a glyph is already a solid shape
and needs none of a heading's weight. Both are written as sizes, so both still follow Dynamic Type.

An icon-only button in a bar wears `.barGlyph()`, which carries that type and a hit area with it.

Setting a height without the control size does nothing, which is how the book page ended up with a
Read button and a Delete button at two different heights and two different type sizes.

## Everything in a row sits on one line

Use `RowStack` rather than `HStack` for anything set side by side. It aligns on `.firstTextBaseline`,
which is what makes a badge, a glyph and a title read as one line instead of three things standing next
to each other. Centring them lines up their boxes and leaves their words at three different heights,
and the eye reads the words. Anything that genuinely wants a different alignment is a stack rather than
a row, and says so by being one.

A boxed label needs one more thing. A badge or a pill is text inside a padded ground, so a baseline
drawn through its text hangs the ground below the line by whatever padding sits under it. `Pill` and
`SeriesNumber` wear `sitsOnTheLine()`, which takes that padding back out of the baseline they offer the
row and puts the box itself on the line. Any new boxed label wears it too.

A glyph needs the same care for the opposite reason. An `Image` carries no baseline at all, so a symbol
dropped into a row is lined up by its bottom edge and sits below the words beside it. `LineGlyph` sets
the symbol as text, which puts it on the line and takes its size from the row's own font. A symbol
standing next to type is a `LineGlyph`; one standing alone, or inside a mark of its own, stays an
`Image`.

The catalogue's two **Baseline** specimens are where this is checked: a badge beside each of the text
roles, the shelf's folded run, one row carrying a glyph, a badge, words and a pill together, and a row
setting the same glyph both ways so the difference is visible. If anything in those rows sits low or
floats, the rule has been broken somewhere.

## Asides

`Callout` is a short aside and `callout(over:item:ground:)` hangs one over something in the view's own
space: the reader's footnote marker, or a run of words picked off the page. It takes a rectangle rather
than a point, and stands on whichever side of it has more room, pointing at the near edge so it never
covers what it was opened for.

**It draws itself rather than using a popover.** The system's popover keeps its own container and its
own arrow and hands over neither: a ground given to the content stops at the card's edge, and
`presentationBackground` does not reach the arrow. Measured, not guessed, in
`CalloutBackgroundUITests`, which samples the pixels either side of the card's edge and fails if they
differ. It also clamps a card this wide to the middle of the screen wherever it was hung. So
`CalloutShape` draws the card and its pointer as one path: one colour by construction, and one shadow
cast by both.

Placement is arithmetic in `CalloutPlacement`, checked in `CalloutPlacementTests` rather than through a
screen. The card is stood by carving a region with padding and aligning it against the pointer's edge,
so nothing needs to measure how tall it came out.

### Coming and going

`CalloutPresenter` holds the aside on screen for as long as it is arriving or leaving and animates one
number, `reach`, which scale and opacity both read. Not a transition: a transition only runs where
SwiftUI counts the insertion as animatable, and in a tree that rebuilds as often as a reader's page
does it silently did not, however the change was wrapped.

Three things that each looked like "the animation is broken" and were not the same bug:

- The card was measured before being placed and hidden until the measurement arrived, so it played its
  whole arrival invisibly. It is placed by alignment now and never hidden.
- `scaleEffect(anchor:)` reads its `UnitPoint` against the view it is on. On the region around the card
  it named a corner of the page; it belongs on the card, where it names the pointer's own tip.
- The presenter holds the anchor rectangle as well as the item, because the caller drops that on
  dismissal and an aside shrinking towards a place nothing is any more leaves for the screen's corner.

`CalloutMotion` carries both timings: a little bounce on the way out, none on the way back, since a
bounce says something has arrived and nothing is arriving when one is put away. `-at-motion-scale`
stretches them, because a screenshot takes longer to make than either runs for and a test photographing
one otherwise catches only the end of it. `CalloutMotionUITests` measures the frames.

`Callout` takes its colours rather than reading them off `Design`. The reader's page is set by whoever
is reading, and an aside carrying the book's own words belongs on the book's own ground: the page's
colour with a little of the colour on it mixed in, lighter than a dark page and darker than a light one.

## Motion isn't in it

The reader's seven timings are tuned to the gestures that use them, and a page turn at the wrong
duration is worse than a page turn off the lattice.

## The catalogue

`DesignSystemScreen` draws every token and every component from the tokens themselves, in Debug builds
only. It has two halves. **UI** is everything the app is built from, all of it on the lattice and in the
nine text roles. **Reader** is the page: Russian and English each justified and ragged, three sizes, the
paint under picked words, and an aside. Nothing in that half is on the lattice or in a text role,
because a page belongs to whoever is reading it, and every specimen there is set by the book's own
typesetter so what is shown is what a page does. It lives in the app rather than the package, so it can show the book-shaped pieces beside the
generic ones. A catalogue on the device is the only honest specimen: it picks up the real face, the reader's
Dynamic Type setting, the system's light or dark and the materials, none of which a drawing of the app
can.

Two ways in:

- Profile has a **Design System** row in Debug builds.
- `-at-design-system YES` opens it straight from launch without signing in, since the design system has
  nothing to do with having an account.

Its labels are `Text(verbatim:)`, because a token name isn't translated.

## Where a component lives

**A component goes in `DesignSystem`, and if one is already there you use it.** Drawing a second
capsule, a second ring or a second circular mark is how a design system stops being one. There were two
progress marks before this rule, differing in ways nobody had chosen.

The one thing that cannot go in `DesignSystem` is knowledge of what a book is. The package has no
dependency on `BookKit`, and `Scripts/check-modules.sh` fails the build if it grows one. So a component
splits along that line:

| | Lives in | Examples |
| --- | --- | --- |
| Knows no domain | `DesignSystem` | `Pill`, `ProgressMark`, `CircleMark`, `FilterChip`, `RowStack`, `FlowLayout`, `LoadingOverlay`, `ExpandableText`, `ShareSheet` |
| Knows what a book is | `Code/Components` | `BookRow`, `WorkBadges`, `CoverImage`, `FileMark`, `LibraryMark` |

The second kind is built from the first and never redraws a shape the first already has. `FileMark` is
a `CircleMark` with a glyph; `WorkBadges` is a row of `Pill`s that knows which facts a book carries.

Before writing a view that draws anything, look in `DesignSystem`. If the shape is there and the fit is
imperfect, give the existing one a parameter rather than writing a second.

## Adding to it

A new value goes in `Design` or it doesn't go in. If a length isn't a multiple of three, either round it
or say in one line why it can't be. If a colour isn't one of the five, it needs to earn a sixth meaning
rather than a sixth hue.

Two kinds of number stay out of `Design` on purpose:

- **Proportions.** A cover's radius is `width * 0.08` and its placeholder is `width * 1.5`. Those are
  ratios, not lengths, and they hold at any size.
- **Optical padding a single component owns.** There isn't any left, but if a capsule ever needs a
  value the lattice can't give, keep it in the component and say why.
