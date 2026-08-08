# Pitfalls Research

**Domain:** Offline-first mobile sync (Flutter/SQLite) + hybrid native geofencing + area-based content download
**Researched:** 2026-08-08
**Confidence:** MEDIUM-HIGH (codebase risks verified directly by prior audit in PROJECT.md; ecosystem patterns verified via multiple official/community sources; some 2026-specific package claims are LOW confidence and flagged)

## Critical Pitfalls

### Pitfall 1: Silent DB delete-and-recreate on open failure (already in this codebase)

**What goes wrong:**
`AppDatabase` (lib/data/datasources/local/app_database.dart, ~lines 38-53) catches an `openDatabase` failure and responds by deleting the database file and recreating it empty — no backup, no user confirmation, no logging surfaced to the user. Any transient failure (disk full during write, OS killing the process mid-open, a bad migration, file lock contention) permanently destroys every geo_path, geo_trigger, audio_asset and region on the phone with zero recovery path.

**Why it happens:**
"Recreate DB on open failure" is a common quick fix during early development to unblock testing (never has to think about migrations) and nobody circles back to it once real user data exists. The failure path is rarely exercised in normal testing, so it ships silently.

**How to avoid:**
- Never delete on failure. On `openDatabase` error: copy the existing file to a timestamped backup path first (e.g. `app_database.db.bak-<timestamp>`), then retry open once, and only if that also fails, surface a blocking error screen to the user with the backup path — never auto-recreate.
- Use SQLite's own recovery primitives before giving up: try `PRAGMA integrity_check`, and if genuinely corrupt, attempt `.recover` style dump-and-reimport rather than a raw delete.
- Any code path that results in a fresh empty DB must be opt-in and explicit (a named, confirmed user action), never a fallback in the open path.

**Warning signs:**
- Any `catch` block around `openDatabase`/`deleteDatabase` in the codebase.
- Absence of a `.bak` or export step before any destructive DB operation.
- Grep for `deleteDatabase(` and confirm every call site is user-initiated, confirmed, and preceded by an automatic export.

**Phase to address:**
Must be fixed **before any sync code ships** — this is a pre-existing live risk, independent of sync. Should be the very first phase of this milestone ("harden local data integrity"), because sync work will increase how often the DB is opened/touched (background sync ticks, pull merges) and thus increases exposure to this bug.

---

### Pitfall 2: Destructive debug UI reachable without confirmation (already in this codebase)

**What goes wrong:**
`recreateForTesting()` and `importDatabase()` are wired to real buttons in `data_browser_page.dart` with no confirmation dialog. A single mis-tap (easy on a small phone screen, or by a non-technical person handed the phone) wipes or overwrites the live database.

**Why it happens:**
Debug tooling built for developer convenience during early solo development gets left in the shipped app because there's currently no separation between debug and end-user UI (also called out in PROJECT.md's `DiagnosticsPanel` risk).

**How to avoid:**
- Gate every destructive action (recreate, import/overwrite, delete-all) behind an explicit typed-confirmation dialog (e.g. type "DELETE" or a two-step confirm), regardless of the debug/user-mode toggle mentioned in the Active requirements.
- Auto-export/backup the current DB immediately before executing any destructive debug action, so even a confirmed mistake is recoverable.
- This is independent of the runtime debug/user toggle — gating must hold even when debug mode is on, since the milestone plan already states this explicitly.

**Warning signs:**
- Any `ElevatedButton`/`onPressed` wired directly to a destructive repository/datasource method with no dialog in between.
- No pre-action backup call before destructive operations.

**Phase to address:**
Same phase as Pitfall 1 — "harden local data integrity," first phase of the milestone, before sync or geofencing work begins.

---

### Pitfall 3: First-sync "adopt vs. overwrite" ambiguity when connecting existing local data to a fresh backend

**What goes wrong:**
The very first time a phone with months of pre-existing local data connects to a backend that has never seen it, sync code commonly assumes one of two wrong defaults: (a) the phone is the "new" client so the server's (empty) state wins and pull overwrites/deletes local data, or (b) push floods the server correctly but a bug in the *first* pull cycle (before local outbox has fully flushed) applies a pull-and-replace that clobbers rows mid-push. Both are silent data loss with no error thrown — everything "looks like it worked."

