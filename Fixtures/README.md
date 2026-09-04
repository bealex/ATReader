# Fixtures

Book text, kept out of the repository and read by the tests when it's there.

## Reports

`Reports/<name>/` is one debug report unzipped: the reader's own button writes `page.txt`,
`settings.txt`, `lines.txt` and `screen.png`, and `PageReport` reads the first two. `Scripts/app.sh
test` names this directory in `TEST_RUNNER_AT_REPORTS`, so `DevicePageTests`, `SpacingTests` and
`PageRenderTests` check whatever is here on every run, each page at the settings it was read at.

Unzip a page reported as badly set into a directory of its own, and give it a name that says what was
wrong with it.
