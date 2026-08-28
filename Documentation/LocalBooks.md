# Books from files

A book can come from an FB2 file on the device instead of from the service. Once it's in, nothing
downstream can tell the difference: the same library row, the same book page, the same reader.

## The seam

Everything a screen shows comes out of `LocalStore`, and the reader's pipeline starts at a chapter
*body*, which is HTML. So an imported book only has to fill the rows a download would fill: one work,
one chapter per section, one body per chapter. `FB2Parser` emits each section as the same `<p>` markup
a chapter arrives in from the service, and `ChapterHTML`, `ChapterContent`, `ChapterPagination` and
`ChapterLayout` then work on it unchanged.

That's the whole integration. There's no second reader and no second content type.

## Parsing

`XMLParser` rather than a document tree, because these files run to megabytes and everything wanted
from one is decided on the way past. A 1.6 MB book parses in about 60 ms.

Namespace processing is off, so element names arrive as written. That's what makes `l:href` on a
coverpage image readable as an attribute name.

What's kept: the title, the authors, the annotation, the language tag that picks the hyphenation
dictionary, the series and its number, and the cover. Chapter illustrations are dropped, because a
text reader has nowhere to put them and a book's worth would sit in the database for good.

### Where a chapter starts

Sections nest. A book with parts puts its chapters one level further in than a book without, so
splitting at the top level gives one chapter per part: on the sample that meant five chapters of
100,000 characters each.

A section holding sections is therefore a part rather than a chapter. What it holds directly (its
title, an epigraph) becomes a short page of its own, and the sections inside it become the chapters.
The part's own page is emitted when it gains its first child rather than when it closes, because its
children close before it does and the book has to come out in reading order.

Only the first `<body>` is the book. A second one holds footnotes, which the reader has nowhere to
show.

A run of `<empty-line/>` collapses to one centred row of stars, which is how the service's own chapters
mark a scene break.

## Getting a file in

Two ways, one path. The plus button on the shelf opens the picker; a file opened from another app
arrives through `onOpenURL`. Both go through `BookInbox`, because a file can be handed over while the
library screen doesn't exist yet, so the reading-in can't live there.

The app declares FB2 in `UTImportedTypeDeclarations` rather than exporting it, since the format is
somebody else's and this app only claims to read it. That's also why it takes `Default` handler rank
instead of `Owner`. `LSSupportsOpeningDocumentsInPlace` is on: the text is copied into the store on the
way past, so nothing needs duplicating into the app's container first.

A book that came from a file says so on its cover, with a small mark in the corner opposite the reading
ring. It's smaller than the ring on purpose: a book's provenance matters less than how far through it
the reader is.

## Numbering

The service numbers works from one upwards. Local books count down from below zero, so the two can
never collide and every table stays keyed on a single number. A book takes a block of a million, and
its chapters take ids from inside that block, which keeps the chapter table's primary key unique across
a library holding both kinds.

A book is filed under its `document-info/id` where the file has one, and under its title and author
where it doesn't. So a corrected file lands on the book it corrects rather than beside it, keeping its
id, its place in the library and the reader's position. Hashing the bytes would file every corrected
copy as a new book.

`LocalBooks.isLocal` is what a screen asks before calling the service. A shelf replace, a download
clear, marking a book read, taking one off a shelf, reporting progress and every fetch step around
local books. Removing an imported book is a real deletion, since its text is on the device and nowhere
else, so the book page asks first.

## Text the typesetter has already been through

Binding the words a line may not break between and marking every hyphenation point costs about as much
as laying the book out, and neither depends on the font, the margins or the page size. `BookProcessor`
does it once per chapter and `LocalStore` keeps the result, so a book opened again costs a read rather
than the work.

Two hashes ride with each stored chapter:

- **The content hash** is the chapter's own text. It differs when the words changed, and it's what
  decides whether a chapter must be set again.
- **The chain hash** is that hash folded into every chapter before it. It differs from the first
  changed chapter through to the end of the book, and says the book's *shape* has moved even where a
  later chapter's own words have not.

Both matter because pagination is order-dependent: a chapter laid out after a longer neighbour starts
further down its first page. So a chapter whose words are unchanged but whose chain has moved keeps its
prepared text and gets a fresh chain, and only chapters that actually changed go through the typesetter
again. That is what lets a corrected file re-use everything it didn't touch.

The walk runs at utility priority and yields between chapters, so a book being prepared never holds up
a page turn. A book opens on its first chapter as soon as that one chapter is ready; the shelf shows a
bar under the book while the rest arrives, and it stays readable throughout.

Clearing downloads leaves local books alone. The service can send its text again and a file can't.
