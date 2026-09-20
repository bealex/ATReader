# Books from files

A book can come from a file on the device instead of from the service. Once it's in, nothing downstream
can tell the difference: the same library row, the same book page, the same reader.

Two formats are read. FB2 is described below; EPUB has enough of its own to say that it lives in
[Epub.md](Epub.md). `BookImporting.formats` holds both, and the bytes decide which one reads a file
rather than its name.

## The seam

Everything a screen shows comes out of `SQLiteBookStore`, and the reader's pipeline starts at a chapter
*body*, which is HTML. So an imported book only has to fill the rows a download would fill: one work,
one chapter per section, one body per chapter. `FB2Parser` emits each section as the same `<p>` markup
a chapter arrives in from the service, and `BookHTML`, `ChapterContent`, `ChapterPagination` and
`ChapterLayout` then work on it unchanged.

That's the whole integration. There's no second reader and no second content type.

## Archives

FB2 books are handed out zipped more often than not, and an EPUB is an archive by definition, so one is
opened on the way in rather than the reader being asked to unpack it first. The bytes decide, not the
name: FB2 books arrive called `.fb2.zip`, `.zip` and occasionally `.fb2` while being an archive all the
same.

The platform has no public API for reading a zip, so `ZipArchive` reads the little of the format a book
needs. It walks the central directory rather than the local headers, because a zip written as a stream
leaves the sizes zero in the local header and fills them in afterwards. Members are stored or deflated,
and a zip member's deflate stream is exactly what `NSData.decompressed(using: .zlib)` reads. The Zip64
records a large archive keeps its numbers in are read too; encryption and multi-disk archives are
refused rather than half-supported.

The book taken out of an FB2 archive is the first `.fb2` member, or the largest file where none says so.
Directories and the second copy of every file that a Mac writes under `__MACOSX` are skipped.

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

A section holding sections is therefore a part rather than a chapter. What it holds directly, its
title and whatever stands under it, becomes a short page of its own, and the sections inside it become
the chapters. That page is settled when the part gains its first child rather than when it closes,
because its children close before it does and the book has to come out in reading order.

The body itself is opened the same way, so what a book puts before its first section stays in the book
instead of falling out of it: the plate it opens on, the epigraphs it carries. A body has no name to
give that page, and an unnamed page reads in the contents as a chapter nothing can call. So front
matter carrying no title leads the section opening under it, landing after that chapter's heading and
before its text. A plate keeps a page of its own, being something to look at rather than something to
read.

A body's own `<title>` doesn't come across at all, because it names the book rather than a chapter and
the reader shows it before the first page anyway. A plate repeating the cover the description already
named is dropped for the same reason.

Only the first `<body>` is the book. A second one holds footnotes, which the reader has nowhere to
show.

A `<subtitle>` carrying nothing but the marks of a scene break is one, which is how a good many files
write them; a subtitle carrying words is a heading and cuts the chapter as it always did.

The marks are the file's own. A book that parts its scenes with a single asterism is not a book of star
rows, and writing a row where it wrote one mark would put on the page words that nobody wrote.

Nothing at all is written for `<empty-line/>`. It holds no marks to keep, having only a gap, and a row
of stars in its place is text the file never carried. One reported book wraps every plate in a blank
line above and below, which came out as a row of stars over and under each of its twenty-nine pictures.
What that costs is a book marking its scene breaks with nothing but blank lines, which now shows no
break at all: the gap itself would have to be carried through as air rather than as text, and no file
has yet asked for it.

Which marks count is `BookHTML.isSceneBreak(_:)` and nothing else, so the test that centres a break and
the test that keeps one off the top of a page can't drift apart and start disagreeing.

The break is written where the file puts it, rather than held over until the next paragraph arrives.
Held over, a picture standing between the two swallowed it, and so did the end of a section, so a
reader met the break further down the chapter than the book wrote it or never met it at all.

### What a paragraph carries, and how it is set

`<emphasis>` and `<strong>` come across as `<em>` and `<strong>`, wrapped round the words they covered
and nested where the file nested them. They are recorded as the file is walked, the way a note's marker
already was, because the words arrive as characters with no tags in them: what is kept is where each
mark opened and closed. The words themselves are untouched, since a reading position counts them.

How a block is set comes from where the file put it rather than from anything it styles. A paragraph
inside an `<epigraph>` or a `<cite>` is a passage quoted rather than told, and is held off the edge the
way the reader already holds one. A `<poem>` is centred. A `<text-author>` stays with whatever it names,
is set in italics and stands at the far edge of the passage it names, which is how a book gives a
quotation its source. At the far edge of the quotation, not of the page: an epigraph is held off both
edges and its attribution is set against the passage rather than against the margin. Everything else is a plain paragraph.

