# Feature Research

**Domain:** Offline-first mobile sync + geofence-triggered audio + area-based content pre-download (geolocated audio tour app)
**Researched:** 2026-08-08
**Confidence:** MEDIUM-HIGH (platform mechanics HIGH via official docs/well-documented SDK behavior; sync/download UX patterns MEDIUM via multiple converging sources, no single canonical spec)

## Feature Landscape

### Table Stakes (Users Expect These)

Features that, if missing or broken, make sync/background/download feel unreliable — directly maps to the bugs already observed in Cíngula ("detected zone but audio didn't play", polling battery drain, unidirectional sync).

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Push sync with idempotent writes | Outbox already exists; a retry that double-applies a write (dup audio_asset, dup trigger) is worse than no sync | LOW | Server dedupes by `uuid` + `logical_version`, not by "did I receive this HTTP call" — retries are inherently duplicate-prone over flaky connectivity |
| Pull sync actually invoked | `SyncApi.pullChanges()` exists but is dead code today — a sync that only pushes isn't bidirectional, it's a leak | MEDIUM | Single-editor model: pull = replace local row with server's latest (no local merge logic needed, confirmed in PROJECT.md constraints) |
| Retry with exponential backoff + jitter | Comarca Andina has intermittent signal; naive immediate-retry-in-a-loop drains battery and hammers the backend the moment signal returns | LOW | Cap max delay (~30s is the common industry default), jitter ±20-50% to avoid thundering-herd on reconnect, distinguish transient (5xx/timeout, retry) vs terminal (4xx, don't retry) errors |
| Visible, honest sync status | Users (or in v0, the one artist-user) need to know "did my change actually leave this phone" — a silent/fake "synced" checkmark that doesn't reflect real state erodes trust in the tool | LOW | Minimum viable: last-successful-sync timestamp + a pending-changes count from the outbox table (already queryable). "Synced" should mean "outbox empty AND last pull succeeded," not "app tried to sync" |
| Non-destructive local DB failure handling | Current code deletes and recreates the DB with no backup if `openDatabase` fails — this is the #1 data-loss risk named explicitly in PROJECT.md constraints | LOW-MEDIUM | Fix: on open failure, copy corrupt DB file aside before any recreate; never silently drop. This is a prerequisite gate for shipping *any* other sync work, since sync amplifies the blast radius of local data loss (a bad local write can now also get pushed) |
| Explicit confirmation on destructive debug actions | `recreateForTesting()` / `importDatabase()` are wired to real buttons with no confirmation — one misclick destroys the only copy of field recordings pre-sync | LOW | Confirmation dialog gate, independent of the user/debug toggle (already decided in Key Decisions) |
| Region-level detection via native OS geofencing | Continuous foreground-service polling (current approach) drains battery and doesn't survive app-kill reliably; this is the documented standard pattern (Google Tasks, Bixby Places, commercial SDKs like Radar all use native region monitoring, not polling, at the outer level) | MEDIUM | Android `GeofencingClient`: survives app kill, wakes the app, but checks on the order of minutes in background (`NOTIFICATION_RESPONSIVENESS` ~5 min is Google's own recommended default — sub-second responsiveness is not achievable this way). iOS `CLLocationManager` region monitoring: hard limit of 20 concurrent regions, and Apple's own docs describe boundary-crossing detection needing the user to move ~20m past the boundary and dwell ~20s before the callback fires — this is a platform floor, not a bug to "fix" |
| Fine-grained polling inside an active region for small-radius triggers | Native geofencing's multi-minute responsiveness and ~100-200m practical accuracy floor cannot reliably fire a 12m-radius trigger — this is very likely the root cause of "zone detected late/never, audio didn't play" for triggers specifically (region entry can use native geofencing; individual triggers cannot) | MEDIUM | Confirms the hybrid design already chosen in Key Decisions. The dead `BackgroundAdaptivePoller` code is a reasonable starting point to revive, not reinvent |
| iOS 19-region sliding window | CoreLocation's 20-region hard cap is non-negotiable Apple platform behavior, not a tunable setting — exceeding it silently drops registrations | MEDIUM-HIGH | Standard industry pattern (used by commercial geofencing SDKs): register the ~15-19 nearest regions/triggers to current position, re-evaluate and rotate the set as the user moves. Must reserve 1 slot of headroom below 20 for the rotation itself |
| Audio preload before trigger fires | `AudioPlayerService.loadPath()`/`setFilePath()` currently runs *at* trigger fire time — this is the concretely identified root cause of playback latency/failure, independent of the geofencing mechanism used | LOW-MEDIUM | Preload the nearest 1 (or nearest-N) trigger's audio file into the player as soon as its trigger becomes "candidate" (e.g. inside the region, within some lead distance) so `setFilePath()` latency is paid before the user arrives, not at the moment playback should start |
| Trigger-boundary debounce (dwell or hysteresis) | Firing exactly at the geometric boundary causes false triggers when GPS jitter puts the user's fix on the wrong side repeatedly (rapid enter/exit flapping), especially with 12m-radius triggers where GPS error (~5-15m typical) is comparable to the radius itself | LOW | Simple hysteresis (require N consecutive fixes inside radius, or a small dwell time) before firing; same principle as Android's `INITIAL_TRIGGER_DWELL` |
| Content download triggered on region entry, not at exact point-of-use | Requiring connectivity exactly at the geotrigger location is the opposite of what a rural walking-tour app needs — download must happen earlier, when signal is available (this is literally how VoiceMap, GuideAlong, Shaka Guide, and offline-map hiking apps like Gaia GPS/AllTrails all work: download-ahead, playback/use fully offline) | MEDIUM | The `onRegionChange` hook already exists and is the natural trigger point. Must handle "entered region but had no signal at that moment either" — retry the download opportunistically whenever connectivity returns, not just once at entry |
| Downloaded-content staleness invalidation | Server keeps latest + 1 previous version per entity (already decided); a phone that downloaded an old audio file and never re-checks will silently play stale content forever — this breaks the "server is source of truth" model the sync system is being built for | LOW-MEDIUM | Reuse the existing `logical_version`/`updated_at` fields already in the schema: on pull sync, if an `audio_asset` row's version changed and it was previously downloaded, mark it for re-download rather than trusting the stale local file |
| Resumable/retryable downloads | Downloads interrupted by walking out of signal range (the exact environment this app runs in) must not corrupt or silently half-write the audio file | LOW-MEDIUM | Download to temp file, atomic rename on completion; on failure, leave the previous good file in place and retry later rather than leaving a partial file marked as "available" |

