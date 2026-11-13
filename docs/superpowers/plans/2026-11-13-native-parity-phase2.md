# Native parity, phase 2

Baseline: dsh-Go v1.0.15, a9877420ab9aee121134faf01b6a92a39ce0b05b. The user has approved the original UI/behavior and requires ArkTS/ArkUI. No Flutter or WebView replacement.

## Scope and dependencies

- Reuse DshClient, DshWire, existing theme/icons, runtime and signed application identity. Never uninstall to test; preserve sessions and workspaces.
- Protocol agent: queue actions, question lifecycle, permission and agent presets, durable detail projections/trace, goals and capability-gated permanent deletion. Verify against the pinned client and packed runtime.
- Session agent: search, archived sessions, bulk selection and directory picker. Unknown permanent-deletion results must never auto-retry. Local host search capability controls full-text availability.
- Platform agent: original onboarding and native encrypted Asset Store adapter with explicit consent; detail tabs and goal/progress/context. No key in preferences, logs or screenshots.
- Root: integrate question/queue cards, preset selection, detail and onboarding in Index. Maintain generation guards and immutable ArkUI updates. Saved credentials are optional and may be removed without destroying history.

## Execution

1. Read the original pages, protocol and existing callers; document real platform limits.
2. Implement independent modules and tests, then wire all callbacks into the existing root.
3. Run affected parser/state/security tests and client tests against the packed DSH; build the signed HAP using DevEco's installed SDK.
4. Inspect build outputs and install with `hdc install -r`; validate navigation and state on the connected phone. The user supplies any live key directly on the phone.
5. Update parity evidence and the project knowledge record with measured results and remaining differences. Do not claim complete parity from a successful build or a subset of routes.
6. While waiting for unlocked-device validation, implement the original session export page as an independent follow-on: authenticated ZIP download (including descendants), native Save picker and ShareKit panel, cancellation, cache cleanup and binary validation. Test exact runtime ZIP export; do not send any file to an external recipient during testing. Do not enable attachments until Harmony hardlink publication, constrained attachment reads and the missing image codec are properly adapted.

## Risks to check

Stale async results crossing sessions/hosts; queue removal before failed resend; question drafts and timed requests; deleted current session; goal revision conflicts; secret storage lock/errors; first-run migration without resetting existing appearance or data; unsupported bridge capabilities. Existing native runtime archive stays unchanged unless a separately verified runtime fix is required.
