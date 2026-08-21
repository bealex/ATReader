# Testing

Two layers: fast unit tests in the package, and UI tests that drive the real app against the real
service.

```sh
# package unit tests: offline, deterministic, ~1s
cd Frameworks/AuthorToday && swift test

# UI tests: these hit the live service
xcodegen generate
xcodebuild -project ATReader.xcodeproj -scheme ATReader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -derivedDataPath .build/dd build-for-testing

xcodebuild -project ATReader.xcodeproj -scheme ATReader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -derivedDataPath .build/dd \
  -only-testing:ATReaderUITests/CatalogUITests test-without-building
```

## Configuration

Tests that read a chapter need `.env` filled in; see the README. Without it the package unit tests
still pass, since they use their own generated constants, but the UI tests that open a chapter will see
the app report that it has no certificate.

## Unit tests

`ChapterDecryptorTests` and `ChapterHTMLTests` cover the decryption derivation and the HTML flattener.
`LoginResultTests` covers the sign-in response, including the numeric-`twoFactorType` regression.

Every fixture is written by hand from generated nonsense. The decryption tests encrypt placeholder text
through the real derivation and decrypt it back, which exercises the algorithm end to end without
storing any service content. Keep it that way; see the "Never commit" section of `CLAUDE.md`.

## UI tests

Three suites, deliberately layered by what they need:

| Suite | Needs | Covers |
| --- | --- | --- |
| `CatalogUITests` | nothing (guest token) | search, author scope, charts + period filter, opening a book, reading a decrypted chapter, chapter list, typography, page turns by tap and swipe, the controls toggle |
| `LoginUITests` | credentials, optional | field validation, service error for bad credentials, a real end-to-end sign-in |
| `LibraryUITests` | a token | library list, shelf filter, profile and sign-out |

Suites needing an account `XCTSkip` without one, so a run with no credentials is still green.
`CatalogUITests` needs no account, but its chapter-reading tests do need `.env`. Without it the app
correctly reports that it has no certificate, and those tests fail rather than skip.

### Passing secrets

Environment variables must be prefixed `TEST_RUNNER_`. `xcodebuild` strips the prefix and forwards the
rest to the test process; without it the variables never arrive and the suites silently skip.

```sh
TEST_RUNNER_AT_TEST_TOKEN="…" \
TEST_RUNNER_AT_TEST_LOGIN="…" \
TEST_RUNNER_AT_TEST_PASSWORD="…" \
xcodebuild … test-without-building
```

`AT_TEST_CODE` completes a two-factor challenge, but codes are single-use, short-lived and invalidated
by the next sign-in attempt, so that path needs a human. Getting a token once and passing
`AT_TEST_TOKEN` is the practical route for the signed-in suites.

### Reaching signed-in screens

The app gates its tabs behind sign-in, so UI tests use the `#if DEBUG` launch-argument hook:

- `-at-ui-test-guest` gives a signed-in shell on the guest token. Enough for search, charts, book pages
  and the reader.
- `-at-ui-test-token <token>` adopts a real session.

## What these tests are actually for

They run against production, which makes them slower and occasionally flaky, and it earns its keep. The
service is loosely typed and undocumented, the failures that matter are contract failures, and only a
live request finds those. `LoginUITests` caught the numeric `twoFactorType` bug by doing a real
sign-in, and it would have shipped otherwise: a unit test with a hand-written fixture would have used
the shape already believed in.

Keep at least one test per feature talking to the real service.

## Driving the reader

The reader hides everything a test would normally reach for, so its suite works differently from the
others:

- It opens with no controls at all. A test that needs Contents or Appearance taps the middle third
  first; `showChrome()` does that and waits for the buttons.
- A book opens on its title page, so a test that wants text turns one page first.
- The drawn page publishes its text under `reader.pageText`, and only the page the reader is actually
  on carries `reader.caption`. That matters: during a turn two pages are on screen, and two elements
  under one identifier make a query ambiguous.
- Enumerating `app.staticTexts.allElementsBoundByIndex` while the reader is animating raises "no
  matches found for element at index N", because the hierarchy changed between the count and the
  access. Query by identifier instead. That was a flake, not a bug.
- Reader settings come from `UserDefaults`, which reads `-key value` launch arguments, so each suite
  pins the typography it depends on rather than inheriting the last run's.

Two things XCUITest cannot express, so they are verified by construction: a drag reversed into a flick
before the finger lifts, and the app being backgrounded mid-gesture.
Say so plainly when reporting on them.

### Watching a gesture that is still happening

`press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` holds the finger down at the end of a
drag. Run that test in the background and take screenshots from the host with `simctl io … screenshot`
while it holds, and the half-finished gesture can be measured: that is how the incoming page was shown
to sit 20pt to the left of the finger, and how the rubber band at the end of a book was measured at
60.6pt against a predicted 60.3.

### Instrumenting instead of eyeballing

Typographic rules are easier to count than to look at. A temporary `#if DEBUG` print in the page
breaker, reporting hyphens at a page foot, orphans, widows and short pages per chapter, turned "looks
about right" into "no hyphens at a foot, no widows, one orphan in 87 pages" and showed that two lines
of pull-back weren't enough. Write that instrumentation, read it, then delete it before committing.

## Gotchas

- Offscreen `Form` cells don't exist. SwiftUI doesn't instantiate them, so `waitForExistence` won't
  find a control below the fold. Swipe first. This bit the reader typography test, where the sheet
  opens at the `.medium` detent and the page-tint rows start below it.
- Inline `Picker` options don't carry an accessibility identifier from their content view. The reader's
  page-tint choice is built from explicit `Button` rows instead, which is both testable and a better
  control.
- Dump the tree instead of guessing at queries. A throwaway test that prints `app.debugDescription`
  settles in one run what several rounds of guessing won't. That's how the alignment control was found
  to be a `SegmentedControl`, and how the reader page turned out to have been exposing its text
  correctly all along. Both "failures" were bad queries rather than bugs.
- `matching(identifier: "")` matches nothing, so it can't find unidentified elements. `label.length`
  isn't a valid key path in an XCUITest predicate either; read the labels in Swift instead.
- A `\.label` key path fails to compile in a UI test, because `label` is main-actor isolated. Use a
  closure.
- `expectation(for:evaluatedWith:)` doesn't compile under Swift 6 either, since it sends the test case
  across isolation. Poll in a loop, the way `waitForChange(of:from:)` does.
- Two `xcodebuild` invocations against one simulator don't merely contend: the second run's test runner
  fails to bootstrap ("test crashed with signal kill before establishing connection") and the first
  loses tests it had queued. Run them one at a time.
- Assert on identifiers rather than labels wherever a control is localized. Labels change per locale;
  identifiers don't. Search *queries* in the tests are Russian on purpose, since they're input to a
  Russian-language service rather than UI text.

## Style gate

```sh
Scripts/check.sh          # verify: format, lint, shell, String Catalogs
Scripts/check.sh --fix    # apply formatting first
```

The localization step fails on any untranslated or needs-review string, so adding an English string
without its Russian translation breaks the build. That's deliberate.