### Differentiators (Not Required for This Milestone)

Reasonable, sometimes seen in comparable apps, but explicitly not needed for a single-editor v0 per PROJECT.md constraints. Worth naming so they don't get built accidentally.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Predictive multi-trigger preload (preload next N along the path, not just nearest) | Smoother experience on paths with closely-spaced triggers | MEDIUM | Nearest-1 preload already solves the identified root cause; only worth it if closely-spaced triggers become common |
| Adaptive trigger radius based on live GPS accuracy | Reduces false triggers/misses when GPS accuracy is poor (tree cover, canyon) | MEDIUM-HIGH | The commented-out `BackgroundAdaptivePoller` trend logic is a reasonable seed for this later; not required to fix the current bug |
| Wi-Fi-only download preference / cellular data guard | Common in media/hiking apps (avoids surprise data charges) | LOW | Lower priority here — Comarca Andina connectivity is scarce in general (any signal, not specifically Wi-Fi vs cellular), so "download whenever any signal is available" matters more than distinguishing the transport |
| Storage quota management / auto-eviction of old downloaded audio | Prevents unbounded on-device storage growth as regions/content grow | LOW-MEDIUM | Not urgent at current single-region, single-artist content volume; revisit if regions/audio catalog grows significantly |
| Real-time/instant sync (push notifications on server change) | Feels more "live" than periodic sync | HIGH | No user waiting on the other end yet (no web editor exists this milestone) — nothing to be "live" against |

