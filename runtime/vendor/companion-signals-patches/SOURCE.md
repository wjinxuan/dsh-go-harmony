# Companion execution signals

Source: dsh-Go v1.0.15, commit `a9877420ab9aee121134faf01b6a92a39ce0b05b`, `runtime/patches/*companion-signals.diff`. Original patch and AGPL-3.0 license are included alongside this record.

All 12 original hunks in three modules are preserved. One hunk shortens unchanged context around the unrelated Android phone-caller patch; every added and removed line is retained. The manifest pins the original patch, exact input (after recall gates) and complete output SHA256. Unknown sources abort before any build-tree write. The patch wraps the pinned bash executor, captures execution provenance, strips forged metadata, and publishes only after the matching result is committed. No model-facing metadata can forge a producer.

Apply `prepare-companion-signals.mjs` after `prepare-companion-recall.mjs`. Runtime availability still depends on an actual usable bash producer; restricted Harmony hosts may report `producer-unavailable`.
