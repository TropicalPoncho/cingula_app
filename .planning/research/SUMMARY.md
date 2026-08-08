# Project Research Summary

**Project:** Cingula App - offline-first sync + hybrid geofencing + area-based content download milestone
**Domain:** Geolocated audio-tour mobile app (Flutter/SQLite) adding bidirectional mobile-backend sync and battery-safe background geofencing on top of an existing local-first codebase
**Researched:** 2026-08-08
**Confidence:** MEDIUM-HIGH

## Executive Summary

This milestone is not a greenfield build - it's three additive layers grafted onto an existing clean-architecture Flutter app that already has the right shape (repositories to local data sources to SQLite, with an outbox already recording every write, and a `SyncApi`/`RunSyncUseCase` scaffold already wired to a stub). Experts building this class of app (offline-first sync + geofence-triggered media + hiking/tour offline content) converge on the same three patterns this project has already chosen: transactional-outbox sync with server-authoritative last-write-wins (appropriate because this is single-editor v0, not multi-user), two-tier geofencing (native OS region monitoring for coarse/battery-cheap detection, fine-grained polling only inside an active region for small-radius trigger precision), and download-ahead-of-use content delivery (never require connectivity at the exact trigger location).

The recommended approach is: (1) fix the pre-existing, unrelated-to-sync data-loss bugs first (silent DB delete-and-recreate on open failure, unconfirmed destructive debug buttons) since sync amplifies their blast radius; (2) build a real `SyncApi` HTTP implementation against Neon (Postgres) + Vercel Functions, reusing the existing outbox/cursor protocol rather than adopting a heavier sync engine (PowerSync/ElectricSQL) that would require rewriting the local data layer; (3) replace `geofence_service`'s continuous-polling foreground service with `native_geofence` for region-level detection, keeping the existing fine-polling loop scoped to only run inside an active region; (4) hang audio preload and area-based download off the region-enter event that already exists in the codebase.

The key risks are all silent-failure modes, not crashes: a naive first-sync can silently overwrite months of local-only data with an empty backend's state; naive "swap the geofencing plugin" treatments silently degrade small-radius trigger precision because native geofencing was designed for POI-scale radii, not 12m triggers; iOS's hard 20-region cap silently drops registrations with no error once the catalog grows past ~20 regions/triggers; and downloads fired inline on region-entry in a low-signal area silently corrupt files or burn data plans. Every one of these has a well-documented mitigation (bootstrap-before-pull ordering, keep two geofencing tiers, sliding-window region rotation, temp-file+atomic-rename downloads gated on network type) and the roadmap below sequences work so each is addressed at the phase where it's introduced, not discovered later in the field.

## Key Findings

### Recommended Stack

The stack fills gaps around an already-decided architecture rather than making fresh technology choices from scratch. Backend: Neon (managed Postgres, scale-to-zero, free tier fits a single-editor workload at $0/month) plus Vercel Functions (Node/TS serverless) implementing the existing custom `/sync/push`, `/sync/state`, `/sync/changes` contract - a generic PostgREST/Supabase auto-API doesn't fit because the protocol needs custom logic (batch ack by UUID, cursor-ordered pull, version pruning) that a table-CRUD API can't express without RPC anyway. On the Flutter side: add `http` (not `dio` - the protocol's retry logic already lives in the outbox's `markAttempt` counter, so interceptor/cancellation machinery is unused complexity), `connectivity_plus` (as a cheap pre-check only, not a source of truth for sync success), and `native_geofence` (^1.3.1, MIT, actively maintained, wraps `GeofencingClient`/`CLLocationManager` directly) to replace `geofence_service`. `geolocator`, `flutter_local_notifications`, `workmanager`, and `wakelock_plus` are already in the project and are reused as-is for the fine-polling tier.

