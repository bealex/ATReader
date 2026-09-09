# Litres

A reader who bought their books on [litres.ru](https://www.litres.ru) can bring them onto the device.
The books come across once and nothing watches afterwards, which is the whole difference from
author.today, the service the app lives beside.

`Frameworks/Litres` talks to the service and knows nothing about what a book is. It hands `Code/` an
FB2 archive, and `LitresSync` turns that into a book the same way a file picked by hand becomes one.

## Signing in

There's no token to ask for. A `WKWebView` opens the site's own sign-in page, and
`WKHTTPCookieStoreObserver` watches the jar until the cookies that matter appear:

| Cookie | What it is |
| --- | --- |
| `SID` | the session, sent to the API as the `Session-Id` header |
| `supersid` | sent as the `supersid` header |
| `__Secure-session_context` | a JWT whose payload carries the reader's own id |

The session is held in memory and never written down. Sign in, bring the books across, and it's gone
with the process.

## Two hosts, two ways of proving who you are

`api.litres.ru` answers questions and reads the session from headers. `www.litres.ru` hands out files
and reads no headers at all, only cookies. Both sit behind DDoS-Guard, which reads the user agent and
wants the jar, so every request carries the cookies whether or not the host needs them.

The guard answers a client it doubts with a page rather than an answer, at a status of 200. So a reply
is read rather than trusted: the API's own `Powered-By-Litres` header is what says the service
answered, and a download that opens with `<` is a challenge, not a book.

## Walking the library

`/foundation/api/users/me/arts`, 24 at a time, which is what the site's own build asks for. Every page
after the first is the address the service reported, used as it came: the cursor is base64 and carries
`+` and `=`, so taking the URL apart to rebuild it re-encodes the cursor and the service answers 422.
Only the `/api/` prefix is corrected to `/foundation/api/`, which is the one thing the service gets
wrong about its own address.

Requests are held 400ms apart. A native client asking as fast as it can is what gets a session
challenged, and there's nothing to win by hurrying.

## What comes across

`/foundation/api/arts/<id>/files/grouped` lists what the service will hand over, and `fb2.zip` is the
one format worth having. The file list is also what decides whether a work is readable at all: an
audiobook or a workbook offers no FB2 and is reported as such. The library's own `art_type` is
recorded but doesn't decide anything, because nobody has established what its numbers mean.

Decoding is lenient. A `Lenient<Value>` wrapper drops a field it can't read instead of throwing, since
one odd entry in one file listing shouldn't cost the whole book. `LitresError.malformed` carries what
went wrong, so a failure names itself.

## What the device remembers

A book arrives with its provenance: `source`, `source_id`, `source_updated_at`, `content_hash` and
`archive_hash`. Three of those do work:

- `source` and `source_id` say a work is already here, and `source_updated_at` says whether it's
  behind what the service now holds.
- `content_hash` catches the same book carried in by hand under another name, whatever file it arrived
  in. The text is what settles it.
- The fingerprint is `litres:art:<id>` rather than a title and an author, since every edition of one
  book shares those.

A book bought and brought across is one the reader has already been through, so it arrives read. Only
on the way in: a book fetched again because the service edited it keeps whatever the reader has since
done with it.

## Reporting

A run counts what it added, updated, already had, couldn't read and failed, and keeps every failure
with its reason rather than only a number. `LitresSync.writeReport()` writes the lot to a file for
sharing off the device, which is how a run of several hundred books is diagnosed at all.
