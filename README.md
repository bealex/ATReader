# ATReader

> **This is not a real project.** It's a test app, built for the fun of working through it with a
> coding agent. It's for personal use only and isn't ready for publishing. Treat it as an experiment
> rather than as software anyone should depend on.

An iOS reader for [author.today](https://author.today): sign in, browse your library, search the
catalogue, follow the charts, and read.

## Configuration

Browsing, search and the charts work out of the box. Reading chapters needs two values this repository
doesn't ship.

```sh
cp .env.example .env      # then fill in the two values
```

author.today encrypts chapter bodies, and the decryption key comes from two constants its own Android
client is built with:

| Variable | What it is |
| --- | --- |
| `AT_CERTIFICATE` | The client certificate string. Sent as `X-AT-Certificate` (SHA-1, uppercase hex), and used unhashed in the key derivation. |
| `AT_CHAPTER_SALT` | A fixed 16-character salt, the third field of that derivation. |

Where to get them:

1. From author.today's Android APK, where they originate. Unpack it and read the two strings out of
   the client.
2. From [Elib2Ebook](https://github.com/OnlyFart/Elib2Ebook) (GPL-3.0), which extracted them already.
   Its author.today chapter decoding holds the certificate constant and the salt.

See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for licence details.

`.env` is gitignored. `Scripts/gen-secrets.sh` reads it during the build and writes a gitignored Swift
file. Without it the app still builds and runs, and says plainly that it can't open chapters.

## Documentation

`Documentation/` holds what was learned building this: the API reference, the chapter-encryption
scheme, the architecture, the testing setup, and the development history with its dead ends. Start at
[Documentation/README.md](Documentation/README.md). Working rules for changing this codebase are in
[CLAUDE.md](CLAUDE.md).

## Layout

```
ATReader/
├── Code/                     # the app (SwiftUI, iOS 27)
│   ├── App/                  # entry point, root screen, routing
│   ├── Components/           # shared row/cover views
│   ├── Screens/              # one folder per screen: <Name>.Model.swift + <Name>.Component.swift
│   ├── Services/             # session, keychain, cache, background refresh
│   └── Resources/            # Localizable.xcstrings (en source, ru translation)
├── Frameworks/
│   └── AuthorToday/          # the API client, as a standalone SwiftPM package
├── Tests/ATReaderUITests/    # XCUITest suites
├── Scripts/                  # format / lint / check wrappers
└── project.yml               # XcodeGen. The project file is generated, never edited by hand
```

Regenerate the Xcode project after changing `project.yml` or adding files:

```sh
xcodegen generate
```

## Building and testing

```sh
xcodegen generate
xcodebuild -project ATReader.xcodeproj -scheme ATReader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' build

# package unit tests
cd Frameworks/AuthorToday && swift test

# UI tests (the catalogue suite runs against the live service with a guest token)
xcodebuild -project ATReader.xcodeproj -scheme ATReader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:ATReaderUITests/CatalogUITests test
```

The signed-in suites read credentials from the environment so none are committed:
`AT_TEST_LOGIN`, `AT_TEST_PASSWORD`, `AT_TEST_CODE` (two-factor), `AT_TEST_TOKEN`.

Style is enforced by `Scripts/check.sh` (`--fix` to apply).

## Signing

Signing is manual everywhere; nothing is automatic. Simulator builds need no setup, because Xcode signs
those ad-hoc regardless of the configured identity.

To build for a device, fill in your own team and profile:

```sh
cp Local.xcconfig.example Local.xcconfig
# then set DEVELOPMENT_TEAM and AT_PROVISIONING_PROFILE_DEV
```

`ATReader.xcconfig` is committed and defaults both to empty, so a fresh clone builds for the Simulator
with no local setup. It optionally includes `Local.xcconfig`, which is gitignored and carries the real
values. Neither the team ID nor the profile name is committed.

| Configuration | Identity | Profile |
| --- | --- | --- |
| Debug | `Apple Development` (`iPhone Developer` on device) | `$(AT_PROVISIONING_PROFILE_DEV)` |
| Release | none | none |

Only a development profile exists so far. Release deliberately carries neither identity nor profile, so
it fails loudly rather than quietly signing a distribution build with a development one. Add a second
variable to `Local.xcconfig` and wire it into `project.yml` when a distribution profile exists.

## The AuthorToday package

The API has no published specification, but the service ships an OpenAPI document at
`https://api.author.today/swagger/docs/v1`, with a human-readable index at
`https://api.author.today/help`. That document is the source of truth for the request and response
shapes modelled here.

Only `X-AT-Certificate` is load-bearing: the server binds each chapter's encryption key to the
certificate the request claims, so without it a chapter arrives intact but undecryptable. The
`User-Agent` names this app and the service ignores it.

| Header | Value | Required? |
| --- | --- | --- |
| `Authorization` | `Bearer <token>`, or `Bearer guest` when signed out | yes |
| `X-AT-Certificate` | uppercase hex SHA-1 of the app certificate | yes, to read chapters |
| `User-Agent` | `ATReader/<version> (build <n>; iOS <n>)` | no |

Endpoints in use: `account/login-by-password`, `account/current-user`, `account/refresh-token`,
`account/user-library`, `account/update-library-state`, `catalog/search`, `work/genres`,
`work/{id}/details`, `work/{id}/content`, `work/{workId}/chapter/{chapterId}/text`,
`reader/start/{workId}/{chapterId}` and `reader/update-progress`.

### Signing in

`login-by-password` answers with a token. When the account has a second factor it answers instead with
no token and a `twoFactorType` of `Email` or `Code`; repeat the call with `code` set to what the reader
received. A successful sign-in may also return a `trustedCode`, and storing it lets the same device
skip the challenge next time. Tokens are short-lived and kept in the keychain, never in user defaults.

### Chapter bodies

Chapter text arrives encrypted. Each response carries `text` (base64) and a per-chapter `key`, and the
decryption key is derived from both of those plus the reader's account id. A chapter fetched as a guest
and the same chapter fetched while signed in therefore don't share a key:

```
secret  = reverse(key) + ":" + (userId ?? "Guest") + ":" + <fixed salt> + ":" + <certificate>
aesKey  = first 16 bytes of uppercase-hex MD5(secret)
plain   = AES-128-CBC-decrypt(base64Decode(text), key: aesKey, iv: aesKey)   // PKCS#7
```

`ChapterDecryptor` implements this and `ChapterHTML` flattens the resulting markup into paragraphs.
The unit tests round-trip generated text through the real derivation, so they cover the algorithm
without storing anything belonging to the service.

## Offline and background refresh

Books on the Reading shelf are cached under Application Support, excluded from backup: tables of
contents, and chapter bodies as they're read or prefetched. The reader shows the stored copy
immediately and replaces it once the network answers, so a cached book stays readable offline.

Once a day a `BGAppRefresh` task walks the Reading shelf, diffs each table of contents against the
previous sweep, downloads the bodies of newly published chapters (capped per run) and puts the count
on the app icon. The same sweep runs in the foreground when the library opens and a day has passed, so
the badge stays current even if the system never grants a background window. Opening a book clears its
share of the badge.

## Localization

English is the source language; Russian is a full secondary translation. Strings live in String
Catalogs: `Code/Resources/Localizable.xcstrings` for the app, and one inside the package for the
strings it owns. `Scripts/loc-check.sh` reports anything missing or needing review.

## Licence

MIT. See [LICENSE](LICENSE). Copyright © 2026 Alexander Babaev.

Third-party terms, and a note on where the chapter-decryption scheme came from, are recorded in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
