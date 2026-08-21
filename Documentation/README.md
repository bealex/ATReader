# Documentation

What was learned building ATReader. The service has no official specification, so most of this exists
because it was worked out rather than looked up.

| Document | Read it when |
| --- | --- |
| [API.md](API.md) | Touching `Frameworks/AuthorToday`, or adding any endpoint. Where the spec lives, what it gets wrong, headers, auth, search, errors. |
| [ChapterEncryption.md](ChapterEncryption.md) | Chapter text stops decrypting, or you need to know why decrypted chapters can't be shared between accounts. |
| [Architecture.md](Architecture.md) | Adding a screen or a service, or wondering where something belongs. |
| [Reader.md](Reader.md) | Anything about layout, pagination, typography or the page turn. |
| [Testing.md](Testing.md) | Running or writing tests, or a UI test skips when it shouldn't. |
| [History/](History) | You want the reasoning behind the decisions above, including the dead ends. One file per day. |

Start with [API.md](API.md). The rest depends on it.

Everything here except `History/` describes how the app works now, and is rewritten when that changes
rather than added to. A day's findings go in `History/` so this stays short enough to read.

## The four things most likely to trip you up

1. **Chapter text is AES-encrypted and the key includes the signed-in account id.** Guest and
   signed-in responses for the same chapter don't share a key. The certificate and salt the derivation
   needs aren't committed; see the README's Configuration section.
2. **The service's JSON is loosely typed.** `twoFactorType` is a string during a two-factor challenge
   and the number `0` otherwise. Assume any field can be absent, null, or a type you didn't expect.
3. **Free-text search uses `q`, which is missing from the published spec.** With no `q`, the same
   endpoint is the charts API.
4. **CoreText does not hyphenate, and breaks words without drawing a hyphen when asked to.** The
   reader uses TextKit for that reason; see [Reader.md](Reader.md) before changing how text is drawn.

## House rules that outrank convenience

- Nothing from the service (book text, titles, covers, author names, captured responses) is ever
  committed. Tests build fixtures from generated nonsense.
- Credentials reach tests through the environment only.
- English is the source language and Russian is a required second locale. `Scripts/check.sh` fails on
  any untranslated string.

See `CLAUDE.md` at the repository root for the working rules.