**Why it happens:**
Sync engines are usually built and tested against a backend that already has authoritative history. The "cold start against empty backend, phone is the true source of history" case is a distinct code path that's easy to skip because it only happens once per install and isn't covered by regression tests written after the fact.

**How to avoid:**
- Push must run to completion (full outbox drained and acked) before the first pull is ever attempted on a given device — enforce this as an explicit one-time "bootstrap" state machine step (`sync_state.bootstrapped = false` until first full push succeeds), not just "push happens before pull most of the time."
- Never let pull perform destructive replacement of a local row that has no corresponding server row yet — pull should only ever update/insert rows that the server actually returned; local-only rows are left untouched by definition (this matches the project's own "server keeps current+1 previous version" model, but the *first* sync is the case most likely to violate it if not explicitly handled).
- Take a full local DB export automatically before the first-ever sync bootstrap runs, independent of the DB-open backup in Pitfall 1 — this is the last safety net if the sync bootstrap logic has a bug.

**Warning signs:**
- No explicit "first sync" / "bootstrap" flag distinct from normal ongoing sync state.
- Pull code path that can delete or overwrite local rows without checking whether local push has ever completed.
- No pre-sync automatic export step.

**Phase to address:**
The sync bidirectional phase (push+pull activation). This should be a named acceptance criterion for that phase: "connecting an existing populated phone to a fresh backend for the first time never loses local data," tested explicitly with a phone DB pre-seeded with data before the backend exists.

---

### Pitfall 4: Schema/migration drift between phone and backend during rollout

**What goes wrong:**
The local SQLite schema (`geo_paths`, `geo_triggers`, `audio_assets`, `regions`, plus the outbox/version columns) evolves over the milestone as sync is built out. If the backend's expected shape and the phone's actual shape diverge mid-rollout (e.g., app update ships before backend, or vice versa), sync either silently drops fields it doesn't recognize, or a push payload the backend can't parse gets acked anyway (because the client only checks HTTP status, not payload-level validation) and the outbox row is cleared — the mutation is now lost from both sides.

**Why it happens:**
Client and backend are developed together by the same person in fast iteration, so mismatches get "fixed by just re-testing" locally instead of being handled as a real versioning problem — but once real devices are in the field (even a single-user v0), an app update and a backend deploy are never perfectly atomic.

**How to avoid:**
- Version the sync payload schema explicitly (a `schema_version` field on outgoing payloads); backend rejects (does not silently accept/ignore-unknown-fields) payloads it can't fully validate, and returns a distinguishable error so the client keeps the outbox entry instead of marking it synced.
- Never clear an outbox row on ambiguous/unknown server response — only clear on an explicit, understood ack for that specific mutation.
- Since this is a single-editor v0 (per Constraints), keep migrations additive-only where possible (new nullable columns, no renames/drops) to reduce the surface area for drift.

**Warning signs:**
- Outbox rows being cleared on any 2xx response without checking response body content.
- No `schema_version` or equivalent field in the sync payload contract.

**Phase to address:**
Sync phase — specifically the push/pull protocol design step, before wiring it to a real backend candidate.

---

### Pitfall 5: Partial sync failure leaves outbox and local state inconsistent (not fully idempotent)

**What goes wrong:**
A push batch partially succeeds (e.g. 3 of 5 outbox rows acked, connection drops before the response for the rest arrives, or the app is backgrounded/killed mid-request on Android). If the client can't tell "sent but response lost" apart from "never sent," retry either double-applies (server sees a duplicate create) or an entry is dropped from the outbox by an overly broad "clear all pending" call after a batch response.

**Why it happens:**
Naive outbox implementations treat "send batch, get response, clear batch" as atomic when it isn't — the network call and the local state update are two separate operations that Android/iOS can interrupt between.

**How to avoid:**
- Server-side idempotency: every outbox mutation carries a stable client-generated UUID (already present per PROJECT.md's `uuid` field) that the server uses as an idempotency key — re-sending the same mutation twice is a no-op on the server, not a duplicate.
- Client clears each outbox row individually only after that row's specific ack is received, never as a batch-wide "mark all sent" after receiving *a* response.
- Sync runs must be resumable: a sync job killed mid-flight (app backgrounded, OS kill) must be safe to simply run again from current outbox state with no manual cleanup step.

**Warning signs:**
- Outbox clearing logic that operates on "all rows in this batch" rather than per-row ack.
- No idempotency key concept on the backend's write endpoint.
- Sync logic that assumes a single request/response round trip always completes fully.

**Phase to address:**
Sync phase — same push implementation as Pitfall 4; write a specific test/checklist item for "kill app mid-sync, relaunch, verify no duplicate and no loss."

---

### Pitfall 6: Treating hybrid geofencing as "just swap the plugin" — background execution and precision get silently degraded

**What goes wrong:**
Native OS geofencing (Android `GeofencingClient`, iOS `CLLocationManager` region monitoring — e.g. via `native_geofence`) is fundamentally different from continuous polling: transitions are debounced (~20-30s) and, per this project's own prior research, background checks may only happen "every couple of minutes," not instantly. If the small-radius geotrigger detection (12m radius, needs near-real-time precision for audio playback) is naively pointed at the same native-geofencing mechanism used for large-radius Region entry, triggers will be missed or fire late/never — this reads as "the audio bug got worse," not as an obviously broken feature, so it's easy to ship without noticing in a quick manual test near WiFi.

**Why it happens:**
"Replace polling with native geofencing" sounds like a straight swap, but native geofencing trades precision/latency for battery life — it was designed for large POI-radius use cases (retail, delivery), not few-meter interactive triggers.

**How to avoid:**
- Keep the two-tier design already decided in PROJECT.md's Key Decisions: native geofencing only for Region-level (large radius) entry/exit; fine-grained polling (existing `BackgroundAdaptivePoller` logic, currently dead code, is a candidate to revive) only runs *inside* an already-active region, over a short list of nearby small-radius triggers.
- Explicitly test the worst case: user walks directly to a trigger from outside the region without lingering (region-entry event may lag 20-30s+ behind actual GPS entry) — precaching audio (per Active requirements) must not assume the region-entry callback fires immediately.
- Verify Android's foreground-service requirements for the fine-grained polling tier: if that inner polling needs to run while the app is backgrounded, it likely still needs a foreground service with a location-type notification (Android 12+ requires justification and a persistent notification for continuous location use) — don't assume "native geofencing for region" removes the need for a foreground service entirely, it only removes it for the outer tier.

**Warning signs:**
- Manual testing done only near the device/emulator location (fast GPS updates, WiFi present) rather than on foot with real movement and normal background app state.
- No test case for "audio trigger fires within N seconds of physical entry to a 12m radius" as an explicit success criterion.
- Foreground-service notification silently missing once GeofencingClient is introduced, causing Android to kill the fine-grained polling silently in background.

**Phase to address:**
The geofencing/background phase. Success criteria for that phase should explicitly include latency measurements for both tiers (region entry via native geofencing, trigger entry via fine polling) under real outdoor walking conditions, not simulator taps.

---

### Pitfall 7: iOS 20-region cap hit silently — sliding window not actually re-evaluated on movement

**What goes wrong:**
iOS hard-caps simultaneous monitored regions at 20 per app. A naive implementation registers geofences once (e.g. at app start or region download time) and never re-evaluates as the user moves, so once more than ~20 candidate regions/triggers exist across the whole dataset, only the first 20 registered are ever monitored — any trigger the user actually walks near, but which wasn't in that first batch, silently never fires, with no error surfaced (iOS just doesn't monitor it; `CLLocationManager` doesn't throw for the caller, it just won't have registered the region if the cap is exceeded, or overwrites earlier registrations).

**Why it happens:**
The 20-region cap is only mentioned in docs footnotes, easy to miss during a plugin swap, and doesn't manifest at all during development (a single developer's test region set is usually well under 20) — it appears once real content accumulates across the whole recorded catalog.

