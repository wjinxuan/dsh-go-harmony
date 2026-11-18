# Native forum audit

Baseline: ccch1mneyyy/dsh-Go `a9877420ab9aee121134faf01b6a92a39ce0b05b`,
`app/lib/forum/`, `app/lib/ui/forum/` and forum authentication links.

The Harmony forum uses native ArkUI topic/category/search/notification/post views,
native Markdown rendering, compose/preview, image upload, replies, likes,
bookmarks, user summaries, paging, topic/post links and per-topic draft recovery.
The only browser handoff is the user's Discourse authorization page. A strict
`ForumCallback` validator admits only the canonical `dshgo://forum/auth?payload=`
RSA payload. Pending authorization survives closing/reopening the app, expires
after 15 minutes and is single-use.

`runtime/forum-service.mjs` runs behind the existing authenticated loopback
TransportControl service. Requests carry the expected forum base to reject stale
mutations after a forum switch. Network requests are bounded, have an absolute
timeout and refuse redirects; authenticated headers are never sent to a second
origin. Forum sessions, private RSA key, client ID and pending nonce are AES-256-GCM
encrypted by `PrivateVault`, using a separate AssetStore master key named `forum`.
The vault is private mode 0600 and written atomically; wrong keys/corruption do not
overwrite existing data. The app never logs or returns the API key to the UI.

Verified on the host:

- `tests/check-forum.sh <unpacked-runtime>`: 5 data/callback cases plus real
  RSA-OAEP encryption/decryption, nonce expiry/replay, cold-start recovery,
  credential expiry, encrypted persistence and stale-base checks.
- The same command runs a real local HTTP Discourse fixture through authenticated
  TransportControl: forms, multipart uploads, API headers, malformed JSON,
  redirects, sanitized errors and revoked keys. No production login or post was
  performed.
- Root's unified ArkTS builds compile the native views and callback integration.

Explicit differences: the adapter requests OAEP-SHA1 and does not provide the
legacy PKCS#1-v1.5 callback fallback. Public forum bases require HTTPS; plain HTTP
is permitted only for loopback test/development. Native Markdown preserves links,
images and basic structured content, but does not reproduce Discourse's complete
browser widget/onebox rendering. Device browser return, picker, AssetStore and
scroll geometry still require the user's subsequent device test.
