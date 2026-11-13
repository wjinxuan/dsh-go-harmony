# Account, model selection and turn recovery implementation plan

**Goal:** Continue the approved native dsh-Go v1.0.15 port with usable account information, accurate model selection, and safe recovery from failed remote turns.

**Architecture:** Keep ArkTS/ArkUI, DshClient HTTP/mux, and the current host-owned credentials. Account reads use the existing request seam. Durable turn notices belong to DshTranscript and are rendered alongside messages and tools. Model selection belongs to the active session; an uncreated conversation keeps a pending selection until creation.

**Tech Stack:** HarmonyOS API 26, ArkTS/ArkUI, pinned DSH 0.2.2-rc.1. No added dependency or runtime change.

## Preflight and scope

The active exact-source knowledge record `dsh-go-harmony-46e65bbb-46e6-29` was selected over archived duplicates and all six pages were read. Generated architecture fields are incomplete; source and parity records remain authoritative. Existing user authorization covers continued native replication and interaction improvements. The user requested building first, with phone installation later. No Git repository is present.

## Tasks

- [ ] Native account overview: `ui/AccountData.ets`, `ui/AccountPanel.ets`, `ui/SettingsPanel.ets`. Preserve decimal strings and independently represent state/profile/balance failures; reject late responses after connection changes. No login, logout or token display. Test malformed replies, unavailable endpoints, partial failures, precision and stale reads with `tests/check-account.sh`.
- [ ] Model picker: `ui/ModelPanel.ets` and focused tests. Load session selection before falling back to default, display reasoning selection, separate catalog and write retries, hide empty search groups, expose model settings. Empty-session choice only calls the parent; it never creates a session or changes global defaults.
- [ ] Failure transcript: `dsh/DshWire.ets`, `dsh/DshClient.ets`, wire/live tests. Render allowlisted errors, retry progress and terminal reasons from durable events. Reconcile generic relay errors without exposing host error text. Recovery is available only for the eligible final turn and uses that turn's actual user input.
- [ ] Integration: `pages/Index.ets`, `ui/ChatTimeline.ets`. Render notices and explicit recovery/model/account actions. Preserve unsent text during recovery. Apply pending model before sending the first message and retain failed selection for retry. Recheck connection ownership after asynchronous connection initialization.
- [ ] Run targeted behavior tests, actual local DSH integration with synthetic credentials/model, then signed HAP build and generated ArkUI reactivity checks. Do not infer phone acceptance from host checks.
- [ ] Update parity and build receipt; synchronize project knowledge. Keep the user's live public server and tunnel untouched.

## Acceptance boundaries

No raw host errors, credential values or sign-in URLs enter UI or test output. Account status `credential-stored` means stored authorization, not a guarantee of valid upstream access. Real account queries are reserved for user interaction; development checks use mocks and isolated hosts. Explicit retry never silently repeats tool work, overwrites a newer draft, or applies to another host/session. Shared authorization revocation behavior remains unchanged.