**How to avoid:**
- Confirmed as an explicit constraint already in PROJECT.md: cap usage at ~19 (headroom for one region always being the "Region" itself), not the full 20.
- Re-evaluate the monitored set on significant location change (`startMonitoringSignificantLocationChanges`, per the research already done) — not just once at app launch — recomputing nearest-N via Haversine distance and swapping out regions/triggers that are no longer near.
- Since this project has *two* levels (Region and inner Trigger), the 19-region budget on iOS must be split/shared sensibly: don't let "region download" content growth alone (many regions) starve the trigger-monitoring tier's slice of the same 19-region budget, or vice versa.

**Warning signs:**
- Geofence registration code with no re-registration trigger tied to location change.
- No explicit cap/count check before calling `startMonitoring(for:)` on iOS.
- Testing only with a small number of regions/triggers (fewer than 20) that never actually exercises the cap.

**Phase to address:**
Geofencing/background phase — this is the direct implementation of the Active requirement "el sistema nunca intenta monitorear más de ~19 regiones/triggers simultáneos." Should have an explicit test: seed more than 20 triggers across a wide area, walk/simulate movement, verify swapping happens.

---

### Pitfall 8: Region content download triggers on weak/metered signal, causing failed or costly downloads

**What goes wrong:**
The plan is to download a region's audio content when the user enters that region "con señal suficiente" — but "entering a region" and "having good, unmetered connectivity" are unrelated events. A naive implementation fires the download attempt purely on the geofence region-entry callback, which in Lago Puelo's intermittent-connectivity environment often means: attempting a multi-MB download over a weak/metered cellular connection, burning the user's data plan, and/or leaving a corrupted or half-written audio file if the connection drops mid-transfer.