**Core technologies:**
- Neon (Postgres, serverless) - backend datastore - free scale-to-zero tier matches intermittent, low-volume, single-editor workload
- Vercel Functions (Node/TS) - thin HTTP API for the existing sync contract - near-zero cost, no ops burden, fits custom protocol logic
- `native_geofence` ^1.3.1 - region-level native OS geofencing - replaces the battery-draining `geofence_service` polling loop
- `http` package - sync HTTP client - matches protocol simplicity already built into the outbox
- `connectivity_plus` - pre-sync network heuristic only - not a substitute for real HTTP success/failure handling

### Expected Features

**Must have (table stakes) - P1 for this milestone:**
- Non-destructive DB failure handling + confirmation-gated destructive debug actions (blocks everything else)
- Push sync (idempotent, backoff+jitter) against a real backend
- Pull sync actually invoked (bidirectional, replace-with-latest semantics)
- Honest, visible sync status (pending count + last-sync timestamp, not a fake "synced" indicator)
- Region-level native geofencing replacing continuous foreground polling
- iOS ~19-region sliding window (re-evaluated on movement, not registered once)
- Fine-grained in-region polling retained for small-radius trigger accuracy
- Trigger-boundary debounce/hysteresis (GPS jitter vs. 12m radius)
- Audio preload of the nearest trigger ahead of arrival
- Content download-on-region-entry with opportunistic retry when signal returns, resumable/atomic (no half-written files)
- Downloaded-content staleness invalidation tied to `logical_version`
- Runtime user/debug toggle (not build flavors)

**Should have (differentiators) - explicitly deferred this milestone:**
- Predictive multi-trigger preload (only if closely-spaced triggers prove nearest-1 insufficient)
- Adaptive trigger radius based on live GPS accuracy
- Storage quota management / auto-eviction

**Defer (v2+):**
- Multi-editor conflict resolution (CRDTs, 3-way merge) - no concurrency problem to solve until multi-editor
- Real-time/websocket push sync - no live counterpart to push against until a web editor exists
- Wi-Fi-only download guard - less relevant than "any signal available" in this connectivity environment

### Architecture Approach

The new work fits into two seams that already exist (`sync_outbox`/`sync_state`, and the `GeofenceBackgroundService` injection point in `MonitorUserLocationUseCase`) plus one new seam: a local-only write primitive (`applyRemoteChange()`) needed by both pull-apply and download-apply so neither re-enqueues itself back into the outbox. No new top-level architecture layer or generic "sync engine" abstraction is introduced - `RunSyncUseCase` gains a `pullAndApplyOnce()` sibling to its existing push method, and that is the entire "engine."

**Major components:**
1. `SyncApi` (real HTTP impl) + `SyncClient` (existing) + `RunSyncUseCase` (extended) - push-then-pull cycle, using the already-built outbox as the capture mechanism
2. `RegionMonitor` (new, wraps `native_geofence`, runs partly in a background isolate) + `RegionWindowSelector` (new, pure nearest-<=19 selection) + `GeofenceOrchestrator` (new, replaces `GeofenceBackgroundService` behind the exact same interface) - glues native region detection to the existing `FineTriggerPoller`
3. Local-only write primitive `applyRemoteChange()` on each `*LocalDataSource` - the one genuinely new data-layer primitive, shared by pull-apply and area-download so neither corrupts the outbox
4. `DownloadRegionAudioUseCase` (new) - subscriber on the existing `onRegionChange` callback, downloads to temp file + atomic rename, writes `local_path` via the local-only write primitive

Suggested build order from architecture research: (1) DB safety fix first - blocking; (2) real `SyncApi` + scheduled push - independent, can start immediately after (1); (3) local-only write primitive + pull path - prerequisite for both sync-pull and download; (4)/(5) hybrid geofencing replacement + rotating window - independent of sync, parallel work stream, needs real-device testing; (6) audio preload - only depends on (1); (7) area-download - needs (3) for non-null `remote_url`; (8) debug/user toggle - orthogonal, anytime.

### Critical Pitfalls

