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

## Archives

FB2 books are handed out zipped more often than not, so an archive is opened on the way in rather than
the reader being asked to unpack one first. The bytes decide, not the name: these arrive called
`.fb2.zip`, `.zip` and occasionally `.fb2` while being an archive all the same.

The platform has no public API for reading a zip, so `ZipArchive` reads the little of the format a book
needs. It walks the central directory rather than the local headers, because a zip written as a stream
leaves the sizes zero in the local header and fills them in afterwards. Members are stored or deflated,
and a zip member's deflate stream is exactly what `NSData.decompressed(using: .zlib)` reads.

Zip64, encryption and multi-disk archives are refused rather than half-supported. The book taken out is
the first `.fb2` member, or the largest file where none says so; directories and the second copy of
every file that a Mac writes under `__MACOSX` are skipped.

## Parsing

`XMLParser` rather than a document tree, because these files run to megabytes and everything wanted
from one is decided on the way past. A 1.6 MB book parses in about 60 ms.

Namespace processing is off, so element names arrive as written. That's what makes `l:href` on a
coverpage image readable as an attribute name.

What's kept: the title, the authors, the annotation, the language tag that picks the hyphenation
dictionary, the series and its number, the cover, and every picture the text points at.

A `<binary>` is decoded only where an `<image>` has already asked for it by name, which the file's own
ordering makes possible: FB2 puts its binaries after its text. So a file full of pictures nobody
references costs nothing to skip.

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

### Where the pictures go

A picture is written out as a file beside the book, one directory per book, and the `<img>` left in the
chapter body names it. Bytes in the database would be read again on every re-pagination, and a chapter
body is read often.

That name carries the book as well as the picture, so a chapter body holds everything needed to find
its own pictures and nothing has to be passed alongside it. Removing an imported book removes the
directory; a corrected file clears it first, since the new file may have dropped pictures the old one
had. See `Documentation/Reader.md` for what the reader then does with them.

### The file is kept

What a book holds is whatever the parser made of its file at the time, and a parser that has since
learned something can only be applied to the file. So the book's own text is kept beside it, and the
book screen's menu carries a **Re-import** that reads it again in place.

It is kept compressed, which is worth about a third: the sample book is 7.1 MB of XML and base64 and
2.4 MB of that goes. Not more, because the pictures inside it are already compressed and base64 is most
of what is left. What is kept is the book rather than the archive it arrived in, so a second reading
never has to unpack anything.

Re-importing over a book rather than deleting it first is what keeps the reading position. Removing a
book deletes its `reading_position` row along with everything else, where a file carrying the same book
lands on the same row and leaves the position alone.

A book imported before its file was kept has none, and its menu asks for the file instead.

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

### Measurements

Preparing the text is the cheaper half. The other half is `BookPagination`, which lays out every
chapter in order to find where each one starts and how many pages it runs to, and that runs whenever a
book is opened: the pagination lives on the reader's model, which goes when the screen does.

So a measurement is kept too, against two keys. The chain hash says the book is the same book up to
this chapter, which is what a chapter's start position depends on. A style fingerprint says the setting
is the same setting: face, weight, size, line and letter spacing, justification, margins, page size and
safe area. The text colour is deliberately absent, so crossing into the dark doesn't throw the book's
measurements away.

The chapter's hash is read before its text, because the hash is one small row and the prepared text is
a large one. A book reopened unchanged never loads its own text at all: it reads a measurement per
chapter and lays out only the chapter on screen.

Measuring starts when a book is opened and gets no further than it must. A chapter's place depends on
every chapter before it and on none of the ones after, so the run ending at the chapter being opened is
enough to put the reader on a page. The chapter after that one is measured too, since whether it begins
on this chapter's last page has to be settled before the reader can turn onto that page. Opening at the
first chapter therefore measures two, whatever the length of the book.

The rest follows behind the reader, a chapter at a time at utility priority, and never while a page is
turning. Laying a chapter out runs on the main actor, so a chapter measured mid-turn would take its
frames from the animation. Every turn pushes the background pass off for a moment, which also keeps it
off a reader turning steadily rather than letting it in between two quick turns.

### Rules count as input

What is stored is the output of the rules on the source, so both are in the key. `Typography.version`
rides in the content hash and `ChapterLayout.rulesVersion` in the style fingerprint, and each is bumped
by hand whenever a rule changes what comes out.

Without them the cache is a trap rather than a saving. Correcting the dashes changed the prepared text
without touching a byte of any chapter's source, so every book already on the device would have gone on
showing the marks and the line breaks an older typesetter chose, with nothing in the source to say it
was stale. Bumping a version makes every book prepare and measure itself once more, and be quick again
after that.

Clearing downloads leaves local books alone. The service can send its text again and a file can't.
