# Safe session deletion

Fixed dsh-Go commit `a9877420ab9aee121134faf01b6a92a39ce0b05b`: `runtime/patches/zzzzzz-session-deletion.diff` and `runtime/session-deletion/core.mjs`, licensed under AGPL-3.0 (original LICENSE retained).

All 34 original patch hunks across nine modules are retained. Four shorten only unchanged outer context to coexist with the fixed Recall/input recovery and Harmony patch stack. Every added/removed byte is preserved. Complete input/output SHA256 and unique anchors are verified before any disposable build-tree mutation. Run after the existing Harmony `PATCH` heredoc and after Recall/Signals; existing hardlink publication fallback stays intact.

`core.upstream.mjs` is original source. `core.mjs` only adds the Harmony native exclusive-marker-publication fallback when the OS rejects `link` with EACCES/EPERM. The native function validates the same-directory `.UUID.tmp` → `deleted.json` path under the private sessions lifecycle marker directory and uses RENAME_NOREPLACE. Any other I/O failure still aborts. Tombstone and ancestor-directory sync ordering, no-follow checks, permanent fences, writer locks, active/related session refusal, cache/search/workspace cleanup and retry behavior remain upstream logic. Both original and adapted core hashes are pinned in the manifest.