**Why it happens:**
"Download on region entry" is the simple mental model; connectivity-awareness is a separate concern that's easy to treat as an afterthought, especially since the local dev/test environment usually has strong WiFi.

**How to avoid:**
- Decouple "mark for download" (on region entry) from "actually download" (a background job gated on real network constraints) — use Android `WorkManager` with `NetworkType.UNMETERED` (or `CONNECTED` with an explicit user setting for "allow on cellular") plus retry/backoff, rather than firing an inline HTTP call from the geofence callback.
- Always download to a temp file and atomically rename/move to the final path only after a checksum/size verification succeeds — never leave a partially-written file at the "real" filename, which is exactly the kind of state that causes `setFilePath()` failures later (the project's own suspected root cause of the audio-not-playing bug, per PROJECT.md audit).
- Respect the existing "intermittent connectivity" constraint: downloads must be resumable/retryable, not fire-once-and-give-up; surface a clear pending/failed state so the debug UI (or future user UI) can show "content not yet available offline for this region" rather than failing silently at playback time.

**Warning signs:**
- Direct HTTP download call inside the geofence/region-entry event handler with no queuing/retry layer.
- No temp-file-then-rename pattern in the download code.
- No network-type check before attempting download.

**Phase to address:**
The content-download phase (area-based download requirement). Should include explicit test: trigger region entry with airplane mode / metered-simulated network, verify no download attempt and no crash, and that it retries automatically once connectivity improves.

---

### Pitfall 9: Orphaned audio files accumulate with no cleanup path

**What goes wrong:**
Once downloads exist, `audio_assets.remote_url`/local file path management commonly develops a mismatch over time: a trigger/asset gets edited or deleted server-side and synced (per the "server keeps current+1 previous version" model), but the previously-downloaded local audio file for the old version is never deleted — it just sits on disk. Over months of edits this becomes silent storage bloat with no way for the user to reclaim space, and stale files can even get accidentally referenced again if IDs are ever reused.

**Why it happens:**
Delete/cleanup logic is naturally an afterthought relative to the "happy path" of downloading and playing content; nothing in normal testing surfaces it because test devices get reinstalled/wiped frequently.

**How to avoid:**
- Every local audio file's lifecycle should be tied 1:1 to a DB row (e.g. store the exact local file path in `audio_assets`, never re-derive it by convention alone); when a row's `deleted_at` is set (soft delete, per existing sync model) or its content actually changes to a new asset, immediately schedule the old local file for deletion.
- Add a periodic reconciliation sweep (e.g. on app start, or on each sync cycle) that lists files in the app's audio storage directory and deletes any not referenced by a current, non-deleted `audio_assets` row — this is the safety net for the cases the 1:1 lifecycle tracking misses (crash mid-delete, etc.).
- This directly interacts with Pitfall 1/2 territory: cleanup logic must never be more aggressive than the DB state it's reconciling against — when in doubt (e.g. can't determine current DB state), skip cleanup rather than delete.

