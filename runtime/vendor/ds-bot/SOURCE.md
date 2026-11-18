# Fixed upstream DS Bot composition

The dsh-Go v1.0.15 baseline `a9877420ab9aee121134faf01b6a92a39ce0b05b`
locks both sources in `packages/dsh_client/test/fixtures/dsbot_v023_mobile.json`:

- Official **0.2.3** base: `Fei2411/DS-Bot@4a7b55069ad300eae8be42a74f31bc170b40ead7`.
- Mobile API changes: `6f3e1b3e8603abd84820b334a7f99985236dbbdf`.

This directory uses the complete official 0.2.3 host/shared/published package as
its base. It adds the mobile/remote modules and the exact mobile hooks in index,
channel, groups, tools, memory, feed, approvals and usage. It retains the base's
durable memory, request/handoff behavior, browser/avatar support and awaited part
migration. `MOBILE_OVERLAY_AUDIT.json` records per-file source/composition hashes.
It does not relabel the older standalone mobile branch (whose package says 0.2.1)
as a new release. License is Apache-2.0; LICENSE is included.

## Harmony schedule compatibility

Both fixed upstream sources expect the old per-Session schedule API. DSH
0.2.2-rc.1 uses a host-wide catalog and target-based tasks. The independent
`src/host/harmony-schedules.js` adapter is mounted from `schedules.js`:

- Catalog maps only explicit `target.kind === 'session'` entries; list filters
  exact target Session IDs. Historical `involvedSessionIds` never grants ownership.
- Human Web create supplies a typed timing selector and explicit Session target.
- Delete rereads the exact task/target, checks the caller's team owner and passes
  `expectedUpdatedAt` to public `edit(action:'delete')`. Error-code results fail.
- Automatic part migration changes only the existing task's target through public
  `edit`, preserving its ID, paused state, timing and delivery history. It passes
  the real originating Session as actor and therefore uses the original schedule
  authorization gate. Active/paused tasks move; ended/inactive history stays on
  its original part. Execution/concurrent edits fail safely; a final catalog check
  prevents old-part archival while another task was added during confirmation.
- The official 0.2.3 part code awaits migration; failure retains the restart marker
  and does not archive/stop the old part. On the host-wide API, the two completed-
  migration archive sites use normal activity admission, never `stopActivity`:
  a task created after the last catalog read cannot be silently deleted. Archive
  failure propagates and retains the same restart marker. Legacy service behavior
  is unchanged. No direct storage edits or gate bypasses.

The previous compatibility guard disabling schedules was an implementation gap,
not a Harmony platform restriction, and has been removed. Native mobile DS Bot
has no schedule settings page in the fixed original; the existing Web/API route
is retained rather than adding an unrequested native page.

Harmony activates this optional host plugin only after explicit user choice and
engine restart, with `updateCheck:false`, the fixed scoped workspace and existing
no-child-process policy. General npm/install-script limitations are separate from
these implemented schedule capabilities.