1. **Silent DB delete-and-recreate on open failure (already in codebase)** - any transient open failure permanently wipes all local data with no backup. Fix: back up before any destructive fallback, never auto-recreate; must land before any sync work since sync increases DB-touch frequency.
2. **First-sync "adopt vs. overwrite" ambiguity** - connecting a phone with months of pre-existing local data to a fresh empty backend can silently let pull overwrite/delete local rows. Fix: push must fully drain and ack before the first pull ever runs (explicit bootstrap state machine), and pull must never destructively replace local-only rows.
3. **Partial sync failure / non-idempotency** - a push batch that partially succeeds (connection drops mid-batch) can double-apply or drop mutations if outbox rows are cleared batch-wide instead of per-row-ack. Fix: server-side idempotency keyed by the existing client UUID, per-row ack clearing only.
4. **Hybrid geofencing treated as "just swap the plugin"** - native geofencing's inherent latency (20-30s+ debounce, minutes-scale background checks) will silently degrade 12m-radius trigger detection if pointed at the same mechanism used for large-radius regions. Fix: keep the two-tier design - native only for region entry/exit, fine polling only inside an active region.
5. **iOS 20-region cap hit silently** - registering geofences once at launch (not re-evaluated on movement) means any region/trigger outside the first ~20 registered silently never fires, once the catalog grows past the cap. Fix: rotating nearest-<=19 window, re-evaluated on significant location change.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Harden Local Data Integrity
**Rationale:** Both critical, already-live data-loss bugs (silent DB recreate-on-failure, unconfirmed destructive debug buttons) are unrelated to sync but sync amplifies their blast radius (background sync ticks, pull merges touch the DB far more often). Must land before any other work in this milestone.
**Delivers:** Backup-before-any-destructive-fallback DB open path; confirmation-gated (typed confirm) destructive debug actions with auto-backup, independent of the debug/user toggle.
**Addresses:** "Non-destructive local DB failure handling" and "Explicit confirmation on destructive debug actions" (FEATURES.md table stakes).
**Avoids:** Pitfall 1 (silent DB delete-and-recreate) and Pitfall 2 (unconfirmed destructive UI).

### Phase 2: Real Backend + Push Sync
**Rationale:** Independent of geofencing work, can proceed immediately after Phase 1. Reuses the already-built outbox capture mechanism - only needs a real HTTP implementation and a schedule.
**Delivers:** Neon + Vercel Functions backend implementing the existing `/sync/push`/`/sync/state` contract; `sync_api_http.dart` replacing `SyncApiStub`; `RunSyncUseCase` triggered on app resume/connectivity-regained/periodic Workmanager tick; visible sync status (pending count + last-sync timestamp).
**Uses:** Neon, Vercel Functions, `@neondatabase/serverless`, `http` package, `connectivity_plus` (STACK.md).
**Implements:** `SyncApi` real impl (ARCHITECTURE.md Component Responsibilities).
**Avoids:** Pitfall 5 (partial sync / non-idempotency) - per-row ack, idempotency key by UUID; Pitfall 4 (schema/migration drift) - explicit schema_version, never clear outbox on ambiguous response.

### Phase 3: Bidirectional Sync (Pull + Local-Only Write Primitive)
**Rationale:** Depends on Phase 2's real `SyncApi`. Builds the local-only write primitive once, shared by pull-apply and (later) download-apply, avoiding two ad hoc "write without outbox" implementations.
**Delivers:** `applyRemoteChange()` on each `*LocalDataSource`; `pullAndApplyOnce()` on `RunSyncUseCase`; explicit first-sync bootstrap state machine (push-to-completion before first pull); skip-pull-apply-if-pending-outbox conflict rule.
**Addresses:** "Pull sync actually invoked" and "Downloaded-content staleness invalidation" (FEATURES.md).
**Avoids:** Pitfall 3 (first-sync adopt/overwrite ambiguity) - the single most consequential edge case for this milestone; requires an explicit test seeding a device with local-only data before first backend connection.

