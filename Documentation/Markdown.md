# Markdown

A Markdown file comes in the way an FB2 or an EPUB does: `MarkdownFormat` reads it into a `ParsedBook`
whose sections are written in the chapter vocabulary, and nothing past the import knows where it came
from.

## Telling one apart

Markdown asks nothing of a file, so `MarkdownFormat` is asked last and takes whatever is left: text that
decodes as UTF-8 (or UTF-16 with a byte order mark), holds no NUL, isn't an archive and doesn't open
with `<`. A plain `.txt` file reads as a book of paragraphs, which is what it is.

## Chapters

The headings cut the book, two levels deep, and those two levels are what the contents shows.

- A lone heading at the top level with no text before it names the document. It becomes the book's
  title, and the level below it cuts the chapters.
- Whatever stands between that heading and the first chapter is a page of its own, filed under the
  book's name, and is dropped when it holds nothing but the heading.
- The two shallowest levels left are chapters and the sections inside them. A deeper heading stays
  where it is, as a heading inside its section.
- Each section opens with its own heading, so the reader draws no heading of its own over it.

A YAML front matter block gives `title`, `author` (or `authors`, as a list or split by commas), `lang`,
`description` and `id`. Its title beats any heading. Without one, the book is named by its first
heading, and a document with no heading at all by its first six words, cut short with an ellipsis. A
document with neither a front matter title nor a heading is filed by a hash of its bytes, since two
notes filed by their opening words would land on the same book whenever they open alike.

## What is read

| Markdown | Chapter body |
|---|---|
| `**bold**`, `*italic*`, `***both***` | `<strong>`, `<em>` |
| `~~struck~~` | its words, unmarked |
| `` `code` `` | its characters, escaped |
| a line ending in two spaces or `\` | `<br>` |
| `[words](#heading)` | a link into the book, to that heading's anchor |
| `[words](https://…)` | the words alone |
| `![alt](data:image/…;base64,…)` | a picture the book keeps |
| `![alt](file.png)` | nothing: the file isn't here |
| `[^label]` with `[^label]: …` | a note, written under each chapter that points at it |
| `-`, `*`, `+`, `1.` lists, nested | `data-list` with the mark in the text; `- [x]` shows `☑` |
| `> quote` | `data-inset` |
| fenced or indented code | one verse block, held off both edges, with its indent kept |
| `---`, `***`, `___` | a centred `* * *` scene break |
| a pipe table | `<table>` |
| a `<table>` written in HTML | passed through as written |

Every heading carries a `data-anchor` made the way GitHub makes one: lowercased, punctuation dropped,
spaces turned into hyphens, and a number added to a repeat. That's what lets a document's own table of
contents link into the book.

Code has no face of its own on the page. Its leading spaces become figure spaces, which nothing
collapses, and a line too long for the measure runs over the way a line of verse does.

## Tables

A table is a `<table>` in the chapter body, read by `BookHTML` into a `BookTable` on a block of its own.
How the page draws it and how a tap opens it is in the Tables section of [Reader.md](Reader.md).