A `<v>` inside a `<poem>` is a line of verse and says so with `data-verse="1"`, which is kept alongside
whatever else the block is rather than instead of it: a poem quoted as an epigraph is both verse and a
quotation, and the setting above answers only the second. See the Verse section of [Reader.md](Reader.md)
for what the page then does with it.

### Where the pictures go

A picture is written out as a file beside the book, one directory per book, and the `<img>` left in the
chapter body names it. Bytes in the database would be read again on every re-pagination, and a chapter
body is read often.

That name carries the book as well as the picture, so a chapter body holds everything needed to find
its own pictures and nothing has to be passed alongside it. Removing an imported book removes the
directory; a corrected file clears it first, since the new file may have dropped pictures the old one
had. See `Documentation/Reader.md` for what the reader then does with them.

### A book's cover moves under it

An imported book's cover is a file in the app's own container, and **the system gives the app a new
container every time it is installed**. The path written down when the book arrived names a directory
that is no longer there, so `SQLiteBookStore` works a local book's `coverURL` out again from its number
as it reads one rather than trusting what was stored. Without that every local book loses its artwork
after an install, and with it the spine, which is a blur of that artwork.

`SpinePress` reads that file itself for the same reason. It takes any other cover only if one is already
at hand, so printing a shelf pulls nothing down, but a book standing on its edge never decodes its own
cover, so a spine that waited for one to arrive waited for ever and stood bare for good.

### Reading the file again

**`BookReading.version` is what makes a parser reach books already on the shelf.** A chapter holds
whatever the parser made of the file when it was read, so re-measuring sets the words it holds again and
cannot add words it never held. Raise that number whenever a change puts something different into a
chapter's stored text, and `local_book.reading_version` then dates every copy that is behind it.
Changes to how text is set rather than to what it holds belong in `Typography.version` instead, which
prepares the text again without reading the file.

A book behind that number is read again as it opens. `ReaderScreen.Model.rereadIfBehind()` does it
before the chapters come out of the store, so what the reader turns to is what this build makes of the
file, and `BookInstaller` carries the reading position across whatever the new reading cuts the book
into. The reader waits on it once per book, behind the card that already covers opening one.

One book as it opens rather than a library at launch. `BookInbox.rereadWhatIsBehind()` reads every book
that is behind in one pass and nothing calls it: doing that at launch cost five books that had been read
through their positions, and a position lost is lost for good.

Re-import by hand reads the kept file with this build's parser and writes the chapters over the ones already
there. It is filed under whatever the book is already filed under, never under the name its file gives
it: a book a service handed over is named by that service, and working the name out from the file again
names it something else, which stands the same book on the shelf a second time instead of correcting
the one that is there. `ReimportTests` holds that.

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

## Notes

A file keeps its notes in a second `<body>`, at the end, long after the chapter pointing at them. The
parser reads that body into notes by id, keeps the `<a>` anchors in the paragraphs that refer to them,
and writes each note out under the chapters that use it. A chapter from a file then carries its own
notes exactly as one from the service does, and nothing downstream knows which it is holding. See the
Notes section of [Reader.md](Reader.md).

## Getting a file in

Two ways, one path. The plus button on the shelf opens the picker; a file opened from another app
arrives through `onOpenURL`. Both go through `BookInbox`, because a file can be handed over while the
library screen doesn't exist yet, so the reading-in can't live there.

The app declares FB2 in `UTImportedTypeDeclarations` rather than exporting it, since the format is
somebody else's and this app only claims to read it. That's also why it takes `Default` handler rank
instead of `Owner`. EPUB needs no declaration at all: every Apple platform already knows that type, so
the app only claims to open it, at `Alternate` rank. That claim is also what puts Bookhold in the share
sheet, which is how a book reaches it from Books.app.

`LSSupportsOpeningDocumentsInPlace` is on: the text is copied into the store on the way past, so nothing
needs duplicating into the app's container first.

A book that came from a file says so on its own page. Its cover carries no mark for
it: where a book came from matters less than how far through it the reader is.

## The book a fresh install opens with

`Resources/Books/first-book.fb2.zip` ships in the app, and `FirstBook.offer(through:)` reads it in
through the inbox on first launch, the same path a file picked by hand takes. A shelf with one book on
it beats an empty one, and the reader can read something before signing in to anything.

Once only. The mark is `firstBook.offered` in user defaults, and it goes down after the attempt rather
than after a success, since a file this build can't read won't read any better tomorrow. A reader who
deletes the book has deleted it: nothing puts it back. `FirstBookUITests` covers both halves, driving
the app with `-firstBook.offered NO` to make a launch look fresh.

The file is bundled under a name of its own rather than the book's, so swapping the file swaps the
book. What it's called on the shelf comes out of the FB2's own metadata.

## Numbering

