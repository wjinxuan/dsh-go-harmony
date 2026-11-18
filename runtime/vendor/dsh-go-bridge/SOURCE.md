# Source

Upstream sources from ccch1mneyyy/dsh-Go commit a9877420ab9aee121134faf01b6a92a39ce0b05b (v1.0.15), runtime/bridge/dsh-go-bridge. Package metadata declares MIT.

## Harmony recall-marker publication

`lib/companion/recall-markers.js` retains the fixed upstream marker schema, immutable publication, directory fsync, cleanup and fail-closed admission. Its upstream SHA-256 is `49ec14cb6ccb1cbe43f0cd9912e6e79a5804aaf3ac7141601d7c2ae38acfe41e`. On an actual `link` failure with `EACCES` or `EPERM` only, it uses the optional native `dshHarmonyPublishRecallMarker` hook. The hook must be confined to the application data directory’s `companion/recall-sessions` and use atomic no-replace publication for `.recall-UUID.tmp` to a SHA-256 marker name or `.probe-UUID.tmp`. Missing or failed native support still reports `tag-unavailable`; other filesystem errors are not bypassed. No marker path is taken from an HTTP request.

`tests/companion-recall-markers.test.mjs` covers permission-denied probe and durable publication, a concurrent existing target, other errors, absent/rejecting native support, retry, fsync failure and the unchanged hard-link path. Its native hook is a host substitute; the production C++ path/FD boundary and physical-device bind/injection/revoke require their separate evidence.
