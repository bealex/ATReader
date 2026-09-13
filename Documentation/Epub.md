# EPUB

A book can come from an EPUB file the same way it comes from an FB2 one, and nothing downstream can
tell the difference. What follows is what is read out of one, what is deliberately not, and why the
chaptering works the way it does.

The format is [EPUB 3.3](https://www.w3.org/TR/epub-33/). Files written to the older EPUB 2 are read
too: the difference that matters is the table of contents, and both kinds are handled.

## Why this is easier than FB2, and harder

Easier, because the format states what FB2 leaves to be inferred. The spine says which documents the
book reads through and in what order, and the navigation says what each piece is called and how deep it
stands. `FB2Parser` has to work both out from how sections nest.

Harder, because a chapter is arbitrary XHTML where FB2's is a small semantic vocabulary. The same page
has fifty encodings, and what marks a scene break in one publisher's file is a class name, in another's
an `<hr>`, and in a third an empty paragraph with a margin set in CSS. `EpubContent` is the whole of
that reduction, and it is where the surprises live.

## The way in

`ZipArchive` reads the container, `ZipReader` holds it open so members can be fetched by name, and the
rest is four documents deep:

1. `META-INF/container.xml` names the package document.
2. `EpubPackage` reads that: the metadata, the manifest, the spine, and which way the book reads.
3. `EpubNavigation` reads the navigation document, or the EPUB 2 `toc.ncx` where there isn't one.
4. `EpubContent` reduces each spine document to the markup a chapter body is written in.

Names inside the archive arrive percent-encoded from the markup that points at them, and relative to
whichever document did the pointing, so every path goes through `EpubPackage.resolve` first.

## Where a chapter starts

The navigation decides. A book that keeps fourteen chapters in one file carries an anchor at each of
them and lists all fourteen at the front, so `EpubContent` marks the blocks those anchors name and
`EpubSections` cuts there. Only where a document is named once, or not at all, does it fall back to
reading the document's own headings.

Two rules follow from what real files turn out to look like:

- **A heading standing alone is a chapter's name, not a chapter.** Books that list a chapter's number
  and its title as two entries of their own navigation cut into alternating stubs and bodies, and the
  stub is the chapter's first line. Both names are kept: "CHAPTER 1. MY UNCLE MAKES A GREAT DISCOVERY".
  A piece carrying a paragraph is a chapter however short it runs, which keeps a one-line dedication a
  page of its own.
- **A page most of whose words stand inside links into the book is its contents.** The app draws a
  contents of its own, so a second one is dropped. A page whose lines are mostly titles the navigation
  also lists goes the same way. Both tests read the shape of the page rather than its name, so they
  hold whatever language the book is in.

## The reduction

`EpubContent` keeps what the reader can set and drops the rest.

| EPUB | becomes |
|---|---|
| `<p>`, a text-bearing `<div>`, `<blockquote>` | `<p>` |
| `<h1>`–`<h6>` | kept; `BookHTML.levelling` reads the level off them |
| `<em>`, `<i>`, `<cite>`, `<strong>`, `<b>` | `<i>` and `<b>`, read back out as `StyleMark`s |
| `<ul>`, `<ol>`, `<li>` | `<p data-list="N">` with the item's mark in its own text |
| `<img>`, and `<image>` inside an SVG cover | `<img>` pointing at the picture's place in the archive |
| `<hr>` | the centred row of stars a scene break is drawn as |
| a link into the book that reads as a marker | `<a href="#…">`, with the note carried into the chapter |
| any other link into the book | `<a href="#…">`, and `data-anchor` on the block it lands on |
| `<sub>`, `<sup>`, `<br>` | kept |

Ids repeat across an EPUB's files, so a reference folds the document's own path in beside the id.

A link of a few characters is a note's marker; anything longer is a place in the book. What tells the
two apart afterwards is which of them something pointed at *as a note*: every short block standing
under an id is remembered while a document is read, since a note may stand anywhere, but a block a
link merely points at is a piece of the book and stays where it already is.

Where a link lands is only known once the whole book has been looked at, because a chapter points as
often to a page further on as to one already past. So the addresses are scanned out of the markup
before anything is reduced, and only the blocks something actually points at are marked.

`XMLParser` is not used. An EPUB's XHTML routinely names entities that only the HTML DTD ever declared,
and `XMLParser` refuses the whole document over one. `Markup` scans instead: nothing in it throws, and
what it cannot make sense of it steps over.

### The stylesheets

Read for four things and nothing else: which classes centre a line, which slant it, which set it bold,
and which turn it round. A book marks its scene breaks and its epigraphs with a class and nothing else,
so without this they arrive as ordinary paragraphs. Everything else a publisher's CSS says is the
reader's to decide.

### Which way the book reads

The spine's `page-progression-direction`, or the language where the spine says nothing. It rides in the
markup as `dir="rtl"` on each block rather than on the book, which keeps a chapter body holding
everything needed to set it.

`ChapterPagination` sets the paragraph's base writing direction from it, `ParagraphRuler` puts that
direction back on the text it measures, and `ColumnComposer` stands a line short of the measure at the
right edge instead of the left. `PageTurnView` mirrors every horizontal distance it reads or draws, so
a book read from the right turns forward under a finger drawn the other way.

## What is ignored

Most of the specification by page count, and almost none of what a novel contains.

**Refused outright, with an error rather than a page of noise:**

- Fixed layout (`rendition:layout="pre-paginated"`). Comics and children's books. They cannot reflow.
- DRM. `META-INF/rights.xml`, or an `encryption.xml` naming anything but the two font-obfuscation
  algorithms, which are harmless here because the reader never opens a book's own fonts.

**Dropped, because the page belongs to whoever is reading:**

- CSS, beyond the four questions above. Colour, indentation, drop caps, page-break hints, spacing.
- Embedded fonts, media overlays, audio, video, scripting, remote resources.
- MathML, ruby annotations, the page-list and landmarks navigations, bindings, fallback chains.
- Multiple renditions: the first rootfile is the book.
- Tables. There is no table support anywhere in the renderer, so a table's rows flatten to paragraphs.

## Zip64

`ZipArchive` reads the wide records a large archive keeps its numbers in: the Zip64 end-of-directory
and its locator, and the extra field on each member that overflowed. A field the ordinary record gives
as all ones stands in that extra field instead, and the three numbers it may carry are present only
where they were needed, in a fixed order.

## Tests

`EpubFormatTests` builds whole archives out of generated nonsense and reads them back, `Zip` writes
them so the reader is checked against bytes rather than against a mock of itself, and `EpubBooksTests`
reads whatever real books stand in the gitignored `Fixtures/Books`. That last one asserts nothing about
any book's words, only the shape of what comes out, and prints a summary of each so a change to the
reduction can be looked at rather than guessed at.
