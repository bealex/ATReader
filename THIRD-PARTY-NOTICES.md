# Third-party notices

ATReader is MIT licensed. See [LICENSE](LICENSE). This file records everything else the project touches
and how its terms are met.

## Runtime dependencies

None. The app ships no third-party code. Everything it links at runtime is an Apple system framework:
SwiftUI, UIKit, Foundation, CoreText, CryptoKit, CommonCrypto, Security, BackgroundTasks and
UserNotifications, all covered by the Apple SDK agreement, which requires no attribution here.

`Frameworks/AuthorToday` is part of this repository and carries the same MIT licence.

## Build-time dependencies

### swift-syntax, Apache-2.0

Used only by `Scripts/StyleRespace`, the formatting helper that re-inserts interior spaces in
collection literals. SwiftPM fetches it when the formatter is built, and it is not redistributed in
this repository or in the app binary; only `Scripts/StyleRespace/Package.resolved` records the version.

Apache-2.0 obligations (licence copy, notices, statement of changes) attach on distribution of the
licensed work. No swift-syntax source or binary is distributed here, and it isn't modified.
Attribution is given in this file.

- https://github.com/swiftlang/swift-syntax, copyright the Swift project authors, Apache-2.0 with the
  Runtime Library Exception.

### swift-format, SwiftLint, shfmt, shellcheck

Developer tools invoked through `Scripts/`. The developer installs them, they aren't vendored, and
none of their code is distributed with this project.

## Interoperability research

The author.today API has no official specification. The client here was written against the OpenAPI
document the service publishes at `https://api.author.today/swagger/docs/v1`, plus live requests.
Three open-source clients were read while working out the parts that document doesn't cover. No code
was copied from any of them.

| Project | Licence | What was taken |
| --- | --- | --- |
| [Elib2Ebook](https://github.com/OnlyFart/Elib2Ebook) | GPL-3.0 | The chapter key-derivation scheme, and the two client constants it uses |
| [author_today.py](https://github.com/vraestoren/author_today.py) | none stated | Endpoint paths and the mobile request headers |
| [lnreader-plugins](https://github.com/lnreader/lnreader-plugins) | MIT | Confirmation that the *web* API uses a different, unrelated scheme |

### Obtaining the chapter constants

The chapter key derivation needs two constants: the client certificate string and a fixed salt. Neither
is committed here. Both are supplied at build time through a gitignored `.env`; see `.env.example` and
the Configuration section of the README.

Two places to get them:

- **author.today's Android client**, where they originate.
- **`Elib2Ebook`** (GPL-3.0), which extracted them already. Its author.today chapter decoding holds the
  certificate constant and the salt used in the key derivation.

Put them in `.env` as `AT_CERTIFICATE` and `AT_CHAPTER_SALT`.

## Service content

No content belonging to author.today or its authors appears in this repository. Tests build their
fixtures from generated placeholder text. There are no captured API responses, book texts, titles,
covers or author names anywhere in the tree, including in documentation.
