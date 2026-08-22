# The author.today API

There's no official, published specification. What exists, and what this client is modelled on:

- `https://api.author.today/swagger/docs/v1`, a Swagger 2.0 document the service serves publicly.
  86 paths, 79 definitions. This is the authoritative source for request and response shapes.
- `https://api.author.today/help`, a human-readable index of the same thing.

Both were confirmed live while building this. The Swagger document is mostly accurate but incomplete:
one important query parameter is missing from it (see [Search](#search)), and one field's declared type
is wrong in practice (see [Sign-in](#sign-in)). Treat it as a strong hint rather than a contract.

## Transport

Base URL `https://api.author.today`. All JSON, all HTTPS.

Headers this client sends:

| Header | Value | Required? |
| --- | --- | --- |
| `Authorization` | `Bearer <token>`, or `Bearer guest` when signed out | yes |
| `X-AT-Certificate` | uppercase-hex SHA-1 of the client certificate string | yes, to read chapters |
| `User-Agent` | `ATReader/<version> (build <n>; iOS <n>)` | no |
| `Content-Type` | `application/json` | on POST |

`X-AT-Certificate` is the one that matters, though not as authentication. Requests succeed without it;
the same endpoint returns 200 and a payload of identical size. What the header does is tell the server
which certificate to bind the chapter key to, and that certificate is also the last field of the
key-derivation secret. Send no certificate and you get a valid chapter you can't decrypt. This was
tested directly: certificate present decrypts, absent fails.

It amounts to soft client attestation. A client that doesn't know the certificate gets unreadable
bytes rather than an error.

The Android app also sends `X-AT-Client: android_1.8.013-GMS`, its version string. Every endpoint this
client uses was tested with and without it and behaved identically, so it isn't sent. The API does
version-gate somewhere, since it has `/v1/app/check-version` and a `VersionIsUnsupported` error code,
so if a call ever starts failing on version grounds that header is the first thing to try.

The certificate itself is a base64 string supplied through `AuthorTodayClient.Configuration`, used
twice: hashed into the header, and unhashed inside the key derivation. It isn't committed; see the
README's Configuration section.

`User-Agent` names this app rather than imitating the Android client's `okhttp` string. The service
ignores it: every endpoint used here answers identically with any value, including none, and chapters
still decrypt. It's sent so requests are attributable.

### The guest token

The literal string `guest` works as a bearer token and buys read access to a surprising amount: the
whole catalogue, search, genres, work details, tables of contents, and chapter text for free works.
Only account-scoped endpoints (library, reading progress, likes) demand a real token.

This is what the catalogue UI tests run against, with no account needed.

### Errors

Non-2xx responses carry a consistent envelope:

```json
{ "code": "AuthorizationRequired", "message": "…" }
```

`code` is one of ~28 known values (`InvalidToken`, `ExpiredToken`, `AuthorizationRequired`,
`PurchaseRequired`, `NotFound`, `TooManyRequests`, `CodeNotValid`, …). `message` is Russian prose
written for end users, and the client surfaces it as-is, since it's often more specific than anything
it could synthesise. Unknown codes decode to `.unknown` rather than throwing.

## Sign-in

`POST /v1/account/login-by-password`

```json
{ "login": "…", "password": "…", "code": "…", "trustedCode": "…" }
```

`code` and `trustedCode` are optional. The response is the same shape in every case:

```json
{ "twoFactorType": "Email", "trustedCode": null, "token": null,
  "issued": "…", "expires": "…", "twoFactorEnabled": true }
```

The flow:

1. Call with login + password. If the account has a second factor, `token` is `null` and
   `twoFactorType` is `"Email"` or `"Code"`. The service emails a code at this moment.
2. Call again with the same credentials plus `code`. On success `token` is populated.
3. The response may also carry a `trustedCode`. Store it and pass it on future sign-ins to skip the
   challenge.

Each call without a code sends a new email code and invalidates the previous one. A stale code returns
`CodeNotValid`. That makes the challenge awkward to automate, so plan for a human in the loop.

> `twoFactorType` is not always a string. While a challenge is pending it's `"Email"` or `"Code"`. Once
> the account no longer needs one, the same field comes back as the number `0`, alongside a valid
> token. A strict `String` decode throws and takes the whole response down with it, token included.
> `LoginResult` decodes this field leniently for exactly that reason.

Tokens last 24 hours (`issued`/`expires`). `POST /v1/account/refresh-token` exchanges the current token
for a fresh one, and answers with a new `expires`. Tokens belong in the keychain, never in user
defaults.

`AuthorTodayClient` renews a token within twelve hours of its expiry, and retries once behind a refresh
when a request comes back rejected. Concurrent failures collapse into one refresh, and the calls that
mint tokens are excluded so a failure there cannot recurse.

Related: `GET /v1/account/current-user` returns the profile, including the numeric `id` that the
chapter key derivation needs.

## Library

`GET /v1/account/user-library?page=&pageSize=` returns

```json
{ "worksInLibrary": [ … ], "readingCount": 0, "savedCount": 0,
  "finishedCount": 0, "purchasedCount": 0, "totalCount": 0 }
```

Each entry is a `WorkMetaInfo`: identity, cover, author, series, counts, and the reader's own state
via `inLibraryState` (`None`/`Reading`/`Saved`/`Finished`/`Disliked`), `lastChapterId`,
`lastChapterProgress`, `textLengthLastRead` and `lastReadTime`.

Reading progress is best derived from `textLengthLastRead / textLength`, a character offset, falling
back to `lastChapterProgress` when the offset is missing.

The endpoint pages and gives no total page count, so a client that wants the whole library asks until a
page comes back short; `fullUserLibrary` does that, bounded so a bad answer can't loop forever.

`POST /v1/account/update-library-state` with `{ "workIds": [ … ], "state": "Reading" }` moves books
between shelves; state `None` removes them. The field is `workIds`: send `ids` and the service answers
500 `InternalServerError`, because its own field is left null. States are `None`, `Reading`, `Saved`,
`Finished` and `Disliked`, and `/v1/account/batch-update-library-state` takes a state per work.

## Search

`GET /v1/catalog/search`

The free-text parameter is `q`, and it's absent from the Swagger document. It was found by trying it,
and it matches titles and author names together, so one query serves both kinds of search. There's no
separate by-author endpoint, so narrow client-side if you want to distinguish them.

Useful parameters, all optional:

| Parameter | Meaning |
| --- | --- |
| `q` | free text (undocumented) |
| `page`, `ps` | page number, page size |
| `sorting` | `popular`, `trending`, `recent`, `likes`, `views`, `comments`, `length` |
| `rp` | rating window: `today`, `yesterday`, `week`, `month`, `year` |
| `genreId` | a single genre |
| `state` | `any`, `in-progress`, `finished` |
| `access` | `any`, `paid`, `free` |
| `form`, `format`, `length`, `tag`, `promo`, … | further filters |

The reference lists are themselves endpoints (`/v1/catalog/sort-orders`, `/v1/catalog/rating-periods`,
`/v1/catalog/work-states`, `/v1/catalog/accesses`), each returning `{ value, title, mobileTitle }`.
The client hardcodes the small stable ones and reads genres live.

With no `q`, the same endpoint is a chart. Vary `sorting` and `rp` and you have the "top" lists; there
is no separate charts API.

The response is a `CatalogViewModel`: `searchResults` (richer than library entries, with annotation,
tags and view counts), `realTotalCount`, `isLastPage`.

`GET /v1/work/genres` returns ~70 genres, ~21 of them top-level (`parentId == null`), each with a
`workCount` useful for ordering a filter list.

## Works and chapters

| Endpoint | Returns |
| --- | --- |
| `GET /v1/work/{id}/details` | work plus annotation, tags, series info |
| `GET /v1/work/{id}/content` | array of `ChapterInfo`, the table of contents |
| `GET /v1/work/{workId}/chapter/{chapterId}/text` | one chapter, encrypted |
| `GET /v1/work/{workId}/chapter/many-texts` | up to 100 chapters at once |

The table of contents lists chapters the reader can't open as well as ones they can, so filter on
`isAvailable != false && isDraft != true`. Show locked chapters greyed out rather than hidden, since
that's what the site does.

Chapter bodies arrive encrypted. See [ChapterEncryption.md](ChapterEncryption.md), the least obvious
part of this API and the part most likely to break.

## Reading position

- `GET /v1/reader/start/{workId}/{chapterId}` opens a reading session and returns where the reader left
  off, plus a `sessionId`.
- `POST /v1/reader/update-progress` with `{ workId, chapterId, workProgress, chapterProgress, sessionId }`
  is meant to push the position back. Both progress values are fractions in `0…1`.
- `GET /v1/account/reading-progress?lastSyncTime=` returns positions changed since a timestamp.

Report progress in coarse steps (this client uses 5%) rather than on every scroll event.

> **The service keeps positions. It just won't take ours.**
>
> `GET /v1/account/reading-progress?lastSyncTime=` returns real positions: 20 entries for a live
> account, with chapter ids and timestamps months apart, written by the website's own reader. This app
> adopts them, which is how a book read on the site opens here where it was left.
>
> `POST /v1/reader/update-progress` still records nothing. Tested with every variable eliminated: a
> value the service had not seen (1.0 → 2.0), in its own percent units, carrying a `sessionId` from a
> live `reader/start`, spaced out so the rate limit could not interfere. The call succeeds and the
> position stays where it was. Earlier rounds covered a work with an existing position and one without,
> with and without a session, and with the full Android impersonation restored.
>
> **`reading-progress` allows one call a second per IP** and says so: `Too many requests! Rate limimt
> by your ip to this endpoint allow only 1 per Second` (its spelling). Two calls close together read as
> a timeout rather than an error, which is worth knowing before reading it as a hang.
>
> **Progress is a percentage, not a fraction.** The read side returns values like `93.022125` and
> `96.119712`, so `0…100` is the unit for both `chapterProgress` and `workProgress`. This client used
> to clamp its writes to `0…1`, which said "half a percent in" whatever the reader had done. Fixing
> the clamp did not make the writes stick, but it is the unit the service itself speaks.
>
> The two `sync-reading-stats` endpoints are not an alternative: both return a server-side
> `NullReferenceException` from the same `ReverseString` helper the chapter key derivation uses, so
> they expect a derived field that isn't in the Swagger document.
>
> So the position this device makes stays local, and the position the service holds is read and
> adopted. Reading here does not show up there.

## Endpoints this client doesn't use

The API also covers audiobooks (`/v1/audiobook/*`), notifications, push registration for both Firebase
and Huawei, complaints, hidden authors and series, and social actions like votes and subscriptions. The
`/v1/home/home-page` endpoint returns a merchandised front page. None of it is needed for reading, but
it's there if the app grows.

## Other clients to read

All three were consulted while working out the parts the spec doesn't cover:

- [Elib2Ebook](https://github.com/OnlyFart/Elib2Ebook) (C#), the only public implementation found that
  gets the mobile chapter decryption right.
- [author_today.py](https://github.com/vraestoren/author_today.py) (Python), a clean map of the
  endpoints and headers. It doesn't decrypt chapters.
- [lnreader-plugins](https://github.com/lnreader/lnreader-plugins) (TypeScript), which targets the
  *web* API, whose chapter obfuscation is a different and simpler scheme. Don't copy it for the mobile
  API.
