# Architecture Research

**Domain:** Offline-first mobile app (Flutter) adding bidirectional sync + hybrid native geofencing + area-based content download on top of an existing local-first SQLite codebase
**Researched:** 2026-08-08
**Confidence:** HIGH (component boundaries — derived directly from existing code + verified plugin docs) / MEDIUM (rotating-window tuning, HLC-style conflict details — no single-editor case study found, reasoned from general offline-first + iOS SDK patterns)

## Standard Architecture

### System Overview

This is not a greenfield architecture — it's three additive layers grafted onto an existing clean-architecture Flutter app. The existing app already has the right shape (repositories → local data sources → SQLite, with an outbox already recording every write). The new work fits into two seams that already exist (`sync_outbox`/`sync_state`, and the `GeofenceBackgroundService` injection point in `MonitorUserLocationUseCase`) and one seam that has to be added (a "local-only write" path, needed by both pull-apply and download-apply so neither one re-enqueues itself back into the outbox).

```
┌───────────────────────────────────────────────────────────────────────────┐
│  DOMAIN (unchanged)                                                        │
│  ┌────────────────────────────┐   ┌────────────────────────────────────┐ │
│  │ MonitorUserLocationUseCase  │   │ RunSyncUseCase (extend: push+pull)  │ │
│  │  - injects a monitor with   │   │ DownloadRegionAudioUseCase (new)    │ │
│  │    the SAME interface shape │   └────────────────────────────────────┘ │
│  │    GeofenceBackgroundService│                                          │
│  │    exposes today            │                                          │
│  └──────────────┬───────────────                                          │
├─────────────────┼──────────────────────────────────────────────────────────┤
│  NEW: GEOFENCE ORCHESTRATION LAYER (replaces GeofenceBackgroundService)   │
│  ┌────────────────┐   ┌──────────────────┐   ┌───────────────────────┐  │
│  │ RegionMonitor    │──▶│ GeofenceOrchestr. │──▶│ FineTriggerPoller     │  │
│  │ (native_geofence)│   │ (region↔trigger  │   │ (= today's polling    │  │
│  │ region enter/exit│   │  lifecycle glue)  │   │  loop inside          │  │
│  │ + RegionWindow-  │   │                   │   │  _handleCoordinate,   │  │
│  │  Selector (19-cap│   │                   │   │  scoped to 1 region)  │  │
│  └────────────────┘   └──────────────────┘   └───────────────────────┘  │
├───────────────────────────────────────────────────────────────────────────┤
│  DATA (repositories + local data sources — unchanged read/write API,      │
│         gains one new capability: applyRemote* / local-only write)        │
│  ┌─────────────┐ ┌──────────────┐ ┌─────────────┐ ┌────────────────────┐ │
│  │ GeoTrigger   │ │ GeoPath       │ │ Region      │ │ Audio               │ │
│  │ Repository   │ │ Repository    │ │ Repository  │ │ Repository          │ │
│  └──────┬──────┘ └──────┬───────┘ └──────┬──────┘ └──────────┬─────────┘ │
│         └────────────────┴────────────────┴───────────────────┘          │
│                          SyncLocalDataSource (already writes outbox)      │
├───────────────────────────────────────────────────────────────────────────┤
│  NEW: SYNC ENGINE (sits BESIDE repositories, talks only through them)     │
│  ┌───────────────┐  ┌───────────────┐  ┌────────────────────────────┐   │
│  │ RunSyncUseCase │─▶│ SyncClient     │─▶│ SyncApi (real HTTP impl,   │   │
│  │ push()+pull()  │  │ (outbox r/w,   │  │  replaces SyncApiStub)     │   │
│  │ orchestration  │  │  cursor state) │  │                            │   │
│  └───────────────┘  └───────────────┘  └────────────────────────────┘   │
│  Triggered by: app resume, connectivity-regained, periodic Workmanager   │
│  task (reuse existing callbackDispatcher pattern in background_worker)   │
└───────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Notes |
|-----------|----------------|-------|
| `SyncApi` (real impl) | HTTP push/pull against the backend, cursor-based | Replaces `SyncApiStub`; interface (`SyncPushResult`/`SyncPullResult`/`SyncStateResult`) already exists and doesn't need to change |
| `SyncClient` | Reads pending outbox rows, tracks `sync_state` cursor/device_id | Already exists, already local-only; needs no change for push, gains no new responsibility for pull (pull-apply is a different concern, see below) |
| `RunSyncUseCase` | Orchestrates one sync cycle: push outbox batch → ack/mark-attempt → **then** pull remote changes → apply them locally | Already exists for push only (`pushOutboxOnce`); needs a `pullAndApplyOnce()` sibling method, and a `runFullCycle()` that does push-then-pull in that order (see Data Flow) |
| **Local-only write primitive** (new) | Lets a caller upsert/delete a row in `audio_assets`/`geo_triggers`/`geo_paths`/`regions` **without** enqueueing a new outbox entry | Needed by both pull-apply (remote change → local row) and by area-download (local file path written after download). Implement once as e.g. `applyRemoteChange()` on each `*LocalDataSource`, reusing the existing `insert`/`update` calls but skipping `enqueueOutbox()`. This is the one genuinely new primitive the sync + download work both depend on — build it once |
| `RegionMonitor` (new) | Thin wrapper around the `native_geofence` plugin: register/unregister native OS geofences for the *currently windowed* set of regions, surface enter/exit as a stream/callback | Runs partly in a **separate background isolate** — `native_geofence` delivers events via a top-level callback, same pattern this codebase already uses for `Workmanager` in `background_worker.dart`'s `callbackDispatcher`. That isolate has no access to the running `GetIt` container from the UI isolate and must bootstrap its own minimal DB/repository set on entry |
| `RegionWindowSelector` (new, pure) | Given last known coarse coordinate + all regions, returns the nearest ≤19 to monitor | Pure function, easily unit-testable, no I/O. Called on cold start, on significant coarse location change, and after a region exit — not on every fine GPS tick |
| `GeofenceOrchestrator` (new, replaces `GeofenceBackgroundService`) | Glues `RegionMonitor` (region-level, native, coarse) to `FineTriggerPoller` (trigger-level, polling, precise): on region-enter, starts fine polling scoped to that region's triggers + fires `onRegionChange`; on region-exit, stops fine polling + fires `onRegionChange(null)` | **Must expose the same method shape `GeofenceBackgroundService` exposes today** (`start({triggers, regions, onLocation, onRegionChange, onLog, ...})` / `stop()`) so `MonitorUserLocationUseCase`'s constructor and `start()`/`stop()` bodies need **zero changes** — only the DI registration in `service_locator.dart` swaps the concrete class |
| `FineTriggerPoller` | Same job the polling loop inside `MonitorUserLocationUseCase._handleCoordinate` already does today (nearest-trigger matching, audio play/pause, offset save) | **Does not change.** It just needs to only be "hot" while inside a region — today it's always hot because `geofence_service` polls continuously everywhere |
| Audio preload hook | Preload the nearest trigger's audio before the user crosses into its radius | Not a new component — a new branch inside the *existing* nearest-trigger distance loop in `_handleCoordinate`, calling a new `AudioPlaybackGateway.preload(asset)` that does today's `loadPath()` without `play()` |
| Area-download hook | Download/mark-for-download the audio for a region's assets when entering that region | Not a new component — a subscriber on the *existing* `onRegionChange` callback (already fired by `GeofenceBackgroundService` today, will be fired by `GeofenceOrchestrator` tomorrow), driving a new `DownloadRegionAudioUseCase` |

## Recommended Project Structure

Extends the existing `lib/` layout — no restructuring of existing folders.

```
lib/
├── core/
│   ├── background/
│   │   └── background_worker.dart        # existing Workmanager entrypoint — reused,
│   │                                      # not replaced, for periodic sync triggers
│   └── services/
│       ├── geofence_background_service.dart   # existing — kept as reference/fallback
│                                                # until GeofenceOrchestrator ships, then removed
│       └── geofencing/                     # NEW folder
│           ├── region_monitor.dart          # native_geofence wrapper + background isolate entrypoint
│           ├── region_window_selector.dart  # pure nearest-N selection logic
│           ├── geofence_orchestrator.dart   # replaces GeofenceBackgroundService
│           └── fine_trigger_poller.dart     # extracted from monitor_user_location_usecase
├── data/
│   ├── sync/
│   │   ├── sync_api.dart                  # existing interface — unchanged
│   │   ├── sync_api_stub.dart             # existing — kept for tests
│   │   ├── sync_api_http.dart             # NEW real implementation
│   │   ├── sync_client.dart               # existing — unchanged
│   │   └── pull_apply_service.dart        # NEW: applies SyncPullResult.changes to local tables
│   └── datasources/local/
│       └── *_local_data_source.dart       # gain one new method each: applyRemoteChange()
└── domain/
    └── usecases/
        ├── run_sync_usecase.dart          # existing — extend with pull()/runFullCycle()
        └── download_region_audio_usecase.dart  # NEW