**Warning signs:**
- No delete-file call anywhere near the soft-delete (`deleted_at`) write path for audio_assets.
- No sweep/reconciliation job at all.
- Local file paths derived by string convention from remote URL rather than stored explicitly.

**Phase to address:**
Content-download phase, as a follow-on task after basic download works — should not block initial download shipping, but must land before the phase is considered done, given the multi-month recording history already on real devices.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|-----------------|------------------|
| Skip first-sync bootstrap state machine, just "push then pull" | Less code now | Silent data loss the one time it matters most (first connect) | Never — this is the single most consequential edge case for this milestone's core constraint |
| Batch-clear outbox on any successful-looking response | Simpler sync loop | Duplicate/lost mutations on partial failure | Only if backend guarantees true all-or-nothing batch transactions AND client persists which UUIDs were in the batch for verification — otherwise never |
| Fire download inline on region-entry callback | Fast to implement, works in dev on WiFi | Data-cost surprises and corrupted files for real users in low-signal areas | Never for production; acceptable only behind a debug-only "force download" test button |
| Register all geofences once at app start (no re-evaluation) | Works fine under 20 regions in testing | Silent trigger failures once catalog grows past iOS cap | Never once catalog approaches ~15+ entries; acceptable only while catalog is small and known to stay small |
| No reconciliation sweep for orphaned files, rely only on delete-on-edit hooks | Less code | Storage bloat and drift after crashes/edge cases over months | Acceptable temporarily for MVP if a manual "clear unreferenced files" debug button exists as a stopgap, but must be replaced by an automatic sweep before considering the download phase done |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|--------------|------------------|-------------------|
| `native_geofence` (or equivalent) plugin | Assuming it replaces both the region-level *and* fine-grained trigger-level detection | Use it only for the outer Region tier; keep the existing fine-grained polling (reviving `BackgroundAdaptivePoller`) for the inner trigger tier |
| Android `WorkManager` for downloads | Using `NetworkType.CONNECTED` (any network) by default for large audio downloads | Default to `NetworkType.UNMETERED`, offer an explicit opt-in setting for cellular downloads |
| Backend sync endpoint (once chosen) | Treating any 2xx response as "safe to clear outbox row" | Only clear on an explicit per-mutation ack keyed by the client UUID; treat ambiguous/unknown responses as "retry later," not "success" |
| iOS region monitoring | Registering more than ~19-20 regions and letting `CLLocationManager` silently drop/ignore the overflow | Explicitly cap requests client-side before calling the API; never rely on the OS to tell you it refused |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|-----------------|
| Fine-grained polling left running continuously instead of only inside an active region | Battery drain returns despite "switching to native geofencing" | Ensure the inner polling tier starts only on the region-entry callback and stops on region-exit, not on app launch | Immediately noticeable once any region is entered for an extended walk |
| Sync pull naively re-downloads full dataset every cycle instead of delta/since-timestamp | Increasing sync time and data usage as catalog grows | Use `updated_at`/`logical_version` (already in schema) for incremental pull, not full-table pull | Becomes noticeable once catalog exceeds a few dozen entities |
| Orphaned file sweep implemented as a full directory scan + full table scan on every app start | Startup latency grows with accumulated files over time | Run the sweep on a background isolate/lower frequency (e.g. once a day or once per sync cycle), not every cold start | Noticeable once dozens+ of files accumulate over months of edits |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Destructive debug actions (recreate/import DB) reachable in production builds without confirmation | A stray tap (or someone else picking up the phone) destroys all local data | Confirmation dialog + backup-before-destroy, independent of debug/user toggle (already identified as a hard constraint in PROJECT.md) |
| Backend sync endpoint with no auth because "it's just me, v0" | Even a single-user backend exposed to the internet without auth is trivially discoverable/writable by anyone with the URL | Minimal auth (e.g., static API key/bearer token) from day one of the real backend, even for v0 single-user — cheap to add now, expensive to retrofit once a mobile client is already shipped without it |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-------------------|
| No visible indicator that region content hasn't finished downloading | Audio silently fails to play when the user reaches a trigger, indistinguishable from the pre-existing "audio doesn't start" bug | Show explicit "downloading content for this area…" / "ready offline" state per region, especially relevant since fixing perceived audio reliability is a stated goal of this milestone |
| Sync failures shown only in a debug panel most users never see | Real sync problems (e.g., stuck outbox) go unnoticed for a single non-technical editor persona in future | Even in v0, surface a simple non-debug indicator ("last synced: 3 days ago" / "sync error") once the debug/user toggle exists |

