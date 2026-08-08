# Stack Research

**Domain:** Offline-first bidirectional mobile sync (Flutter/SQLite ↔ Postgres) + hybrid native/polling background geofencing
**Researched:** 2026-08-08
**Confidence:** MEDIUM-HIGH (sync backend verified against current docs/pricing; geofencing plugin verified against pub.dev; hand-rolled protocol choice is a project-specific judgment call, not an external "standard")

## Context this builds on

The app already has a hand-rolled, cursor-based push/pull sync protocol scaffolded and partially wired:
- Local: `sqflite` with `sync_outbox` / `sync_state` tables, `uuid`/`updated_at`/`deleted_at`/`logical_version` columns already on every syncable entity.
- Contract: `SyncApi` (`lib/data/sync/sync_api.dart`) with `pushOutbox()`, `fetchState()`, `pullChanges({cursor})`, currently backed by `SyncApiStub`.
- Client: `RunSyncUseCase` already does batch push + ack + attempt-counting; `ApiConfig` already defines `/sync/push`, `/sync/state`, `/sync/changes` endpoints and a `--dart-define`-driven base URL.

This is not a greenfield decision. The stack below is chosen to fill in the missing pieces (real backend + real HTTP client + real hybrid geofencing) **without discarding this existing protocol**, per the milestone constraint.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Neon (managed Postgres, serverless) | current (2026) | Backend datastore | Free tier (0.5GB storage, 100 CU-hrs/month, scale-to-zero) covers a single-editor workload at $0/month indefinitely; post-Databricks-acquisition pricing cuts (storage $0.35/GB-mo) make paid tiers cheap if outgrown. Scale-to-zero means no idle cost, which fits "low budget, intermittent connectivity, single user" exactly — you're not paying for uptime nobody needs. Confidence: MEDIUM (pricing verified via multiple 2026 comparison sources, not an official pricing page fetch). |
| Vercel Functions (Node.js/TypeScript serverless) | Hobby tier | Thin HTTP API implementing the existing `/sync/push`, `/sync/state`, `/sync/changes` contract | The app already speaks a *custom* protocol (batched outbox push with ack ids, cursor-based pull, server keeps current+1-previous version) — this is not generic table CRUD, so a PostgREST-style auto-API doesn't fit without a lot of custom SQL/RPC anyway. A few serverless functions are the smallest thing that can implement custom business logic (conflict resolution, version pruning) directly in SQL/TS. Free Hobby tier + pay-per-invocation means near-zero cost for a single editor's request volume. No server to patch/monitor — important since there's no ops budget. Confidence: MEDIUM. |
| `@neondatabase/serverless` (Neon's HTTP/WebSocket driver) | current | DB access from Vercel functions | Classic `pg` TCP connections don't pool well in serverless (each invocation = new connection = exhausts Postgres connection limits fast). Neon's HTTP driver is built for exactly this serverless-function-per-request pattern. Confidence: MEDIUM (Neon + Vercel official integration, verified via search). |
| `native_geofence` (Flutter) | ^1.3.1 | Region-level (coarse) geofencing using real OS APIs | MIT-licensed, actively maintained (updated within last 2 months as of research date), wraps `GeofencingClient` (Android) and `CLLocationManager` region monitoring (iOS) directly — matches the exact requirement already identified in PROJECT.md. Confirmed: works in foreground/background/terminated, geofences persist across Android reboot, has built-in Android foreground-service support for triggering heavier work on region enter. This is the plugin to standardize on to replace `geofence_service`. Confidence: HIGH (verified on pub.dev directly, matches prior project research). |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `http` | ^1.6.0 | HTTP client for `SyncApi` implementation and audio-asset downloads | Official Dart-team package, not currently in `pubspec.yaml`. Chosen over `dio`: the sync protocol is 3 simple JSON endpoints with retry/backoff logic already handled by the outbox's `markAttempt` counter — `dio`'s interceptor/cancellation machinery is unused complexity here. Add only `http`, not `dio`. |
| `connectivity_plus` | ^7.3.1 | Skip sync attempts when there's clearly no network interface up | Not a replacement for real error handling (it reports interface type, not actual internet reachability — verified from its own docs) — use it only as a cheap pre-check to avoid pointless wake-ups/battery drain in the intermittent-connectivity zones (Lago Puelo), not as the source of truth for "did the request succeed." Keep existing `markAttempt`/retry logic as the real reliability mechanism. |
| `geolocator` | ^14.0.2 (already in pubspec) | Fine-grained polling for small-radius trigger detection *inside* an active region | Already a dependency — no new library needed for the "polling fine dentro de región activa" half of the hybrid design. Use its position stream with a distance filter, driven by a foreground service/notification while a region is active, not `geofence_service`'s always-on polling loop. |
| `flutter_local_notifications` + `workmanager` + `wakelock_plus` | already in pubspec | Foreground-service/background-task plumbing for the fine-polling phase on Android | Already present — reuse for the "polling fino" leg instead of adding a new background-execution library. The dead `BackgroundAdaptivePoller` code referenced in PROJECT.md is a legitimate starting point to revive/adapt for this phase, not a new build. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Neon branching (dev/preview branches) | Isolated Postgres branch per feature/test run | Free tier includes up to 10 branches — use one as a scratch DB for sync-protocol integration tests instead of standing up local Postgres via Docker. |
| Vercel CLI (`vercel dev`) | Local emulation of the serverless API during development | Lets the Flutter app point `CINGULA_API_BASE_URL` at `http://localhost:3000` (already the default in `ApiConfig`) while iterating, no deploy needed per change. |

## Installation

```bash
# Flutter side — add to pubspec.yaml
flutter pub add http connectivity_plus native_geofence

# Remove once native_geofence is wired in and validated
flutter pub remove geofence_service

# Backend side (new small repo/directory, Node/TS)
npm install @neondatabase/serverless
npm install -D typescript @vercel/node
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| Hand-rolled sync API (Vercel Functions + Neon) on top of the existing outbox protocol | PowerSync (managed SQLite↔Postgres sync engine) | PowerSync is genuinely excellent for offline-first Flutter (real-time Postgres→SQLite streaming, built-in conflict handling, free tier up to 2GB/month synced) — but it requires adopting **its own** client-side SQLite wrapper and sync-rules schema, replacing direct `sqflite` usage and the already-built outbox/cursor protocol. That's a rewrite of the local data layer this milestone explicitly wants to avoid. Reconsider PowerSync if/when the project moves to multi-user/multi-device sync (v1 of the ERS), where hand-rolling conflict resolution gets much harder and the migration cost is justified. |
| Hand-rolled sync API | ElectricSQL | Similar tradeoff to PowerSync — a real sync engine, but requires its own client integration and Postgres logical-replication setup. Overkill for a single-editor, low-volume use case; revisit only at multi-editor scale. |
| Vercel Functions | Self-hosted VPS (Fly.io, Railway, etc.) | Fly.io's free tier was discontinued in 2024 (now trial credits only, ~$2-8/month minimum for an always-on machine); a VPS only makes sense if the API needs long-running processes (it doesn't — push/pull are short request/response cycles) or if data residency/self-hosting is a hard requirement later. |
| Neon | Supabase | Supabase bundles Auth/Storage/Realtime/Edge Functions behind a platform fee ($25/mo Pro) and free projects pause after 7 days of inactivity — worse fit for a low-traffic single-editor app than Neon's true scale-to-zero pricing. Reconsider Supabase if the future web-editing UI (out of scope this milestone) ends up needing built-in auth/storage — bundling could then be cheaper than assembling those pieces separately. |
| `native_geofence` | `geofence_service` (current dependency) | Never — this is the package being replaced. It implements continuous polling in a foreground service, which is exactly the battery drain this milestone exists to fix. Keep it only until the region-level migration is validated, then remove. |
| `native_geofence` | `geofence_foreground_service`, `flutter_geofence`, `geofencing_flutter_plugin` | These are older/less-maintained polling-based or thin wrappers found during the same pub.dev search; none matched "real native OS geofencing, actively maintained, terminated-app support" as cleanly as `native_geofence`. Don't switch without a specific unmet need. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|--------------|
| PostgREST / Supabase auto-generated REST API as the sync transport | The sync protocol needs server-side logic (batch ack by client-generated id, cursor-based change feed ordered by a server sequence, pruning to current+1-previous version) that a generic table-CRUD API can't express without stored procedures/RPC anyway — at that point you're writing custom backend code regardless, so skip the extra abstraction layer. | A few explicit serverless functions (Vercel) with hand-written SQL for exactly these operations. |
| `dio` for the sync HTTP client | Adds interceptor/cancellation-token surface area unused by 3 simple JSON endpoints whose retry logic already lives in the outbox (`markAttempt`). | `http` package. |
| PowerSync/ElectricSQL for this milestone | Both require replacing the local SQLite access layer and the already-built outbox/cursor protocol — a rewrite the milestone explicitly wants to avoid, for a single-editor use case where hand-rolled LWW is sufficient. | Hand-rolled protocol + thin serverless API (recommended above). Revisit at multi-editor scale. |
| Self-hosted always-on VPS as the default choice | No free tier remains among mainstream providers in 2026 (Fly.io in particular removed theirs); adds ops burden (patching, monitoring, backups) with no budget for it, for a workload with no long-running-process requirement. | Vercel Functions (serverless, $0 at this scale). |
| `geofence_service` package going forward | It is a polling-loop-in-a-foreground-service implementation — architecturally the opposite of "native OS geofencing," and the documented root cause of the battery drain this milestone is meant to fix. | `native_geofence` for region-level detection; `geolocator` polling only while inside an active region. |
| Relying on `connectivity_plus` status to decide whether a sync push "succeeded" | Its own docs state it reports network interface type, not actual internet reachability (e.g. reports "connected" on a WiFi captive portal with no real internet). | Treat actual HTTP request success/failure as the source of truth; use `connectivity_plus` only as a cheap early-exit heuristic before attempting sync. |

## Stack Patterns by Variant

**If the future web-editing UI (next milestone) needs built-in auth/file storage:**
- Reconsider Supabase over Neon+Vercel at that point, since the bundled Auth/Storage could offset its higher platform fee.
- Because: this milestone's low-cost win (Neon scale-to-zero) assumes no auth/storage service is needed yet — that assumption may not hold once a second, less-trusted actor (a public web UI) exists.

**If sync volume/users grow beyond single-editor:**
- Reconsider PowerSync or ElectricSQL instead of extending the hand-rolled protocol's conflict resolution.
- Because: LWW-with-1-previous-version is intentionally simple for one editor (RNF-02 in the ERS); real multi-editor conflict resolution is a different, harder problem those tools solve out of the box.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `native_geofence` ^1.3.1 | Android API 23+, iOS 14+ | Matches existing `min_sdk_android: 21` in `pubspec.yaml`'s `flutter_launcher_icons` config only loosely — verify/raise `minSdkVersion` in `android/app/build.gradle.kts` to 23 if not already, since the app's launcher-icon min_sdk (21) is unrelated to the actual Gradle `minSdkVersion` the plugin needs. |
| `native_geofence` | Kotlin ≥1.9.25, Gradle 8+ | Per package docs, Flutter + Kotlin 2.x had compatibility issues as of Jan 2025; pin Kotlin in the 1.9.x line unless already validated otherwise on a current Flutter/AGP version. |
| `@neondatabase/serverless` | Vercel serverless functions (classic, non-Fluid Compute) | If Vercel's newer "Fluid Compute" mode is used instead, connection pooling via `pg` + PgBouncer (port 6432) becomes viable too — but the HTTP driver is the simpler default and works in both modes. |
| `sqflite` ^2.3.3+1 (existing) | No change needed | Confirmed still the local DB layer; this stack adds a remote counterpart without touching it. |

## Sources

- https://pub.dev/packages/native_geofence — version, license, platform support, terminated-app behavior (fetched directly)
- https://pub.dev/packages/http — latest version (fetched directly)
- https://pub.dev/packages/connectivity_plus — latest version, reachability caveat (fetched directly)
- https://powersync.com/pricing — free tier limits, confirms PowerSync viable but architecturally distinct (fetched directly)
- WebSearch "Supabase vs Neon low cost single user Postgres 2026 pricing free tier" — multiple 2026 comparison articles (designrevision.com, agentdeals.dev, closefuture.io) cross-checked for free-tier terms — MEDIUM confidence (aggregated, not official pricing page)
- WebSearch "Fly.io free tier 2026 discontinued pricing minimum cost VPS" — multiple 2026 sources confirming free tier removal — MEDIUM confidence
- WebSearch "Vercel serverless function Neon Postgres HTTP driver free tier 2026" — confirms official Neon↔Vercel integration and HTTP-driver rationale for serverless — MEDIUM confidence
- Existing codebase (`lib/data/sync/sync_api.dart`, `sync_client.dart`, `run_sync_usecase.dart`, `pubspec.yaml`) — read directly to determine what's already built vs. what's missing

---
*Stack research for: Offline-first mobile sync + hybrid background geofencing (Cíngula App milestone)*
*Researched: 2026-08-08*