```

### Structure Rationale

- **`core/services/geofencing/`:** groups the four new region/trigger components together and keeps them clearly separate from the sync work — they have unrelated lifecycles and unrelated dependencies (one needs `native_geofence` + platform channels, the other needs HTTP).
- **`data/sync/pull_apply_service.dart`** is deliberately a sibling of `sync_client.dart`, not folded into it — `SyncClient` today is a pure local-outbox/cursor reader; mixing "apply remote rows to arbitrary tables" into it would force it to depend on every `*LocalDataSource`, which it doesn't today. Keep push-side (`SyncClient`) and pull-apply-side as separate small objects, both owned by `RunSyncUseCase`.
- No new top-level architecture layer is introduced. This deliberately avoids introducing a generic "sync engine" abstraction/interface for a single push+pull cycle — YAGNI until there's a second backend or a second sync direction beyond outbox+cursor.

## Architectural Patterns

### Pattern 1: Outbox capture already done — sync engine only needs to drain it

**What:** Every write in this app already goes through `insert`/`update`/`delete` methods on `*LocalDataSource` that call `SyncLocalDataSource.withInsertMetadata`/`withUpdateMetadata` and `enqueueOutbox(...)`. This is the entire "capture" half of the outbox pattern, already built and already correct.
**When to use:** No new capture code is needed anywhere. The only work is (1) build a real `SyncApi` HTTP implementation, (2) call `RunSyncUseCase` on a schedule, (3) add the pull half.
**Trade-offs:** None — this is a "don't touch it" finding. The risk is in *not noticing* it's already there and rebuilding a parallel change-tracking mechanism.

### Pattern 2: Conflict resolution — server-authoritative, client-trivial, because v0 is single-editor

**What:** Given the constraint that v0 has exactly one editor and the server keeps "current + 1 previous version" (per `PROJECT.md` Key Decisions), conflict resolution does not need CRDTs, vector clocks, or manual merge UI. The rule is: client always pushes its outbox first; server accepts if `logical_version` is monotonic for that record (or just accepts and increments — single editor, no concurrent writers); client then pulls and **replaces** any local row whose remote `logical_version`/`updated_at` is newer than what's stored locally, except rows that still have a pending (unacked) outbox entry for that `uuid` — those are skipped on this pull cycle so an in-flight local edit isn't clobbered before its own push lands.
**When to use:** Applies to every table with `uuid`/`logical_version`/`updated_at` already in the schema (`audio_assets`, `geo_triggers`, `geo_paths`, `regions`).
**Trade-offs:** This breaks the moment there's a second concurrent editor (out of scope per `PROJECT.md`, explicitly deferred). Don't build anything more sophisticated than "skip pull-apply for records with a pending outbox row" — that's the entire conflict-avoidance logic needed for v0.

**Example (pull-apply decision, pseudocode matching existing method names):**
```dart
for (final change in pullResult.changes) {
  final hasPendingOutbox = await syncClient.hasPendingOutboxFor(change['uuid']);
  if (hasPendingOutbox) continue; // let this device's own push win first
  await localDataSource.applyRemoteChange(change); // no outbox re-enqueue
}
```

### Pattern 3: Two-level geofencing — native for region, polling for trigger, glued by one orchestrator

**What:** Region-level geofences (few, large radius) use OS-native `CLLocationManager`/`GeofencingClient` monitoring via `native_geofence` — low battery cost, works with the app killed, but debounced (seconds-to-minutes latency, per Android/iOS docs). Trigger-level geofences (many, small radius, e.g. 12m) keep using the *existing* fine-polling loop already in `_handleCoordinate`, but only while a region is active — not globally, which is what wastes battery today.
**When to use:** This is already the direction encoded in the existing schema (`region_id` nullable FK on `geo_triggers`) — the componentization below just makes it real instead of aspirational.
**Trade-offs:** Region entry/exit now has native-level latency (tens of seconds), so a user standing right at a region boundary may take longer to have fine-polling start. Mitigate by keeping region radii meaningfully larger than trigger radii (already true — region radius vs. 12m trigger radius) so the debounce window is absorbed by the walk from region edge to nearest trigger.

### Pattern 4: Background isolate bootstrap for native geofence callbacks

**What:** `native_geofence`'s background callback (like `Workmanager`'s `callbackDispatcher`, which this codebase already has in `background_worker.dart`) fires in a detached Dart isolate with no access to the running app's `GetIt` container. `RegionMonitor`'s callback entrypoint must be a top-level or static function that calls a minimal, idempotent bootstrap (open `AppDatabase`, construct just the repositories it needs) before doing anything — it cannot assume `setupServiceLocator()` from `main.dart` already ran in that isolate.
**When to use:** Any code inside the `native_geofence` triggered-callback.
**Trade-offs:** Slightly more boilerplate than a plain callback, but this codebase already pays this cost for `Workmanager` — same shape, same fix, not a new pattern to invent.

## Data Flow

### Push + pull sync cycle

```
[trigger: app resume | connectivity regained | periodic Workmanager tick]
    ↓