## "Looks Done But Isn't" Checklist

- [ ] **DB-open hardening**: Looks done if it "doesn't crash on open" — verify it actually backs up before any destructive fallback, and that the fallback path has been deliberately exercised (simulate a corrupt file) rather than just assumed unreachable.
- [ ] **Bidirectional sync**: Looks done once push+pull both run without errors on a clean test device — verify specifically against a device pre-loaded with real historical local data connecting to a backend for the first time (the actual production scenario, not a fresh-install test).
- [ ] **Hybrid geofencing**: Looks done once a manual walk-test triggers audio near the office/WiFi — verify against the documented ~20-30s region-entry debounce and iOS's "every couple of minutes" background check cadence, on a real device off WiFi, with the app backgrounded.
- [ ] **iOS 20-region cap handling**: Looks done with a small test catalog (<20 items) — verify with a seeded catalog of 25+ regions/triggers and confirm the sliding window actually swaps registrations on movement.
- [ ] **Area-based download**: Looks done when it downloads on a fast WiFi connection during dev — verify under simulated metered/weak connection and confirm no partial/corrupt file is ever left at the path the audio player will read from.
- [ ] **Orphaned file cleanup**: Looks done if newly-downloaded files play correctly — verify that editing/deleting an audio asset server-side and syncing actually frees the old local file, not just that new files download fine.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|----------------|------------------|
| Silent DB delete already happened to a real user before the fix ships | HIGH (data likely unrecoverable without a backup) | Check for any prior manual export via the existing debug export feature; otherwise data is gone — this is exactly why Pitfall 1 must be fixed first, before further real-world use |
| First-sync bootstrap bug wipes/overwrites local data after backend connects | MEDIUM if the pre-sync automatic export (Pitfall 3 prevention) was in place, HIGH if not | Restore from the automatic pre-bootstrap export; if none exists, this is unrecoverable — reinforces making that export mandatory, not optional |
| Outbox stuck with un-acked mutations after a partial sync failure | LOW | Outbox rows are still present locally by design (Pitfall 5 prevention); simply re-run sync, idempotency keys prevent duplication |
| Orphaned files discovered accumulating | LOW | Run the reconciliation sweep (Pitfall 9) once implemented; safe to delete anything unreferenced since it's derived, not primary, data |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|----------------|
| Silent DB delete-and-recreate (P1) | Phase 0 / "harden local data integrity" (first phase, before sync work) | Simulate `openDatabase` failure in a test; confirm backup file created and no data loss, no silent recreate |
| Unconfirmed destructive debug UI (P2) | Same first phase as P1 | Manual test: tap recreate/import buttons, confirm a confirmation dialog blocks execution and a backup exists afterward regardless |
| First-sync adopt/overwrite ambiguity (P3) | Sync bidirectional phase | Seed a test device with local-only data, connect to a fresh backend, verify zero data loss and correct bootstrap ordering |
| Schema/migration drift (P4) | Sync bidirectional phase (protocol design step) | Deploy a client/backend version mismatch deliberately in a test environment; confirm outbox rows are retried, not silently dropped |
| Partial sync failure / non-idempotency (P5) | Sync bidirectional phase | Kill app mid-sync (adb/simulate), relaunch, verify no duplicates and no loss via idempotency key |
| Hybrid geofencing precision loss (P6) | Geofencing/background phase | Real outdoor walk test measuring latency for both region-entry and trigger-entry events, app backgrounded |
| iOS 20-region cap (P7) | Geofencing/background phase | Seed 25+ regions/triggers, simulate movement across them, confirm sliding-window re-registration and no silent misses |
| Download on weak/metered connection (P8) | Content-download phase | Simulate metered/no-signal region entry; confirm no download attempt, no corrupt file, auto-retry on reconnect |
| Orphaned audio files (P9) | Content-download phase (follow-on task) | Edit/delete a synced audio asset, confirm old local file removed via lifecycle hook or sweep |

