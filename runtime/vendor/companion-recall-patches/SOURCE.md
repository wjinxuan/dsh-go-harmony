# Companion recall engine gates

Source: ccch1mneyyy/dsh-Go commit `a9877420ab9aee121134faf01b6a92a39ce0b05b`, `runtime/patches/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz-companion-recall-gates.diff` (AGPL-3.0; original repository license retained as `LICENSE` in this directory). Original diff retained verbatim and SHA256 recorded in `recall-gates.json`.

This ports all 53 recall upstream hunks plus all ten `dsh-agent-loop` hunks of the required `zzzzzzz-input-recovery.diff` across ten modules onto the exact npm `0.2.2-rc.1` sources from the fixed package lock. Five hunks shorten only unchanged outer context because Harmony does not install the unrelated Android session deletion / phone caller patches. Every upstream added and removed line is preserved byte for byte and in order. No gate, capability check, retirement path, auxiliary rejection, tool provenance, or history quarantine is omitted. Both complete input and output SHA256 are pinned; unknown sources fail before any file is modified. Reapplying the exact output is idempotent.

Run `node runtime/prepare-companion-recall.mjs <runtime-root>` immediately after the locked npm install. The emitted code uses Node standard libraries already available in the embedded runtime; it does not load a native addon.

The required inbox recovery patch supplies the actual durable in-flight input projection used by the original recall clean-session check. Its non-agent-loop API-controller request-deduplication hunk is unrelated to recall admission and is excluded. The original prerequisite diff is retained as `input-recovery.upstream.diff` and its SHA256 is recorded. No empty or fabricated `claimed` getter is used.
