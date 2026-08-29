# ATReader

An iOS reader client for [author.today](https://author.today): sign in, read your library, search the
catalogue, follow the charts.

Two modules. The `AuthorToday` package (`Frameworks/AuthorToday`) owns everything network- and
service-shaped; the app (`Code/`) owns screens, session, cache and background work. Keep that line:
nothing service-specific belongs in `Code/`, and nothing SwiftUI belongs in the package.

## Before you change anything

- The Xcode project is generated. Edit `project.yml`, then run `xcodegen generate`. Never hand-edit
  `ATReader.xcodeproj`, because the next generate erases your changes.
- New files need no project edit, since `Code/` and `Tests/` are directory-globbed. A new *directory*
  outside those roots does.
- Signing is manual everywhere and must stay that way. The team ID lives in the gitignored
  `Local.xcconfig`, never in `project.yml`; Debug carries the development profile and Release
  deliberately carries none. See the README's Signing section.

## Building, running and testing

`Scripts/app.sh` is the only way to build, install or test this project. Never call `xcodebuild`,
`swift test`, `simctl` or `devicectl` directly.

- `Scripts/app.sh build` compiles. Add `-d` for hardware and `--release` for the Release configuration;
  both default to a simulator in Debug.
- `Scripts/app.sh deploy` builds, installs and launches on a simulator or a device.
- `Scripts/app.sh test` runs the package unit tests and the app UI tests. `--unit` and `--ui` pick one.
- `Scripts/app.sh clean` removes `build/`.

Every run prints one line per phase and a final `RESULT` line, and writes the full log under
`$TMPDIR/atreader-logs`. When the summary isn't enough, read that log instead of reaching for the
underlying tool.

The script refuses to choose between several connected devices, so pass `--device-id` when more than one
is plugged in. Release carries no provisioning profile, so it builds but can't install on hardware.

## Style

Follow `~/Programming/_Scripts/Instructions/CLAUDE.CodeStyle.md` and `CLAUDE.SwiftUIStyle.md`. The parts
this codebase leans on hardest:

- Screens are namespace enums with `Model` and `Component` inside, split across
  `<Screen>.Model.swift` and `<Screen>.Component.swift`.
- `@Observable @MainActor final class Model` with `private(set)` state. Never `ObservableObject`.
- `Mutex` (from `Synchronization`) for shared mutable state. No `@unchecked Sendable`, no
  `nonisolated(unsafe)`.
- Every interactive element gets an `.accessibilityLabel()`; decorative views get
  `.accessibilityHidden(true)`.

Run `Scripts/check.sh` before you call a change done (`--fix` applies formatting). It gates
swift-format, SwiftLint, shell scripts and the String Catalogs in one pass. Never invoke
`swift-format` or `swiftlint` directly.

## Writing

**Every piece of prose a human will read gets a deslop pass before it counts as done.** That means the
README, everything under `Documentation/`, `TODO.md`, this file, commit messages and PR descriptions.
Run the `deslop` skill and apply what it finds instead of eyeballing it.

The patterns this repository keeps producing, worst first:

- **Em-dashes bolted onto sentences.** The first draft of the docs had 112 of them. Use a full stop when
  the aside is its own claim, a colon when it explains the clause before it, a comma when it is genuinely
  parenthetical.
- **Mid-sentence bold** used to sell a phrase. Bold belongs on list-item leaders and headings. Let
  sentence position carry the emphasis instead.
- **Filler openers**: "it's worth noting", "worth knowing", "worth recording". Say the thing.
- **"Not X, it is Y"** where the negation adds nothing. Keep the positive half.
- **Prose with no contractions**, which reads like a specification rather than a person.
- **The same point restated across sections.** Say it once, in the strongest place, and link to it from
  the others.

## Localization

English is the source language; Russian is a full second locale. Every user-facing string must be
localized and translated, and `Scripts/check.sh` fails the build if any string is missing or needs
review.

- App strings live in `Code/Resources/Localizable.xcstrings`.
- Strings the package owns (enum titles, error messages) live in its own catalog and are read with
  `String(localized: "…", bundle: .module)`.
- String extraction happens when the project is opened or built in the Xcode GUI, not on a `xcodebuild`
  command-line build, so a headless workflow never sees new keys appear. Either open the project in
  Xcode to let it extract and then fill in the `ru` values, or add the entry and its translation to the
  catalog by hand. Run `Scripts/check.sh` afterwards either way; it fails on any untranslated string,
  which is what catches keys that appeared without a translation.
- Interpolated keys use the non-positional form Swift generates (`"Rank %lld. %@, %@"`); the Russian
  value may reorder with `%1$@`-style positions.

Book content is Russian; the chrome around it isn't. Don't "fix" Russian titles coming back from the
service.

## Configuration

The two author.today service constants aren't in the repository. They live in a gitignored `.env`
(template: `.env.example`), and `Scripts/gen-secrets.sh` turns them into a gitignored Swift file during
the build. Never inline them into source. That's the whole point of the arrangement, and the reason is
licensing rather than secrecy. An unconfigured build must keep working for everything except chapters.

## Never commit

- **Service content.** No captured API responses, no real book text, titles, covers or author names,
  in fixtures, tests, previews or docs. Tests use generated nonsense; see `ChapterDecryptorTests`.
- **Credentials.** Test account details reach the tests through the environment only
  (`AT_TEST_LOGIN`, `AT_TEST_PASSWORD`, `AT_TEST_CODE`, `AT_TEST_TOKEN`), never through source.

## Things that will bite you

- **A model a view holds compares every field.** SwiftUI decides whether to redraw a row by comparing
  the values its view stores, so an id-only `==` on `WorkSummary` or `WorkMetaInfo` tells it a book is
  unchanged when its progress, badges and dates have all moved, and the row keeps yesterday's copy for
  as long as it lives.
- **The service's JSON is loosely typed.** `twoFactorType` is the string `"Email"` when a challenge is
  pending and the *number* `0` when it isn't. Enums that mirror service values conform to
  `DefaultingDecodable` so unknown members fall back instead of throwing. When you add a model, assume
  the field can be absent, null, or a type you didn't expect.
- **Chapter text is encrypted, and the key includes the signed-in account id.** A chapter fetched as a
  guest and the same chapter fetched signed-in don't share a key. See
  `Documentation/ChapterEncryption.md`.
- **The reader draws with TextKit, not SwiftUI `Text` and not CoreText.** SwiftUI can't justify text;
  CoreText can't hyphenate, and breaks a word at a soft hyphen without drawing the hyphen. Pagination
  flows the chapter through one `NSTextContainer` per page, so it agrees exactly with drawing. Drawn
  text is invisible to VoiceOver, so `ChapterPageView` publishes the page's text as its own
  accessibility label. Keep that in step with any drawing change.
- **Reading position never syncs to the service.** `/v1/reader/update-progress` returns 200 and stores
  nothing; see the note in `Documentation/API.md`. The position a device shows comes from `LocalStore`,
  which is the only place it survives. Don't "fix" the call.
- **A book from a file is numbered below zero.** The service counts works up from one, so imported
  books count down from minus one and take their chapter ids from a block beneath their own. Ask
  `LocalBooks.isLocal` before calling the service about a book: its text is on the device and nowhere
  else, and there's nothing on the other end to answer.
- **`LocalStore` is one SQLite file and the app's first source for everything.** Books, contents,
  chapter bodies and reading positions live there, and screens draw from it before the service answers.
  A change that only writes to the service leaves the app wrong offline.
- **The reader's page ignores the safe area, so the layout can't tell it how big it is.** Its size and
  the device insets come from the window; measuring the layout gives the size before the page was let
  out to the screen edges, and moves the text every time a toolbar appears.
- **The reader's position is a character offset, not a page number.** Changing the font re-paginates,
  and a page index means nothing across a restyle.
- **UI-test environment variables need a `TEST_RUNNER_` prefix** to reach the test process;
  `xcodebuild` strips it.
- **`UserDefaults` reads `-key value` launch arguments,** which is the easy way to drive reader
  settings from `simctl` without touching the UI. It only works if the default is read with a coercing
  accessor like `double(forKey:)` rather than `object(forKey:) as? Double`.
- **Form cells aren't instantiated offscreen.** A UI test looking for a control below the fold has to
  scroll first; `waitForExistence` alone won't find it.

## Documentation

`Documentation/` describes how the app works **now**: the API reference, the encryption scheme, the
architecture, the reader, the testing setup. Read `Documentation/API.md` before touching the client,
since the service has no official spec and those notes were expensive to get. Read
`Documentation/Reader.md` before touching layout, pagination or the page turn.

These documents are rewritten when the code changes, never appended to. Anything historical or
append-only goes in `Documentation/History/<YYYY-MM>/<YYYY-MM-DD>.md` instead, one file per day in a
directory per month: what happened that day, findings, measurements, approaches that failed. Keep the
main documents short enough that someone will read them.
