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
| `actionLabel()` | The shape of a full-width action, so two on one screen agree on height. |

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

A full-width action wears `.actionLabel()` on its label and `.controlSize(.large)` on the button.
Prominence is the only thing that varies: `.borderedProminent` for the one thing a screen is for,
`.bordered` for the rest, `role: .destructive` where it takes something away.

Setting a height without the control size does nothing, which is how the book page ended up with a
Read button and a Delete button at two different heights and two different type sizes.

## Motion isn't in it

The reader's seven timings are tuned to the gestures that use them, and a page turn at the wrong
duration is worse than a page turn off the lattice.

## The catalogue

`DesignSystemScreen` draws every token and every component from the tokens themselves, in Debug builds
only. It lives in the app rather than the package, so it can show the book-shaped pieces beside the
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
progress rings before this rule, differing in ways nobody had chosen.

The one thing that cannot go in `DesignSystem` is knowledge of what a book is. The package has no
dependency on `BookKit`, and `Scripts/check-modules.sh` fails the build if it grows one. So a component
splits along that line:

| | Lives in | Examples |
| --- | --- | --- |
| Knows no domain | `DesignSystem` | `Pill`, `ProgressRing`, `CircleMark`, `FilterChip`, `FlowLayout`, `LoadingOverlay`, `ExpandableText`, `ShareSheet` |
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