RunSyncUseCase.runFullCycle()
    ↓
 1. PUSH  SyncClient.pendingOutbox() → SyncApi.pushOutbox() → ack/markAttempt → SyncClient.saveState(cursor)
    ↓                                                              (must complete/settle before pull —
 2. PULL  SyncApi.pullChanges(cursor) → for each change:            pushing first means this device's own
             - skip if uuid has pending outbox row                  edits aren't immediately overwritten
             - else *LocalDataSource.applyRemoteChange(change)      by the server's pre-push view)
    ↓
SyncClient.saveState(newCursor)
```

Push-before-pull ordering matters precisely because of the single-editor conflict rule in Pattern 2 — pulling first would let a stale-relative-to-this-device's-outbox server state overwrite a local edit that hasn't been pushed yet.

### Region window (iOS 20-region cap) rotation

```
LocationRepository (coarse stream — geolocator distanceFilter, NOT the fine per-second stream
                     used for trigger polling; a coarse update every ~100-300m of movement is enough)
    ↓ on: cold start | significant coarse move | after a region-exit event
RegionWindowSelector.select(allRegions, lastCoarseCoordinate) → nearest ≤19 (pure, no I/O)
    ↓
RegionMonitor.updateMonitoredRegions(windowedRegions)
    ↓
native_geofence: unregister regions that fell out of window, register newly-windowed ones
    ↓ (async, native OS debounce)
native_geofence background callback → RegionMonitor's isolate-safe entrypoint
    ↓
GeofenceOrchestrator receives enter/exit → starts/stops FineTriggerPoller scoped to that region
                                          → fires onRegionChange(region) to domain layer
    ↓                                          ↓
audio preload hook (in FineTriggerPoller's   DownloadRegionAudioUseCase.run(region)
existing nearest-trigger loop)               (queries AudioRepository for this region's
                                              assets missing a local file, downloads,
                                              writes local_path via applyRemoteChange —
                                              NOT the outbox-enqueueing update path)
```

One edge case worth a one-line rule, not a component: whatever region the user is *currently inside* must stay pinned in the monitored window even if a coarse-position recompute would otherwise rank it outside the nearest-19 (unlikely given region radii, but cheap to guard against near a region boundary).

### Key Data Flows

1. **Push (write path, already built):** every local write → `*LocalDataSource` insert/update/delete → `SyncLocalDataSource.enqueueOutbox()` → sits in `sync_outbox` until `RunSyncUseCase` drains it. No architecture change needed here, only "make it real + make it run periodically."
2. **Pull (new):** `SyncApi.pullChanges(cursor)` → skip-if-pending-outbox filter → `applyRemoteChange()` (local-only write, no outbox re-entry) → cursor advances in `sync_state`.
3. **Region rotation (new):** coarse location → pure nearest-N selector → native geofence re-registration → native callback (separate isolate) → orchestrator.
4. **Trigger fire + preload (existing loop, additive branch):** fine poll inside active region → nearest-trigger distance calc (already exists) → new: if approaching-but-not-yet-inside, call `preload()`; if inside, `play()`/`playFrom()` as today.
5. **Area download (new, reuses region-enter event that already exists today):** `onRegionChange(region)` → `DownloadRegionAudioUseCase` → HTTP download → `applyRemoteChange` writes `local_path` locally only.

## Scaling Considerations

This is a single-user (v0) local-artist app, not a scale problem in the traditional sense — the real "scale" axis here is **number of regions/triggers**, not users.

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Current (handful of regions, one artist) | Rotating window logic is basically inert (all regions fit under 19) — but build it now anyway since the requirement is explicit and retrofitting it later means touching `RegionMonitor` twice |
| Dozens of regions across Lago Puelo trails | Rotating window becomes load-bearing; tune the coarse-recompute distance filter so native re-registration doesn't thrash near region boundaries (add hysteresis: only drop a region from the window once the user is meaningfully farther from it than the 19th-nearest, not exactly at the boundary) |
| Hundreds of geo_triggers within one active region | Android's 100-geofence cap could matter if triggers were ever registered natively too — they're not (fine-polling handles triggers), so this ceiling doesn't apply; the only cap that matters is the ≤19 *regions* |

### Scaling Priorities

1. **First bottleneck:** iOS 20-region cap once the artist adds more than ~19 regions total — solved by the rotating window described above, which is why the requirement calls for it now rather than later.
2. **Second bottleneck (unlikely soon):** outbox growth if the device is offline for a long stretch while recording — the existing `limit`/batch pattern in `RunSyncUseCase.pushOutboxOnce(limit: 50)` already handles this; no change needed.

## Anti-Patterns

### Anti-Pattern 1: Building a new generic "sync engine" abstraction

**What people do:** Introduce a `SyncEngine` interface/class hierarchy anticipating future backends, future entity types, or future conflict strategies.
**Why it's wrong:** There's exactly one backend, one conflict strategy (server-authoritative, single-editor), and four tables. `RunSyncUseCase` extended with a `pullAndApplyOnce()` method is the entire "engine." An abstraction with one implementation is dead weight the next reader has to see through.
**Do this instead:** Extend `RunSyncUseCase` directly. If a second backend or a second conflict strategy ever materializes, extract then — with two real cases in hand instead of zero.

### Anti-Pattern 2: Rewriting `MonitorUserLocationUseCase` to "do geofencing properly"

**What people do:** See that the geofencing story is changing and treat it as license to rewrite the use case that already works (trigger matching, path offset save/resume, audio state transitions — all correct today per `PROJECT.md`'s Validated list).
**Why it's wrong:** The bug being fixed (audio not starting reliably) lives in `AudioPlayerService`'s load-at-trigger-time behavior and in `geofence_service`'s continuous-polling battery cost — neither requires touching the trigger-matching logic in `_handleCoordinate`, which is orthogonal and already correct.
**Do this instead:** Swap only the `GeofenceBackgroundService` dependency for `GeofenceOrchestrator` behind the same interface shape; add `preload()` as a new branch in the existing nearest-trigger loop. Leave the rest of the file alone.

### Anti-Pattern 3: Letting pull-apply or download-apply go through the normal write path

**What people do:** Reuse `insertPath`/`updateAudio`/etc. as-is for applying a remote change or a downloaded file path.
**Why it's wrong:** Those methods call `enqueueOutbox()` — applying a pulled remote change would immediately re-queue it to be pushed straight back to the server (harmless but wasteful), and worse, applying a downloaded `local_path` would push a client-side-only file path to the server as if it were an edited field.
**Do this instead:** The `applyRemoteChange()` / local-only write primitive (Pattern 1 note in Component Responsibilities) — build it once, use it for both pull-apply and download-apply.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Backend sync API (host TBD — VPS/Supabase/Neon/Vercel per `PROJECT.md`, not chosen yet) | REST-ish JSON over HTTP(S), matching the `SyncApi` interface already defined (`pushOutbox`/`fetchState`/`pullChanges`) | Interface shape is backend-agnostic already — choosing the actual host doesn't block building `sync_api_http.dart` against the existing contract; only the base URL/auth needs to be pluggable |
| `native_geofence` plugin (Android `GeofencingClient` / iOS `CLLocationManager` region monitoring) | Dart plugin wrapping native APIs; background events delivered via a top-level callback in a detached isolate | Requires background location permission on both platforms and native config changes (Android manifest receiver, iOS background modes) — this is the one integration point with real platform/store-review risk, budget a device-testing pass for it specifically |
| Audio CDN/storage for region downloads | Plain HTTP GET of `audio_assets.remote_url` to a local file, written via the local-only write primitive | `remote_url` column already exists but is always `null` today — this only becomes exercisable once pull sync brings down non-null `remote_url` values from the (future) web editor, so area-download is functionally gated on pull sync existing, even though structurally it only depends on the region-enter event |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `MonitorUserLocationUseCase` ↔ `GeofenceOrchestrator` | Same constructor-injected interface `GeofenceBackgroundService` exposes today (`start(...)`/`stop()` with callbacks) | This is the key seam that makes the geofencing swap non-invasive — do not change this interface's shape when introducing the orchestrator, extend behind it |
| `GeofenceOrchestrator` ↔ `RegionMonitor` / `FineTriggerPoller` | Direct method calls + callbacks, all in-process (region monitor's *native* events cross an isolate boundary before reaching the orchestrator, but the orchestrator itself is single-isolate) | `RegionMonitor` is the only piece that has to know about isolate bootstrap; `GeofenceOrchestrator` and `FineTriggerPoller` don't |
| `RunSyncUseCase` ↔ repositories/local data sources | Never direct — `RunSyncUseCase` talks to `SyncClient` (outbox/state) and to each `*LocalDataSource`'s new `applyRemoteChange()` only; it never calls repository methods, so domain-layer read/write logic in `MonitorUserLocationUseCase`, `RecorderService`, etc. is completely unaware sync exists | Preserves the existing clean-architecture boundary: sync is a data-layer-adjacent concern, not a domain concern |
| Domain use cases ↔ `DownloadRegionAudioUseCase` | Triggered by the same `onRegionChange` callback the presentation layer already wires up from `MonitorUserLocationUseCase.start()` | No new coupling between `MonitorUserLocationUseCase` and the download use case — both are independent subscribers of the same existing event |

## Suggested Build Order

1. **`AppDatabase` safety fix** (backup-before-delete-on-open-failure; gate `recreateForTesting()`/`importDatabase()` behind explicit confirmation in `data_browser_page.dart`) — must land **first**, before any sync or geofencing work, because every subsequent stream (push, pull, download-apply) writes more data into this database and the stated highest-priority constraint is zero data loss.
2. **Real `SyncApi` HTTP implementation + wiring `RunSyncUseCase` to run on a schedule** (push only, reusing what's already captured in the outbox) — independent of geofencing, can start immediately after (1). Requires adding an HTTP client dependency (none present in `pubspec.yaml` today — `http` or `dio`) and a connectivity-change listener (`connectivity_plus` not present either).
3. **Local-only write primitive (`applyRemoteChange()`) + pull path** — build this once; it's a prerequisite for both sync-pull and area-download. Do this before area-download (step 7) so download doesn't invent its own ad hoc "write without outbox" shortcut.
4. **Hybrid geofencing replacement** (`RegionMonitor` + `RegionWindowSelector` + `GeofenceOrchestrator`, `native_geofence` dependency + native platform config) — independent of sync, can be built in parallel with (2)/(3) by a different work stream, but isolate this as its own phase given the platform/native-config risk; needs real-device testing on both Android and iOS, not just simulator/emulator.
5. **Rotating window logic** — depends on (4) existing (needs a `RegionMonitor` to attach to); can ship in the same phase as (4) or immediately after.
6. **Audio preload hook** — only depends on (1); the fine-trigger-distance loop it hooks into is untouched by the geofencing swap, so this can land any time after (1), independently of (4)/(5).
7. **Area-download hook** — structurally only needs the existing region-enter event (works with old `GeofenceBackgroundService` or new `GeofenceOrchestrator` equally), but functionally needs (3) (pull sync) to ever populate a non-null `remote_url` to download — sequence after (3).
8. **Debug/user-facing toggle** — orthogonal to all of the above, no dependencies, can land whenever.

## Sources

- Existing codebase (read directly): `lib/domain/usecases/monitor_user_location_usecase.dart`, `lib/core/services/geofence_background_service.dart`, `lib/core/background/background_poller.dart`, `lib/core/background/background_worker.dart`, `lib/data/sync/sync_api.dart`, `lib/data/sync/sync_api_stub.dart`, `lib/data/sync/sync_client.dart`, `lib/domain/usecases/run_sync_usecase.dart`, `lib/data/datasources/local/app_database.dart`, `lib/data/datasources/local/sync_local_data_source.dart`, `lib/data/repositories/geo_path_repository_impl.dart`, `lib/core/di/service_locator.dart`, `lib/core/services/audio_player_service.dart`, `lib/data/repositories/audio_playback_gateway_impl.dart`, `pubspec.yaml`
- [Geofencing iOS: Understanding the limitations — Radar](https://radar.com/blog/limitations-of-ios-geofencing) — confirms the 20-region hard cap and the "monitor only the nearest regions, update as the user moves" rotating-window pattern as the standard industry workaround, and that production SDKs typically use 17-20 of the available slots (headroom for other apps' regions is not the limiting factor — the 20 is purely per-app)
- [native_geofence — Flutter package (pub.dev)](https://pub.dev/packages/native_geofence) — confirms it wraps native `GeofencingClient`/`CLLocationManager`, works with the app fully closed, delivers events via a background callback requiring its own permission/battery-optimization handling — the basis for the "background isolate bootstrap" pattern noted above
- WebSearch (outbox pattern, offline-first conflict resolution) — general pattern confirmation only (idempotency keys, LWW-by-timestamp/version, outbox capture-then-drain); no single authoritative source, cross-checked against multiple results (Medium/engineering-blog tier — MEDIUM confidence, but the resulting design choice here is simple enough (server-authoritative, single-editor) that it doesn't depend on the more advanced CRDT/HLC material these sources also surfaced

---
*Architecture research for: offline-first sync + hybrid geofencing integration into an existing Flutter/SQLite app*
*Researched: 2026-08-08*