## Sources

- [Offline First Mobile App in 2026: Real-Time Data Sync with CRDT Architecture](https://www.calibraint.com/blog/offline-first-mobile-app-in-2026) — MEDIUM confidence (marketing-adjacent blog, but claims align with well-known outbox/tombstone patterns)
- [Offline-First Done Right: Sync Patterns for Real-World Mobile Networks](https://developersvoice.com/blog/mobile/offline-first-sync-patterns/) — MEDIUM confidence
- [Recovering Data From A Corrupt SQLite Database (official sqlite.org)](https://sqlite.org/recovery.html) — HIGH confidence, official source
- [How to Fix a Corrupted SQLite Database](https://blog.corenexis.com/how-to-fix-a-corrupted-sqlite-database) — MEDIUM confidence
- [native_geofence | Flutter package (pub.dev)](https://pub.dev/packages/native_geofence) — HIGH confidence, official package page (specific 2026 background-cadence details were LOW confidence / not directly found, carried over from prior project research per PROJECT.md)
- [Region Monitoring and iBeacon — Apple official docs](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html) — HIGH confidence, official Apple source, confirms 20-region cap
- [How to Monitor More than 20 Regions in Your iOS App — PlotProjects](https://www.plotprojects.com/blog/how-to-monitor-more-than-20-regions-in-your-ios-app/) — MEDIUM confidence, confirms sliding-window / significant-location-change pattern used by commercial geofencing SDKs
- [Location updates in Android 11 — Android Developers official](https://developer.android.com/about/versions/11/privacy/location) — HIGH confidence, official
- [Access location in the background — Android Developers official](https://developer.android.com/develop/sensors-and-location/location/background) — HIGH confidence, official
- [Understanding location in the background permissions — Google Play Console Help official](https://support.google.com/googleplay/android-developer/answer/9799150?hl=en) — HIGH confidence, official Play policy source
- [Avoid unoptimized downloads — Android Developers official](https://developer.android.com/develop/connectivity/avoid-unoptimized-downloads) — HIGH confidence, official
- [What should you know about Android WorkManager Constraints? — Medium](https://chaitanyaduse.medium.com/what-should-you-know-about-android-workmanager-constraints-68dacaa4292b) — MEDIUM confidence, corroborates official WorkManager docs on `NetworkType.UNMETERED`
- [Orphaned Files: What They Are & Safe Cleanup — Cleanor](https://cleanor.app/reference/orphaned-files) — LOW-MEDIUM confidence, general consumer-facing source but describes the mechanism accurately
- [The Outbox Pattern: A Love Letter to Eventual Consistency — DEV Community](https://dev.to/igornosatov_15/the-outbox-pattern-a-love-letter-to-eventual-consistency-3ch3) — MEDIUM confidence
- [Transactional outbox pattern — AWS Prescriptive Guidance (official)](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html) — HIGH confidence, official AWS documentation on idempotency/at-least-once delivery
- Direct codebase audit findings already recorded in `.planning/PROJECT.md` (Context section) — HIGH confidence, primary source

---
*Pitfalls research for: Cíngula App sync + hybrid geofencing + area-based download milestone*
*Researched: 2026-08-08*
