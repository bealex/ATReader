# TODO

What's still open, roughly in the order it would bite. Finished work isn't listed here: it's in
`Documentation/History/`, dated.

## Bugs and half-finished plumbing

- [ ] **Search scopes filter what's already loaded.** Picking "Author" narrows the current page, so it
      can show an empty list while the service holds plenty more. Page until enough matches arrive, or
      drop the scopes and let `q` match both fields on its own.
- [ ] **Pages cut forwards and backwards needn't agree.** A page reached by reading on and the same
      page reached by turning back to it can break in different places, since each is cut from the
      page beside it. The sheets the reader has seen are kept, so it takes leaving the run of them and
      coming back; what shows is a line moving from one page to the next.
- [ ] **A pinned author's name comes back from a book without its bar.** Only `scrollViewDidScroll`
      works out `AuthorHeaderView.isFloating`, and `prepareForReuse` clears it while the reader
      covers the list, so the scroll edge effect stays off until the shelf is next scrolled. Work it
      out from the layout instead.
- [ ] **The pinned name is pushed back with the books.** UIKit's zoom puts its pushback on the list's
      `sublayerTransform`, so a name that's meant to read as part of the bar scales while the bar holds
      still. Either counter-transform its contents while a zoom runs, or lift the pinned name out of
      the scrolling list altogether.
- [ ] **The shelf holds its shrunk size for over a second after a book closes.** Measured at 1.55
      seconds of a still screen before the scale springs back. Time the main thread across `onGone`
      and log what rect the zoom is shrinking into before changing anything.
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
- [ ] **`BookmarkUITests` fails on the mark it takes off.** Swiping a mark in the contents and tapping
      Remove leaves a row the test still finds. It fails the same way two commits back, so it is the
      test or the contents list rather than anything the marks themselves changed, and the reader's own
      bar clears a mark as it should.
- [ ] **`DevicePageTests` fails on five reported pages.** The running-head band grew after those
      reports were taken, so the measure the fixtures carry is 11pt short of the one a page is set to
      now. The reports need taking again.

## Reader

- [ ] **The book's length is guessed short.** `BookLength` counts characters against the room a page
      has, and every paragraph's last line leaves most of itself empty, which the count can't see. The
      bundled book cuts into about 254 pages on a phone and is called 154. Counting paragraphs as well
      as characters would close most of it.
- [ ] **No ladder control.** Nothing caps consecutive hyphenated lines, and a paragraph's last line can
      still be a single short word. Both need control over line breaking rather than page breaking.
- [ ] **VoiceOver gets a whole page as one label.** `ChapterPageView` publishes the page text as a
      single accessibility element, so there's no paragraph navigation and no rotor support.
- [ ] **Pictures from the service are dropped.** A chapter body's `<img>` is read as a block and then
      goes nowhere, because only a file's own pictures are on the device. Fetching and caching a remote
      one would need the layout to be redone when it lands.
- [ ] **A book imported before its file was kept can't re-read itself.** The book screen's menu asks
      for the file instead of re-reading one it holds, so those books need finding once by hand.
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
- [ ] A foldable half-opened. Treated as one screen, which is wrong once there's a hinge across it.
- [ ] The UI suite is written for a phone-shaped screen. `app.tab(_:)` finds the tabs either way now,
      but seventeen normalized-coordinate taps still assume one full-width page. On an iPad
      `ReaderTurningUITests` runs 4 of 5: `testSwipingTurnsThePageBothWays` fails on the leftward
      swipe, and whether that's `swipeLeft()` on a 1194-point element or the drag arithmetic at a
      spread's width is not yet known. Tapping to turn, rapid taps and the edge drag all pass.

## Housekeeping

- [ ] Error handling is inconsistent. The library raises an alert, other screens show inline text or
      say nothing, and almost none offer a retry.
- [ ] No pull-to-refresh on Search or the charts.
