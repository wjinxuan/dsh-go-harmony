# Explicit schedule authorization

Source: `ccch1mneyyy/dsh-Go`, fixed commit `a9877420ab9aee121134faf01b6a92a39ce0b05b`, `runtime/patches/zzzzzzzz-schedule-authorization.diff` (AGPL-3.0; original LICENSE retained).

The upstream patch is copied byte for byte. All seven hunks across `@deepseek-ai/dsh-schedule` and `@deepseek-ai/dsh-tool-schedule` are applied unchanged. The input hashes are for the pinned DSH 0.2.2-rc.1 runtime after Harmony compatibility, Recall/Signals and safe session deletion. Apply this preparation after `prepare-session-deletion.mjs`.

The complete manifest and original diff have pinned SHA256. Every regular source file, unique hunk and whole-file input/output checksum is checked before any build-tree write. Reapplication is idempotent; mismatched modules fail before any mutation.

The exact upstream gate asks a blocking `userQuestions` request with purpose `schedule-authorization`, full detached task details, a 120-second abort deadline and one exact Authorize answer. Rejection, custom answers, cancellation, unavailable answerers, delegated agents, service stop and elapsed scheduled times fail closed. Updates are reauthorized and rechecked against the complete prior record before commit. Human Remote forms retain their original separate authorization boundary. Generic approval and allow-all modes do not bypass the model's question gate.