### Phase 4: Hybrid Geofencing Replacement
**Rationale:** Architecturally independent of sync, can be built in parallel with Phases 2-3 by a different work stream, but isolated as its own phase given real platform/native-config risk (Android manifest receiver, iOS background modes) and the need for real-device (not simulator) testing.
**Delivers:** `RegionMonitor` (native_geofence wrapper + background isolate bootstrap) + `RegionWindowSelector` (pure nearest-<=19 selection) + `GeofenceOrchestrator` (replaces `GeofenceBackgroundService` behind the identical interface, so `MonitorUserLocationUseCase` needs zero changes) + rotating window re-evaluated on significant location change.
**Uses:** `native_geofence` ^1.3.1 (STACK.md); requires `minSdkVersion` verification (23) and Kotlin pinned ~1.9.x.
**Implements:** Pattern 3 (two-level geofencing) and Pattern 4 (background isolate bootstrap) from ARCHITECTURE.md.
**Avoids:** Pitfall 6 (naive plugin swap degrading trigger precision) - keep fine polling scoped inside active region only; Pitfall 7 (iOS 20-region cap silently hit) - explicit test with 25+ seeded regions/triggers and simulated movement.

### Phase 5: Audio Preload + Area-Based Content Download
**Rationale:** Preload only depends on Phase 1 (can land any time after, independent of geofencing swap). Area-download structurally only needs the existing `onRegionChange` hook (works with old or new geofencing), but functionally needs Phase 3 (pull sync) to populate non-null `remote_url` - sequence after Phase 3.
**Delivers:** Preload hook in the existing nearest-trigger loop (new branch, not a new component); `DownloadRegionAudioUseCase` triggered on region-enter, gated on real network constraints (not fired inline), temp-file + atomic-rename downloads, resumable/retryable; periodic orphaned-file reconciliation sweep.
**Addresses:** "Audio preload before trigger fires," "Content download triggered on region entry," "Resumable/retryable downloads" (FEATURES.md).
**Avoids:** Pitfall 8 (download on weak/metered signal causing corrupt files/data charges) - decouple "mark for download" from "actually download," gate on network type; Pitfall 9 (orphaned audio files) - tie file lifecycle 1:1 to DB row plus a periodic sweep as safety net.

### Phase Ordering Rationale

- Data-integrity hardening comes first because it is a pre-existing live risk that every subsequent phase (which writes more data via sync and downloads) would otherwise amplify.
- Sync (push then pull) is sequenced before download because download is functionally gated on pull populating `remote_url` - structurally it only needs the region-enter event, but shipping it before pull sync means testing against permanently-null URLs.
- Geofencing is architecturally independent of sync and can run in parallel, but is isolated as its own phase because of real native/platform risk (device testing, manifest/entitlement changes) that should not be mixed with backend work.
- Preload and download are sequenced last since they are additive branches on existing hooks (`onRegionChange`, the nearest-trigger loop) rather than new detection mechanisms - they depend on both the DB safety net and (for download specifically) real `remote_url` values from pull sync.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2 (Real Backend + Push Sync):** Choosing/finalizing between Neon+Vercel vs. alternatives once actual invocation volume and future web-editor auth/storage needs are clearer - STACK.md flags this as a MEDIUM-confidence, project-specific judgment call, not an external standard.
- **Phase 4 (Hybrid Geofencing Replacement):** Real-device latency measurements (region-entry debounce, iOS background check cadence) are documented as ranges, not guarantees - needs on-the-ground validation in the actual Comarca Andina terrain before locking success criteria.
- **Phase 5 (Area-Based Content Download):** Android `WorkManager` network-constraint tuning (`NetworkType.UNMETERED` vs. user-configurable cellular opt-in) may need refinement once real connectivity patterns in Lago Puelo are observed.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Harden Local Data Integrity):** Well-documented SQLite recovery patterns (official sqlite.org guidance), standard confirmation-dialog UX - no deep research needed.
- **Phase 3 (Bidirectional Sync / Pull):** Outbox + LWW-with-pending-outbox-skip is a well-established pattern (AWS Prescriptive Guidance, multiple converging sources), and the codebase already has the schema fields (`uuid`, `logical_version`, `updated_at`) needed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | `native_geofence`/`http`/`connectivity_plus` verified directly on pub.dev (HIGH); Neon/Vercel pricing and the hand-rolled-vs-PowerSync tradeoff are project-specific judgment calls backed by aggregated 2026 comparison sources (MEDIUM) |
| Features | MEDIUM-HIGH | Platform mechanics (geofencing limits, latency) verified via official Android/Apple docs (HIGH); sync/download UX patterns converge across multiple independent sources but no single canonical spec (MEDIUM) |
| Architecture | HIGH / MEDIUM | Component boundaries derived directly from existing code + verified plugin docs (HIGH); rotating-window tuning and conflict-resolution details reasoned from general patterns, no single-editor case study found (MEDIUM) |
| Pitfalls | MEDIUM-HIGH | Codebase risks (Pitfalls 1, 2) verified directly by prior audit in PROJECT.md (HIGH); ecosystem patterns (outbox idempotency, geofencing caps) verified via multiple official/community sources (MEDIUM-HIGH); some 2026-specific package cadence claims are LOW confidence and explicitly flagged in PITFALLS.md |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Backend host not yet finalized:** Neon+Vercel is the STACK.md recommendation but PROJECT.md still lists host as TBD (VPS/Supabase/Neon/Vercel). The `SyncApi` interface is backend-agnostic so this does not block Phase 2 implementation start, but should be confirmed before deploying Phase 2.
- **Real-world geofencing latency numbers:** Region-entry debounce and iOS background-check cadence are documented as ranges from official docs and third-party reports, not measured against this specific app/terrain - Phase 4 should include explicit real-device, real-terrain latency measurement as an acceptance criterion, not just a walk-test near WiFi.
- **Auth on the new backend:** PITFALLS.md flags "no auth because it is just me, v0" as a security mistake to avoid from day one - Phase 2 scope should include a minimal API key/bearer token even for single-user v0, not deferred.
- **iOS 19-region budget split between Regions and Triggers:** Architecture research notes the two geofencing tiers share one iOS cap but does not fully resolve how to split the budget between them if both scale - flag for validation during Phase 4 planning once the actual regions/triggers catalog size is known.