The service numbers works from one upwards. Local books count down from below zero, so the two can
never collide and every table stays keyed on a single number. A book takes a block of a million, and
its chapters take ids from inside that block, which keeps the chapter table's primary key unique across
a library holding both kinds.

A book is filed under its `document-info/id` where the file has one, and under its title and author
where it doesn't. So a corrected file lands on the book it corrects rather than beside it, keeping its
id, its place in the library and the reader's position. Hashing the bytes would file every corrected
copy as a new book.

`BookNumbering.isLocal` is what tells the two apart, though a screen rarely asks: a fetch goes
through `BookLoader`, and a book from a file routes to a loader with nothing to give. A shelf replace, a download
clear, marking a book read, taking one off a shelf, reporting progress and every fetch step around
local books. Removing an imported book is a real deletion, since its text is on the device and nowhere
else, so the book page asks first.

## Text the typesetter has already been through

Binding the words a line may not break between and marking every hyphenation point costs about as much
as laying the book out, and neither depends on the font, the margins or the page size. `BookProcessor`
does it once per chapter and `SQLiteBookStore` keeps the result, so a book opened again costs a read rather
than the work.

Two hashes ride with each stored chapter:

- **The content hash** is the chapter's own text. It differs when the words changed, and it's what
  decides whether a chapter must be set again.
- **The chain hash** is that hash folded into every chapter before it. It differs from the first
  changed chapter through to the end of the book, and says the book's *shape* has moved even where a
  later chapter's own words have not.

A chapter whose words are unchanged but whose chain has moved keeps its prepared text and gets a fresh
chain, and only chapters that actually changed go through the typesetter again. That is what lets a
corrected file re-use everything it didn't touch.

The walk runs at utility priority and yields between chapters, so a book being prepared never holds up
a page turn. A book opens on its first chapter as soon as that one chapter is ready; the shelf shows a
bar under the book while the rest arrives, and it stays readable throughout.

### Rules count as input

What is stored is the output of the rules on the source, so both are in the key: `Typography.version`
rides in the content hash, and it is bumped by hand whenever a rule changes what comes out.

Without it the store is a trap rather than a saving. Correcting the dashes changed the prepared text
without touching a byte of any chapter's source, so every book already on the device would have gone on
showing the marks an older typesetter chose, with nothing in the source to say it was stale. Bumping
the version makes every book prepare itself once more, and be quick again after that.

Nothing about pages is stored. The reader cuts a book into pages around wherever the reader is, a few
milliseconds a page, so a change of font or of screen costs the page in front of them and nothing else.

Clearing downloads leaves local books alone. The service can send its text again and a file can't.

## Covers

A file's own cover is made for print: one measured at 1500 by 2359 took three megabytes, and five
hundred of those came to a quarter of a gigabyte on the device and in every backup. `LocalBookFiles`
holds a cover to `CoverCache.maximumPixelSize` as it is taken in, which is the size the largest cover on
a screen is drawn at, and covers taken in before that are shrunk once by `Covers.shrinkWhatWasKept()`
behind whatever the reader is doing. A picture's size is read from its header, so a library already
holding small covers costs one pass over a directory listing.

## Paths through the container

Everything a book from a file brings with it lives under Application Support, and the path to it runs
through the app's container: `…/Containers/Data/Application/<UUID>/Library/Application Support/Books/…`.
That UUID is a different one after every install, so a path held from one run of the app is a path to
nothing in the next. Nothing that outlives the process may be filed under one.

What was filed under one, and what it cost:

- **A cover's shape**, in `cover_shape`, keyed by the address the picture came from. A book from a file
  lost its shape at every install, and a shelf that doesn't know a book's shape stands it in the slot it
  guessed and cuts its picture to fit, which is a cover with its title sliced off. Now kept in
  `book_shape` under the book's own id, with the spine's shape beside it.
- **The downsampled copy of a cover**, whose file name in `CoverCache` is a hash of that address. A
  local cover is read and downsampled again after every install, and the copy made under the old name
  sits in the cache until it is swept. Nothing shows, and it costs a decode and the room.

What holds, and why:

- **Pictures inside a chapter.** A stored body carries `"<book>/<name>"`, and `LocalBookFiles.imageURL`
  builds the path when the picture is wanted. The book is named in the source rather than the disk.
- **Everything else under `LocalBookFiles`.** The file, the cover and the images directory are all
  worked out from the work id when they are asked for, never written down.
- **The backup folder**, which is outside the container and belongs to the reader. `LibraryBackup` keeps
  a security-scoped bookmark, which survives being moved as well as being reinstalled.
- **Caches in memory** keyed by address (`CoverImages`, `BookImages`), and anything under a temporary
  directory: the OPDS download, a debug report, the Litres sync log. All die with the run that made them.

The rule: file it under the book, or keep the part of the path the app owns and build the rest when it
is wanted.
