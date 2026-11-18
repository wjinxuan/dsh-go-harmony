# Subscription auth sources

`subscription-auth.mjs` and `subscription-auth-bridge.mjs` are vendored from ccch1mneyyy/dsh-Go at commit a9877420ab9aee121134faf01b6a92a39ce0b05b, `app/assets/engine/auth/{index,bridge}.mjs`, under their original MIT license headers. The sole index change is the relative bridge module filename. Provider grants are persisted independently by `credentials.mjs` as private mode 0600 JSON, preserving the real pi-ai OAuth payload and refresh fields. No credentials are embedded in source or fixtures.
