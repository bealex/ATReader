# How chapter text is protected

Chapter bodies are the one part of the API that isn't plain JSON. This is what the scheme does, and how
it was worked out. The reasoning matters: if the service changes the scheme, the same method will find
the new one.

The vendor documents the existence of the encryption but not the mechanism. The `/help` page for
`GET /v1/work/{workId}/chapter/{chapterId}/text` says it returns the chapter text "in encrypted form"
and labels the two relevant fields, `Text` as the encrypted body and `Key` as the key. That's all. The
Swagger document carries no descriptions at all, and neither source mentions AES, CBC, MD5, a salt or a
certificate anywhere. Everything below the field names had to be established elsewhere.

## The scheme

`GET /v1/work/{workId}/chapter/{chapterId}/text` returns:

```json
{ "id": 0, "title": "…", "text": "<base64>", "key": "<32 hex chars>",
  "publishTime": "…", "lastModificationTime": "…" }
```

Decryption:

```
secret  = reverse(key) + ":" + (userId ?? "Guest") + ":" + SALT + ":" + CERTIFICATE
aesKey  = first 16 bytes of the uppercase-hex MD5 of secret
plain   = AES-128-CBC-decrypt(base64Decode(text), key: aesKey, iv: aesKey)   // PKCS#7 padding
```

- `key` is the per-chapter value from the response, reversed as a string rather than as bytes.
- `userId` is the signed-in account's numeric id rendered as a decimal string, or the literal `"Guest"`
  when not signed in.
- `SALT` is a fixed 16-character constant, and `CERTIFICATE` is the same base64 certificate string sent
  (hashed) in `X-AT-Certificate`. Neither is committed. Both are supplied through
  `AuthorTodayClient.Configuration` from a gitignored `.env`; see the README's Configuration section.
- The MD5 is hex-encoded first, and the first 16 ASCII characters of that hex string are the AES key.
  It isn't the raw 16-byte digest.
- The key doubles as the IV.

The plaintext is UTF-8 HTML using a small tag set: `<p>`, `<br>`, `<span>`, `<em>`, `<strong>`, and
occasionally `<img>`. `ChapterHTML` flattens it into paragraphs.

## The certificate is also a request header

The `CERTIFICATE` in the derivation is the same string the client hashes into `X-AT-Certificate`, and
that header isn't optional for reading: the server binds each chapter's key to whichever certificate
the request claims. Drop the header and the response still arrives, same size and status 200, but the
configured constant won't open it. Tested directly; see [API.md](API.md#transport).

## The consequence that matters

The account id is part of the key. The same chapter fetched as a guest and fetched while signed in
returns different `key` values and derives different AES keys. You can't cache a decrypted chapter
across accounts, and you can't decrypt a signed-in response with `"Guest"`.
`ChapterDecryptorTests.rejectsAKeyBoundToAnotherAccount` asserts this, and it was confirmed against the
live service.

In practice `AuthorTodayClient.chapterText(workId:chapterId:)` reads the account id from its own
credentials, so callers never deal with it. But if you ever cache the *encrypted* payload, cache the
account id with it.

## How this was worked out

Every early hypothesis was wrong, which is the useful part.

**1. The obvious guess: repeating XOR.** Every open-source author.today client that decodes chapter
text uses the same trick, reversing the key, appending a separator and XORing the character codes.
Trying that on the mobile response produced garbage.

**2. Ruling it out properly.** Rather than guessing more variants, the ciphertext was tested for the
structural signature of a repeating-key XOR: the average index of coincidence across columns, for every
candidate period from 1 to 80. Natural language XOR'd with a repeating key shows a clear IoC spike at
the true period. This showed a flat ~0.0039, which is 1/256, uniformly random, at every period. That
rules out repeating XOR entirely and points at a real cipher.

**3. Ruling out compression.** The decoded payload was ~34,100 bytes for a chapter the API reported as
~15,800 characters. Russian in UTF-8 costs about two bytes per character, so ~31,600 bytes of text plus
markup lands almost exactly on the observed size. The data therefore wasn't compressed, and the length
was an exact multiple of 16, which says block cipher with padding rather than a stream cipher.

**4. Finding the derivation.** With "AES, 16-byte blocks" established, the remaining unknown was key
derivation, which no amount of analysis recovers. A targeted code search across public clients turned
up `Elib2Ebook`, whose C# `AuthorTodayChapter.Decode` implements the scheme above. Verified against the
live service on the first try.

**5. The trap.** The most-starred reference implementations target the *web* API
(`author.today/reader/…`), which uses a genuinely different and much weaker scheme: a character-level
XOR with the key from a `reader-secret` header. Copying it for the mobile API sends you back to step 1.
If a client claims to decrypt author.today and never mentions AES, it's describing the web endpoint.

## If it breaks

The likely failure is the service rotating the salt or the certificate, or folding another field into
the secret. Symptoms: `AuthorTodayError.decryption`, because base64 decoding fails, PKCS#7 unpadding
produces nonsense, or the result isn't valid UTF-8.

Diagnosis order:

1. Confirm the response still has both `text` and `key`, and that `key` is still 32 hex characters.
2. Check the decoded byte length is a multiple of 16. If it isn't, the cipher changed, not just the key.
3. Run the IoC sweep again. Flat means a real cipher is still in play; a spike means they moved to
   something simpler.
4. Compare the current Android client's constants against the values in your `.env`.

`ChapterDecryptorTests` encrypts generated text through the same derivation and decrypts it back, which
proves the implementation is self-consistent. It can't tell you the service changed. Only a live fetch
does that.
