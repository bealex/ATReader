# Fixtures

Book text, kept out of the repository and read by the tests when it's there.

## Reports

`Reports/<name>/` is one debug report unzipped: the reader's own button writes `page.txt`,
`settings.txt`, `lines.txt` and `screen.png`, and `PageReport` reads the first two. `Scripts/app.sh
test` names this directory in `TEST_RUNNER_AT_REPORTS`, so `DevicePageTests`, `SpacingTests` and
`PageRenderTests` check whatever is here on every run, each page at the settings it was read at.

Unzip a page reported as badly set into a directory of its own, and give it a name that says what was
wrong with it.

## Titles

`Titles/series-titles.tsv` is every book of a series from a library backup, one a line: series, author,
the volume the file states, the title, what the shelf showed when the list was written, and what it
should show. `SeriesTitlesTests` checks the shelf against the last column on every run.

    TEST_RUNNER_AT_BACKUP=~/…/Backup/ATReader TEST_RUNNER_AT_TITLES_WRITE=1 \
    Scripts/app.sh test --only ATReaderTests/SeriesTitlesTests

writes the list afresh, with the last column filled in from what the shelf shows now. Correct that
column by hand; it is what the shelf is held to from then on.

`TEST_RUNNER_AT_TITLES_SHELF=1` in place of `…_WRITE` writes `Titles/shelf-titles.tsv` instead: every
book of a series the way the whole library shows it, card by card: its title, series and shown title,
the volume it states, the volume its title gives, the volume the shelf shows, and its card.

