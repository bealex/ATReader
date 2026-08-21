# TODO

Ordered roughly by how much each would bite. Everything here is something I hit while building or
testing, and the four claims that mattered were checked against the code rather than remembered. Add
your own freely.

## Bugs and half-finished plumbing

- [x] **Tokens are never refreshed, so sign-in dies daily.** The client now retries once behind a
      refresh when the service rejects a token, `SessionStore` renews one near expiry at launch and on
      every return to the foreground, and only a rejected token signs the reader out.
- [x] **`isOffline` is set and never shown.** The reader carries a `wifi.slash` glyph in its toolbar,
      and the library keeps its own flag when a refresh fails.
- [x] **The library loads one page and stops.** `fullUserLibrary` pages until the service runs out.
- [x] **Reading position goes nowhere.** It is kept on the device, as a character offset in
      `LocalStore`, and the reader resumes from it. The service call still goes out and still stores
      nothing.
- [ ] **Search scopes filter what's already loaded.** Picking "Author" narrows the current page, so it
      can show an empty list while the service holds plenty more. Page until enough matches arrive, or
      drop the scopes and let `q` match both fields on its own.

## Decisions for you

- [x] **Tap zones.** Settled: both outer thirds turn forward, as originally specified. Swiping right
      is the way back.
- [ ] **Catalogue behind sign-in.** The API serves search and the charts to guests, and the UI tests
      depend on that, but the app still gates them.
- [ ] **Icon source art.** `Resources/*.png` is about 5 MB the app never bundles; only `app-icon.icon`
      ships. Keep them as sources or move them out of the repo.
- [ ] **Release signing.** Release carries no identity and no profile on purpose, so it fails loudly
      instead of signing with the development one. Fill both in through `Local.xcconfig` once a
      distribution profile exists.

## Testing

- [ ] **There's no app-side unit test target.** Nine services in `Code/Services` have no unit tests:
      `LocalStore`, `CoverCache`, `ChapterPagination`, `ChapterUpdateService`, `SessionStore`,
      `KeychainStore`, `CatalogFeed`, `BackgroundRefresh`, `ReaderSettings`. `ChapterPagination` and
      `CatalogFeed` are pure enough to cover in an afternoon, and both fail in ways nobody would notice.
- [ ] **Background refresh has never run on a device.** The simulator won't fire `BGTaskScheduler`, so
      only the foreground sweep is proven.
- [ ] The UI tests hit production, so a full run takes about four minutes and flakes now and then. A
      cheaper offline layer underneath would take the pressure off them.

## Reader

- [ ] **VoiceOver gets a whole page as one label.** `ChapterPageView` publishes the page text as a
      single accessibility element, so there's no paragraph navigation and no rotor support.
- [x] **Justification opens rivers in a narrow column.** The reader lays out with TextKit now, which
      hyphenates English and Russian from the system dictionaries and draws the hyphen. What it does
      not offer is the finer typographic rules: no limit on consecutive hyphenated lines, and no way to
      spare the last word of a paragraph or of a page.
- [ ] Dynamic Type does nothing in the reader. That may be right, since it has its own size control,
      but the rest of the app still needs checking.
- [ ] No brightness control, no haptics on a page turn, and the screen still sleeps while reading.
- [ ] The running head is the book's title on every page. A chapter title on the verso, the way a
      printed book does it, would be more use.
- [ ] Chapter downloads are budgeted per sweep (60 in the foreground, 15 in the background) and
      backfill what is missing, so a long absence fills in over several sweeps rather than at once.

## Not started

- [ ] Audiobooks. `/v1/audiobook/*` covers them and none of it is wired up.
- [ ] Purchases. Paid books get a badge and locked chapters get a padlock, with no way to buy and no
      explanation of why a chapter won't open.
- [ ] Series navigation. `seriesId` and `seriesNextWorkId` are modelled and unused.
- [ ] Marking a book finished from inside the reader instead of only from the book page.
- [ ] Notifications for new chapters. The badge exists; nothing is ever delivered.
- [ ] iPad layout. The app builds for iPad and looks phone-shaped on it.

## Housekeeping

- [x] The cover cache has no size cap. It holds 2000 covers in Application Support and drops the least
      recently used beyond that.
- [ ] Error handling is inconsistent. The library raises an alert, other screens show inline text or
      say nothing, and almost none offer a retry.
- [ ] No pull-to-refresh on Search or the charts.
- [ ] `Documentation/DevelopmentHistory.md` stops at the cover work. Keep appending.
