# TODO

What's still open, roughly in the order it would bite. Finished work isn't listed here: it's in
`Documentation/History/`, dated.

## Bugs and half-finished plumbing

- [ ] **Search scopes filter what's already loaded.** Picking "Author" narrows the current page, so it
      can show an empty list while the service holds plenty more. Page until enough matches arrive, or
      drop the scopes and let `q` match both fields on its own.
- [ ] **The pagination progress bar has never been seen.** It appears over 239 KB and real chapters are
      a fiftieth of that, so the path is verified by construction only. Either find a book that trips
      it or lower the threshold and watch it once.
- [ ] **Jumping backwards past the prepared window re-paginates.** A chapter's run-on offset comes from
      the chapter before it, so arriving from far away can lay it out differently than reading into it
      did. Harmless in practice, visible as a page count that shifts by one.
- [ ] **`LocalStore` has no size ceiling.** Chapter bodies accumulate for every book on the shelf, and
      only "Clear downloads" removes them.

## Decisions for you

- [ ] **Catalogue behind sign-in.** The API serves search and the charts to guests, and the UI tests
      depend on that, but the app still gates them.
- [ ] **Icon source art.** `Resources/*.png` is about 5 MB the app never bundles; only `app-icon.icon`
      ships. Keep them as sources or move them out of the repo.
- [ ] **Release signing.** Release carries no identity and no profile on purpose, so it fails loudly
      instead of signing with the development one. Fill both in through `Local.xcconfig` once a
      distribution profile exists.
- [ ] **iOS 27 only.** Deliberate, and it means paired devices on 26.x can no longer install the app.

## Testing

- [ ] **There's no app-side unit test target.** `LocalStore`, `Typography`, `ChapterLayout`,
      `CoverCache`, `ChapterUpdateService`, `SessionStore`, `KeychainStore`, `CatalogFeed`,
      `ReaderSettings` have none. `Typography` and the page breaker are pure enough to cover in an
      afternoon and both fail in ways nobody would notice.
- [ ] **The signed-in paths are unproven.** Token refresh, expiry and the library suites all need an
      account; none has run.
- [ ] **Background refresh has never run on a device.** The simulator won't fire `BGTaskScheduler`, so
      only the foreground sweep is proven.
- [ ] The UI tests hit production, so a full run takes about four minutes and flakes now and then. A
      cheaper offline layer underneath would take the pressure off them.

## Reader

- [ ] **No ladder control.** Nothing caps consecutive hyphenated lines, and a paragraph's last line can
      still be a single short word. Both need control over line breaking rather than page breaking.
- [ ] **VoiceOver gets a whole page as one label.** `ChapterPageView` publishes the page text as a
      single accessibility element, so there's no paragraph navigation and no rotor support.
- [ ] The running head is the book's title on every page. A chapter title on the verso, the way a
      printed book does it, would be more use.
- [ ] Dynamic Type does nothing in the reader. That may be right, since it has its own size control,
      but the rest of the app still needs checking.
- [ ] No brightness control, no haptics on a page turn, and the screen still sleeps while reading.

## Not started

- [ ] Audiobooks. `/v1/audiobook/*` covers them and none of it is wired up.
- [ ] Purchases. Paid books get a badge and locked chapters get a padlock, with no way to buy and no
      explanation of why a chapter won't open.
- [ ] Series navigation. `seriesId` and `seriesNextWorkId` are modelled and unused.
- [ ] Marking a book finished from inside the reader instead of only from the book page.
- [ ] Notifications for new chapters. The badge exists; nothing is ever delivered.
- [ ] iPad layout. The app builds for iPad and looks phone-shaped on it.

## Housekeeping

- [ ] Error handling is inconsistent. The library raises an alert, other screens show inline text or
      say nothing, and almost none offer a retry.
- [ ] No pull-to-refresh on Search or the charts.