## Sources

### Primary (HIGH confidence)
- https://pub.dev/packages/native_geofence - version, license, platform support, terminated-app behavior (fetched directly)
- https://pub.dev/packages/http, https://pub.dev/packages/connectivity_plus - latest versions, reachability caveat (fetched directly)
- Android Developers - Create and monitor geofences (developer.android.com) - official docs
- Android Developers - Optimize location use for real-world scenarios (developer.android.com) - official docs
- Apple Developer - Region Monitoring and iBeacon - official docs, confirms 20-region cap
- Recovering Data From A Corrupt SQLite Database (sqlite.org) - official
- Transactional outbox pattern - AWS Prescriptive Guidance - official
- Avoid unoptimized downloads - Android Developers - official
- Existing codebase (read directly across all four research passes): `lib/data/sync/`, `lib/domain/usecases/`, `lib/core/services/`, `lib/data/datasources/local/app_database.dart`, `pubspec.yaml`, `.planning/PROJECT.md`

### Secondary (MEDIUM confidence)
- WebSearch aggregated 2026 pricing comparisons - Neon vs. Supabase, Fly.io free-tier removal, Vercel+Neon HTTP-driver rationale
- Radar - Geofencing iOS: Understanding the limitations (radar.com/blog) - commercial SDK vendor, technically detailed, consistent with Apple's own docs
- PlotProjects - How to Monitor More than 20 Regions in Your iOS App - sliding-window pattern confirmation
- Exponential backoff/jitter industry-consensus sources (Presidio, Baeldung, oneuptime.com) - no single authoritative spec, broad convergence
- ObjectBox - Customizable conflict resolution for offline-first apps - vendor blog, consistent with broader pattern

### Tertiary (LOW confidence)
- Specific 2026 background-cadence numbers for `native_geofence` beyond what is in official docs - carried over from prior project research per PROJECT.md, not independently re-verified this pass
- Cleanor - Orphaned Files: What They Are and Safe Cleanup - general consumer-facing source, mechanism described accurately but not authoritative

---
*Research completed: 2026-08-08*
*Ready for roadmap: yes*