### Anti-Features (Would Be Over-Engineering Here)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|------------------|-------------|
| Multi-editor conflict resolution (CRDTs, 3-way merge, operational transform) | Feels like the "proper" way to build sync | Explicitly out of scope per PROJECT.md (single editor, RNF-02); CRDT/OT machinery is real complexity that solves a concurrency problem this app doesn't have | Server keeps latest + 1 previous version; phone always replaces with server's latest on pull. Last-write-wins is not a compromise here, it's the correct design for one editor |
| Unlimited server-side version history / audit log | "Never lose a version" instinct | Explicitly decided against in Key Decisions (storage growth, not needed for one editor's use case) | Keep only current + 1 previous per entity, as already decided |
| Always-on fine-grained background polling everywhere (current behavior) | "Just poll constantly, it's simple and always accurate" | This is the actual cause of today's battery drain; simple to write, expensive to run, and doesn't even fix the reliability problem (accuracy isn't the issue, wake-reliability and continuous cost are) | Hybrid: native OS geofencing at region level (survives kill, low power) + fine polling only inside the currently-active region |
| Build flavors (user vs debug) | Common Flutter pattern for separating debug tooling from prod | Already decided against — v0 has one person filling both roles (field recorder + end-user tester); flavors add build/release complexity for a distinction that doesn't exist yet | Runtime toggle, destructive actions gated by confirmation regardless of toggle state (already decided) |
| Optimistic "always shows synced" UI | Looks cleaner, avoids showing errors to the user | Actively harmful here — masks exactly the class of bug this milestone exists to prevent (silent data loss/divergence). A UI that always says "synced" when it isn't is worse than no status indicator | Show real state: pending count + last-successful-sync timestamp, surface sync errors with retry, even if it's not pretty |
| Real-time bidirectional sync (websocket push) | Feels modern | No counterpart yet to push *from* (no web editor this milestone) — pure speculative infrastructure for a client that doesn't exist | Periodic/triggered sync (on app foreground, on connectivity regained, on manual trigger) is sufficient until the web editor exists |

## Feature Dependencies

```
Non-destructive DB failure handling
    └──blocks──> Push sync (unsafe to sync from a DB that might get silently wiped)
                     └──blocks──> Pull sync (pulling into a DB with unverified integrity compounds risk)

Pull sync (SyncApi.pullChanges() actually invoked)
    └──required by──> Downloaded-content staleness invalidation (needs to know server version changed)
    └──required by──> Content download-by-region (needs real remote_url from server, not null)

Region-level native geofencing (region entry/exit detection)
    └──required by──> Content download trigger (onRegionChange hook)
    └──enables──> Fine-grained in-region polling (only runs once a region is confirmed active)

Fine-grained in-region polling
    └──required by──> Audio preload (need to know a trigger is "coming up" before it fires)
    └──required by──> Trigger-boundary debounce (dwell logic needs continuous fixes, not native geofence callbacks)

Audio preload ──depends on──> Content already downloaded to device (can't preload what isn't local yet)

iOS 19-region sliding window ──constrains──> Region-level native geofencing (implementation detail of it on iOS specifically, not a separate feature)
```

### Dependency Notes

- **DB safety blocks all sync work:** shipping push/pull sync on top of a DB that can silently wipe itself on open failure means sync becomes a vector for *amplifying* data loss (a corrupted-then-recreated empty DB would push "everything deleted" to the server). This has to land first.
- **Pull sync unlocks both download-by-region and staleness invalidation:** `remote_url` is already in the schema but always null today because nothing populates it — pull sync is the thing that would populate it from the server.
- **Region detection is the gate for the download trigger:** the `onRegionChange` hook already exists in `geofence_background_service.dart`; download-by-region is additive logic hung off an existing hook, not a new detection mechanism.
- **Preload depends on download:** preloading audio into the player only helps if the file is already on disk — for a region visited for the first time with no signal, preload has nothing to preload. Download-by-region is a prerequisite for preload actually eliminating latency in the field, though preload also helps independently once content is present (e.g. re-visiting an already-downloaded region).

## MVP Definition

Framed for this milestone's scope (a phase of an existing app, not a 0-to-1 product), per PROJECT.md Active requirements.

### Launch With (this milestone)

- [ ] Non-destructive DB failure handling + confirmation-gated destructive debug actions — highest-priority constraint, blocks everything else
- [ ] Push sync via existing outbox against a real backend, idempotent, with backoff+jitter retry
- [ ] Pull sync actually invoked (bidirectional, replace-with-latest semantics)
- [ ] Honest sync status surfaced somewhere in the UI (pending count + last-sync timestamp)
- [ ] Region-level native geofencing (Android `GeofencingClient` / iOS `CLLocationManager`, e.g. via `native_geofence`) replacing continuous foreground polling
- [ ] iOS ~19-region sliding window
- [ ] Fine-grained in-region polling retained for small-radius trigger accuracy
- [ ] Trigger-boundary debounce/hysteresis
- [ ] Audio preload of nearest trigger ahead of arrival
- [ ] Content download-on-region-entry with opportunistic retry when signal returns
- [ ] Resumable/atomic downloads (no half-written audio files)
- [ ] Downloaded-content staleness invalidation tied to `logical_version`
- [ ] Runtime user/debug toggle (not build flavors)

### Add After Validation (once this milestone's sync/background pipe is proven solid)

- [ ] Web editor UI (RF-02) — explicitly deferred, depends on this milestone's backend/API existing and being trustworthy
- [ ] Predictive multi-trigger preload — add if closely-spaced triggers on real paths make nearest-1 preload insufficient
- [ ] Storage quota management — add once content volume across regions grows enough to matter

### Future Consideration (v2+, multi-user era)

- [ ] Multi-editor conflict resolution — only relevant once the system is genuinely multi-editor (v1 of the ERS), not before
- [ ] Real-time push sync — only relevant once there's a live counterpart (web editor) to sync against in real time

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Non-destructive DB failure handling | HIGH | LOW | P1 |
| Push sync (idempotent, backoff+jitter) | HIGH | LOW-MEDIUM | P1 |
| Pull sync invoked | HIGH | MEDIUM | P1 |
| Sync status visibility | MEDIUM | LOW | P1 |
| Region-level native geofencing | HIGH | MEDIUM | P1 |
| iOS 19-region sliding window | HIGH (blocking on iOS specifically) | MEDIUM-HIGH | P1 |
| Fine-grained in-region trigger polling | HIGH | MEDIUM | P1 |
| Audio preload | HIGH | LOW-MEDIUM | P1 |
| Trigger-boundary debounce | MEDIUM | LOW | P1 |
| Content download-on-region-entry | HIGH | MEDIUM | P1 |
| Resumable downloads | MEDIUM | LOW-MEDIUM | P1 |
| Staleness invalidation | MEDIUM | LOW-MEDIUM | P1 |
| Runtime user/debug toggle | LOW-MEDIUM | LOW | P1 |
| Predictive multi-trigger preload | LOW-MEDIUM | MEDIUM | P3 |
| Storage quota management | LOW | LOW-MEDIUM | P3 |
| Wi-Fi-only download guard | LOW | LOW | P3 |
| Multi-editor conflict resolution | NONE (v0) | HIGH | Not planned |
| Real-time push sync | LOW (no counterpart yet) | HIGH | Not planned |

**Priority key:**
- P1: Must have for this milestone
- P3: Nice to have, future consideration
- Not planned: Explicitly out of scope per PROJECT.md constraints

## Competitor / Comparable-App Feature Analysis

| Feature | GuideAlong / VoiceMap / Shaka Guide (audio tours) | Gaia GPS / AllTrails (hiking, offline maps) | Google Tasks geo-reminders / Bixby Places | Our Approach |
|---------|------|------|------|--------------|
| Content availability offline | Download tour (audio + maps) fully before the trip; plays with zero data once downloaded | Download map tiles for a chosen area ahead of time; usage limits per map source (e.g. ~100k tiles / ~2GB per download batch) | N/A (reminders are small payloads, not media) | Download-by-region on signal availability, not requiring pre-trip manual download step, since the artist/user is often already in the field |
| Trigger mechanism | GPS-triggered playback, no signal required at trigger point | N/A (maps are passive, not trigger-based) | OS-native geofencing (region monitoring), same platform APIs as this app | Hybrid: native region-level geofencing + fine polling for small-radius triggers, for the reasons detailed above |
| Sync direction | One-way (publisher → app); no user-generated content synced back | One-way (map tiles are read-only downloads) | One-way (reminder created on one device, fires wherever) | Bidirectional (this app's user *creates* content in the field, unlike tour-consumption apps) — this is the genuinely novel part of this milestone, not something to copy from these comparables |

## Sources

- [ObjectBox — Customizable conflict resolution for offline-first apps](https://objectbox.io/customizable-conflict-resolution-for-offline-first-apps/) — MEDIUM confidence, vendor blog but consistent with broader pattern
- [Offline-First | Outbox, Idempotency & Conflict Resolution](https://www.educba.com/offline-first/) — MEDIUM confidence
- [GitHub: Geofencing Events Not Triggering in Android Killed State (flutter_background_geolocation #1240)](https://github.com/transistorsoft/flutter_background_geolocation/issues/1240) — MEDIUM confidence (real-world issue reports, corroborates official docs' latency caveats)
- [Apple Developer Forums: Geofencing Event Not Triggering When App Killed](https://developer.apple.com/forums/thread/773861) — MEDIUM confidence
- [Radar — Geofencing iOS: Understanding the limitations](https://radar.com/blog/limitations-of-ios-geofencing) — MEDIUM-HIGH confidence (commercial geofencing SDK vendor, technically detailed, consistent with Apple's own documented behavior)
- [Apple Developer Forums: What is the true radius of a Geofence?](https://developer.apple.com/forums/thread/94091) — MEDIUM confidence, corroborated by multiple independent reports of ~100-200m practical floor
- [Android Developers — Create and monitor geofences](https://developer.android.com/develop/sensors-and-location/location/geofencing) — HIGH confidence (official docs)
- [Android Developers — Optimize location use for real-world scenarios](https://developer.android.com/develop/sensors-and-location/location/battery/scenarios) — HIGH confidence (official docs)
- [Gaia GPS Help — Individual Offline Map Tile Limits](https://help.gaiagps.com/hc/en-us/articles/360000915488-Individual-Offline-Map-Tile-Limits) — HIGH confidence (vendor's own support docs)
- [AllTrails Support — Download custom areas for offline use](https://support.alltrails.com/hc/en-us/articles/37758009767444-Download-custom-areas-for-offline-use) — HIGH confidence (vendor's own support docs)
- [VoiceMap](https://voicemap.me/), [GuideAlong](https://guidealong.com/), [Shaka Guide](https://play.google.com/store/apps/details?id=com.shakaguide.android) — app store / marketing descriptions, MEDIUM confidence for stated behavior (download-ahead, offline GPS playback), not independently verified via testing
- [Google for Developers — Design Guidelines for Offline & Sync (Open Health Stack)](https://developers.google.com/open-health-stack/design/offline-sync-guideline) — HIGH confidence (official Google design guidance)
- Exponential backoff/jitter sources (Presidio, Baeldung, oneuptime.com) — MEDIUM confidence, converging industry consensus on jitter + capped delay + idempotency, no single authoritative spec but broad agreement across independent sources

---
*Feature research for: offline-first sync + geofence-triggered audio + area-based content download (geolocated audio tour app)*
*Researched: 2026-08-08*
