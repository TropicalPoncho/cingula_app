# Phase 2: Backend Real + Push Sync - Research

**Researched:** 2026-08-29
**Domain:** Serverless HTTP API (Vercel Functions + Neon Postgres) implementing an existing client-defined outbox-push protocol; Flutter-side HTTP client, auto-trigger wiring, retry/backoff.
**Confidence:** HIGH (stack versions, driver APIs, backoff algorithm all verified against current sources). MEDIUM on exact backend SQL schema (design choice, not verified against an existing implementation) and on the outbox `last_attempt_at` gap (a genuine, newly-discovered schema hole, not a documented pitfall).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Phase Boundary
Esta fase reemplaza `SyncApiStub` por un backend real que implementa el contrato de outbox ya existente (`SyncApi.pushOutbox`), con push automático (no manual), reintentos con backoff exponencial + jitter, autenticación mínima por API key, dedupe idempotente por `uuid`+`logical_version`, versionado limitado (actual + 1 anterior) en el servidor, y estado de sync honesto visible en el panel de debug. **Pull sync (`SyncApi.pullChanges`) queda fuera de esta fase — es Fase 3.**

### Locked Decisions
- **D-01 (Hosting):** Neon (Postgres serverless, scale-to-zero) + Vercel Functions. Already researched and confirmed in `CLAUDE.md`. Do not re-litigate Supabase/VPS/PowerSync/ElectricSQL alternatives.
- **D-02 (Auth):** Static API key, fixed at compile time via `--dart-define`, same pattern as `ApiConfig._defaultBaseUrl` (`String.fromEnvironment`). No login, no rotation.
- **D-03 (401 handling):** A 401 (invalid auth) is a **terminal** error — do NOT retry with the normal backoff. It's a config problem (wrong key baked into the build). The outbox stays pending until the key is fixed; the attempt is logged.
- **D-04 (Auto push on write):** Push fires automatically immediately after every local write that generates an outbox row (recording a geo_path, trigger, audio, etc.) — not only on manual demand as today.
- **D-05 (Auto push on reconnect):** In addition to D-04, a push is retried when connectivity is restored. `connectivity_plus` is used only as the cheap pre-check CLAUDE.md already recommends — never as the source of truth for "did the push succeed."
- **D-06 (Manual button stays):** The manual "Push outbox (stub)" button in `DiagnosticsPanel` (already wired to `RunSyncUseCase.pushOutboxOnce`) stays as a debug fallback to force a push. It is not a destructive action, so the Phase 1 precedent of removing destructive debug actions does not apply.

### Claude's Discretion
- Exact backoff curve (base, cap, attempt ceiling before "temporarily stopped") — implement the industry-standard pattern, informed by the existing `attempt_count` column on `sync_outbox`.
- Exact server-side idempotent dedupe mechanism for `uuid`+`logical_version` (SYNC-02) — SQL implementation detail.
- Exact auth header format (`Authorization: Bearer <token>` vs `X-API-Key`) — pick whichever is simplest to implement in Vercel Functions.
- How the "push immediately after write" hook connects to the four local data sources without over-coupling — evaluate during research/planning.

### Deferred Ideas (OUT OF SCOPE)
- Pull sync (`SyncApi.pullChanges`, SYNC-04/SYNC-05) — explicitly Phase 3.
- Reconsidering destructive DB admin actions now that sync is a real safety net — mentioned in Phase 1 (D-05 of `01-CONTEXT.md`) as something to revisit "once sync works," but that's at the close of this phase or later, not a decision to make before building the backend.
- Sync status visibility in end-user mode (currently debug-panel-only per Phase 1's D-10) — not discussed, assumed to stay debug-only.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SYNC-01 | Backend real implementa el contrato de outbox (push), reemplazando `SyncApiStub` | Architecture Patterns (Vercel Functions structure), Code Examples (`/api/sync/push.ts`) |
| SYNC-02 | Push idempotente — dedupe por `uuid`+`logical_version`, ack por fila individual | Architecture Patterns (versioned upsert SQL), Common Pitfalls (delete-op payload gap) |
| SYNC-03 | Backoff exponencial + jitter, distinguiendo transitorio vs terminal | Architecture Patterns (Full Jitter formula + `last_attempt_at` gating), Common Pitfalls (no polling loop, no `last_attempt_at` column yet) |
| SYNC-06 | Backend guarda estado actual + 1 versión anterior, sin historial ilimitado | Architecture Patterns (single versioned-upsert table design) |
| SYNC-07 | Backend exige autenticación mínima (API key/bearer) | Architecture Patterns (auth middleware), Code Examples |
| SYNC-08 | UI muestra pendientes reales + timestamp último sync exitoso, nunca falso "todo sincronizado" | Runtime State Inventory / Code Context (DiagnosticsPanel already mostly satisfies this — gap is only auth-error visibility) |
</phase_requirements>

## Summary

This phase is almost entirely a "fill in the blank behind an existing interface" job. `SyncApi` (contract), `SyncClient` (outbox wrapper), `RunSyncUseCase` (push orchestration), and `DiagnosticsPanel` (status display + manual trigger) already exist and work end-to-end against `SyncApiStub`. Nothing in the Flutter app needs re-architecting — the work is (1) write a real `SyncApi` implementation using `package:http` against a new Vercel Functions + Neon backend, (2) make the push fire automatically instead of only on button-press, and (3) add retry/backoff and terminal-error handling around the existing `markAttempt`/`attempt_count` plumbing.

The single most important code-reading finding: **all four local data sources funnel every outbox-producing write through one shared method, `SyncLocalDataSource.enqueueOutbox()`.** This is the correct hook point for D-04's "push automatically after every write" — there is no need to touch `AudioLocalDataSource`, `GeoTriggerLocalDataSource`, `GeoPathLocalDataSource`, or `RegionLocalDataSource` individually. Wire the auto-push trigger once, in `enqueueOutbox` (or immediately after its callers return, via a thin wrapper/callback), not in sixteen+ call sites across four files.

Two gaps were found by reading the code that the plan must account for, neither obvious from the requirements text alone:
1. **Delete-op outbox payloads don't carry `logical_version`.** `GeoTriggerLocalDataSource.deleteOrphaned/deleteByAudioAssetId` and `GeoPathLocalDataSource.deleteByAudioAssetId/deleteById` enqueue delete rows with payloads like `{'reason': 'orphan_geo_path'}` — no version info. A version-keyed idempotent upsert (SYNC-02/SYNC-06) needs a version number for every op, including deletes.
2. **`sync_outbox` has `attempt_count` but no timestamp of the last attempt.** True exponential backoff (SYNC-03) needs to know *when* to retry, not just *how many times* it's been tried. Since this app has no polling/timer loop (push is purely event-triggered: on-write, on-reconnect, or manual), the natural fix is a schema column (`last_attempt_at`) used to gate whether a pending row is "eligible" to be sent on the next trigger — not a new timer.

**Primary recommendation:** Build a single generic `synced_entities` table in Neon (not four mirrored relational tables) keyed by `(table_name, record_uuid)`, storing `current_version`/`current_payload` plus `previous_version`/`previous_payload` as JSONB, updated via one atomic `INSERT ... ON CONFLICT ... DO UPDATE` per outbox row, executed as a batch via `sql.transaction()`. Add `Authorization: Bearer <token>` auth checked with `crypto.timingSafeEqual`. Distinguish 401 (terminal, no backoff) from network/5xx (transient, Full Jitter backoff) in the Flutter client. Hook auto-push into `SyncLocalDataSource.enqueueOutbox`, gated by a new `last_attempt_at` column plus `connectivity_plus` as a cheap pre-check.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `http` (Dart) | ^1.6.0 (verified current, published 2025-11-10) | HTTP client for `SyncApiHttp` | Already the CLAUDE.md-mandated choice over `dio`; ships `package:http/testing.dart` `MockClient` for free — no extra test-mocking dependency needed. |
| `connectivity_plus` | ^7.3.1 (verified current, published 2026-07-23) | Pre-check before attempting a push; trigger for D-05 reconnect-retry | CLAUDE.md-mandated. v7.x API returns `List<ConnectivityResult>` (not a single value) from both `checkConnectivity()` and `onConnectivityChanged` — verified against pub.dev docs directly, this is a breaking-change trap if coded from stale memory. |
| `@neondatabase/serverless` | ^1.1.0 (verified current) | Neon HTTP driver from Vercel Functions | CLAUDE.md-mandated. `neon()` gives a tagged-template query function over HTTPS; `sql.transaction([...])` runs a **dynamic-length array** of independently-parameterized queries as one non-interactive transaction — exactly what's needed to batch-upsert N outbox rows atomically per request. |
| `@vercel/node` types | ^10.0.0 (verified current) | Type defs for `VercelRequest`/`VercelResponse` in the legacy Node handler style | Only needed for TypeScript editor/type-checking; not a runtime dependency requirement. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `vercel` CLI | ^59.10.0 (verified current) | `vercel dev` local emulation, `vercel env add` | Already in CLAUDE.md's Development Tools; confirms current version for the plan's setup steps. |
| `node:crypto` (built-in) | Node 24 LTS (Vercel's current GA runtime, verified via Vercel docs, last_updated 2026-08-11) | `timingSafeEqual` for constant-time API key comparison | Avoid a naive `===` string compare on a secret — built into Node, zero new dependency. |
| `node:test` (built-in) | Node 24 LTS | Backend unit tests (auth check, upsert-SQL-building helpers) | Zero-dependency choice for ~3 small serverless functions; don't add Jest/Vitest for this scope. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Generic `synced_entities` table (table_name, record_uuid, current/previous payload JSONB) | Four mirrored Postgres tables (`audio_assets`, `geo_triggers`, `geo_paths`, `regions`) with real columns | Mirrored tables would need 4x the DDL/migrations and per-table upsert SQL for zero benefit in this phase (no server-side querying by column happens until Phase 3 pull, which can filter by `updated_at`/cursor on the generic table just as well). Reconsider only if a future phase needs server-side relational queries (e.g. "which regions have unsynced triggers") that a JSONB blob can't express cheaply. |
| `neon()` HTTP driver + `sql.transaction()` | `Pool`/WebSocket driver (session-based, full interactive transactions) | Only needed for multi-statement transactions with app-level control flow (e.g. "if X then Y") between statements. The chosen upsert design is a single atomic SQL statement per row (all conditional logic lives in SQL `CASE`/`WHERE`), so the simpler HTTP driver with batched `sql.transaction()` is sufficient. |
| `Authorization: Bearer <token>` | `X-API-Key: <token>` custom header | Functionally equivalent effort in a Vercel handler (`request.headers['x-api-key']` vs `.authorization`). Bearer chosen as the more broadly recognized REST convention; no functional reason to prefer one over the other for this phase. |
| Schema column (`last_attempt_at` on `sync_outbox`) for backoff gating | A `Timer`/polling loop that re-checks the outbox on an interval | A polling loop is exactly the battery-drain pattern this whole milestone (see GEO-01/`geofence_service` removal) exists to eliminate. Since sync is already purely event-triggered (write, reconnect, manual), gating "is this row eligible yet" on a stored timestamp needs no new background execution machinery. |

**Installation:**
```bash
# Flutter side
flutter pub add http connectivity_plus

# Backend (new directory, e.g. backend/ or api/ at repo root, Node/TS)
npm init -y
npm install @neondatabase/serverless
npm install -D @vercel/node typescript
```

## Architecture Patterns

### Recommended Project Structure (backend)
```
backend/                          # new directory (or repo root /api if backend lives standalone)
├── api/
│   ├── sync/
│   │   ├── push.ts               # POST /sync/push — batch upsert + ack
│   │   ├── state.ts              # GET /sync/state — cursor + last_sync_at
│   │   └── changes.ts            # GET /sync/changes — Phase 3, stub 501 for now
│   └── _lib/
│       ├── auth.ts                # requireApiKey(request) -> Response | null
│       ├── db.ts                  # neon(process.env.DATABASE_URL) singleton
│       └── outbox.ts              # buildUpsertStatements(items) -> sql fragments
├── package.json
├── tsconfig.json
└── vercel.json                    # only if custom routing/regions needed
```

### Pattern 1: Single versioned-upsert table (SYNC-02 + SYNC-06 in one mechanism)
**What:** One Postgres table storing current + 1 previous version per `(table_name, record_uuid)`, updated atomically so retry-of-same-version is a true no-op and only 2 versions are ever kept.
**When to use:** Every `/sync/push` request, one statement per outbox row, batched via `sql.transaction()`.
**Example:**
```sql
-- Source: standard Postgres UPSERT pattern (ON CONFLICT DO UPDATE), applied to
-- the neon()/@neondatabase/serverless driver per github.com/neondatabase/serverless README
CREATE TABLE synced_entities (
  table_name        TEXT NOT NULL,
  record_uuid       TEXT NOT NULL,
  op                TEXT NOT NULL,              -- last op applied: insert/update/delete
  current_version   INTEGER NOT NULL,
  current_payload   JSONB NOT NULL,
  current_updated_at TIMESTAMPTZ NOT NULL,
  previous_version   INTEGER,
  previous_payload   JSONB,
  previous_updated_at TIMESTAMPTZ,
  deleted_at         TIMESTAMPTZ,
  PRIMARY KEY (table_name, record_uuid)
);
```
```typescript
// One upsert per outbox item; batch N of these via sql.transaction([...]).
// idempotent: re-sending the same uuid+version is a no-op (CASE guards on strict '<').
// out-of-order guard: WHERE clause refuses to move current_version backwards.
function upsertStatement(sql: ReturnType<typeof neon>, item: OutboxItem) {
  return sql`
    INSERT INTO synced_entities
      (table_name, record_uuid, op, current_version, current_payload, current_updated_at)
    VALUES
      (${item.table_name}, ${item.record_uuid}, ${item.op}, ${item.version}, ${item.payload}, now())
    ON CONFLICT (table_name, record_uuid) DO UPDATE SET
      previous_version    = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                  THEN synced_entities.current_version ELSE synced_entities.previous_version END,
      previous_payload     = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                  THEN synced_entities.current_payload ELSE synced_entities.previous_payload END,
      previous_updated_at  = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                  THEN synced_entities.current_updated_at ELSE synced_entities.previous_updated_at END,
      current_version      = GREATEST(synced_entities.current_version, EXCLUDED.current_version),
      current_payload      = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                  THEN EXCLUDED.current_payload ELSE synced_entities.current_payload END,
      current_updated_at   = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                  THEN EXCLUDED.current_updated_at ELSE synced_entities.current_updated_at END,
      op                   = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                  THEN EXCLUDED.op ELSE synced_entities.op END,
      deleted_at           = CASE WHEN EXCLUDED.op = 'delete' AND synced_entities.current_version < EXCLUDED.current_version
                                  THEN now() ELSE synced_entities.deleted_at END
    WHERE EXCLUDED.current_version >= synced_entities.current_version
  `;
}
```
**Why this satisfies both SYNC-02 (idempotent, kill-mid-push safe) and SYNC-06 (current + 1 previous only) in one mechanism:** re-sending an already-applied `uuid`+`version` after an app kill mid-push changes nothing (all `CASE` branches are false when versions are equal), so it's a safe no-op to retry — the client doesn't need a separate "have I sent this before" table.

### Pattern 2: Batched ack via `sql.transaction()`
**What:** Send all pending outbox rows the client has (already batched by `SyncClient.pendingOutbox(limit)`) in one HTTP request; server runs them as one transaction and acks every row that succeeded.
**Example:**
```typescript
// api/sync/push.ts (legacy Node handler style — auto JSON body parsing, no manual request.json())
// Source: https://vercel.com/docs/functions/runtimes/node-js (verified 2026-08-11)
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { requireApiKey } from '../_lib/auth';
import { sql } from '../_lib/db';

export default async function handler(request: VercelRequest, response: VercelResponse) {
  const authError = requireApiKey(request);
  if (authError) return response.status(401).json({ error: authError });

  const { outbox } = request.body as { outbox: OutboxItem[] };
  if (!outbox?.length) {
    return response.status(200).json({ ackedIds: [], serverCursor: null, receivedAt: new Date().toISOString() });
  }

  const statements = outbox.map((item) => upsertStatement(sql, item));
  await sql.transaction(statements); // one non-interactive transaction, dynamic length

  // All rows in the batch either all commit or all roll back (transaction semantics) —
  // so on success every item's outbox `id` is ackable.
  const ackedIds = outbox.map((item) => item.id);
  return response.status(200).json({
    ackedIds,
    serverCursor: new Date().toISOString(), // simplest monotonic cursor available; revisit in Phase 3
    receivedAt: new Date().toISOString(),
  });
}
```
**Caveat (MEDIUM confidence):** `sql.transaction()` is all-or-nothing — if one row's insert fails (e.g. a constraint violation), the whole batch rolls back and nothing is acked, even rows that would have succeeded alone. For a single-editor app with a small `limit` (50, per existing `pendingOutbox(limit: 50)` default), this is an acceptable simplicity tradeoff — flag as an Open Question below rather than building per-row partial-commit handling, which the requirements don't ask for.

### Pattern 3: Auth middleware (SYNC-07)
```typescript
// api/_lib/auth.ts
import { timingSafeEqual } from 'node:crypto';

export function requireApiKey(request: { headers: Record<string, string | string[] | undefined> }): string | null {
  const header = request.headers['authorization'];
  const provided = typeof header === 'string' ? header.replace(/^Bearer\s+/i, '') : '';
  const expected = process.env.SYNC_API_KEY ?? '';
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    return 'invalid or missing API key';
  }
  return null;
}
```

### Pattern 4: Flutter-side `SyncApi` real implementation with Full Jitter backoff
```dart
// Source: AWS Architecture Blog "Exponential Backoff And Jitter" (Full Jitter formula, verified)
// sleep = random(0, min(cap, base * 2^attempt))
Duration fullJitterBackoff(int attempt, {Duration base = const Duration(seconds: 2), Duration cap = const Duration(minutes: 5)}) {
  final capped = math.min(cap.inMilliseconds, base.inMilliseconds * math.pow(2, attempt).toInt());
  return Duration(milliseconds: Random().nextInt(capped + 1));
}
```
```dart
// lib/data/sync/sync_api_http.dart — sketch, not final code
class SyncApiHttp implements SyncApi {
  SyncApiHttp({required http.Client client, required String apiKey}) : _client = client, _apiKey = apiKey;
  final http.Client _client;
  final String _apiKey;

  @override
  Future<SyncPushResult> pushOutbox({required List<Map<String, Object?>> outbox, String? cursor, String? deviceId}) async {
    final response = await _client.post(
      ApiConfig.syncPushUri(),
      headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'},
      body: jsonEncode({'outbox': outbox, 'cursor': cursor, 'deviceId': deviceId}),
    );
    if (response.statusCode == 401) {
      throw SyncAuthException('API key rejected (401)'); // caller treats as terminal, D-03
    }
    if (response.statusCode >= 500 || response.statusCode == 408) {
      throw SyncTransientException('server error ${response.statusCode}'); // caller retries w/ backoff
    }
    if (response.statusCode != 200) {
      throw SyncTransientException('unexpected status ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    return SyncPushResult(
      ackedIds: (body['ackedIds'] as List).cast<int>(),
      serverCursor: body['serverCursor'] as String? ?? cursor ?? '',
      receivedAt: DateTime.parse(body['receivedAt'] as String),
    );
  }
  // fetchState / pullChanges: out of scope this phase (Phase 3), can throw UnimplementedError
  // or return an empty result — planner decides based on whether DiagnosticsPanel calls them.
}
```
**Transient vs terminal classification (SYNC-03):**
| Condition | Classification | Action |
|-----------|----------------|--------|
| `SocketException`/timeout (no response reached server) | Transient | Backoff + retry on next trigger |
| HTTP 5xx, 408 | Transient | Backoff + retry on next trigger |
| HTTP 401 | Terminal (D-03) | Log, do NOT touch backoff/`last_attempt_at`; leave outbox pending; surface distinctly in `DiagnosticsPanel` |
| HTTP 4xx other than 401 (e.g. 400 malformed payload) | Terminal-ish — a payload the server will never accept won't succeed on retry either | Log distinctly; open question below on whether to also mark this "don't auto-retry" |

### Pattern 5: Auto-push trigger hook point
**Where:** `SyncLocalDataSource.enqueueOutbox()` in `lib/data/datasources/local/sync_local_data_source.dart` is the single method every one of the four local data sources (`AudioLocalDataSource`, `GeoTriggerLocalDataSource`, `GeoPathLocalDataSource`, `RegionLocalDataSource`) already calls after every insert/update/delete. Confirmed by direct code read — 16 call sites across 4 files, all funneling through this one method.
**Why this matters for the plan:** D-04 ("push fires automatically after every write") does not require touching those 4 files or their 16 call sites. It requires exactly one change: after `enqueueOutbox` successfully inserts a row, notify something that schedules a push (e.g. a callback/stream the DI container wires to `RunSyncUseCase.pushOutboxOnce()`, fired-and-forgotten so it doesn't block the write's `await`). This is the "fewest files, root cause not symptom" fix.
**Anti-pattern to avoid:** Adding a call to `RunSyncUseCase` inside each of the 4 data sources individually. That's 16 duplicated call sites for one piece of behavior, and it's exactly the kind of thing that drifts out of sync when a 5th data source is added later.

### Anti-Patterns to Avoid
- **A dedicated "processed request IDs" idempotency table:** Not needed — `uuid`+`logical_version` is already unique per logical write and already flows through the whole system (SQLite → outbox payload → server). Building a separate idempotency-key ledger duplicates what the version-based upsert (Pattern 1) already guarantees.
- **A polling `Timer` for retry backoff:** The app has zero polling loops by design (this milestone is actively removing the one that exists, `geofence_service`). Backoff should be realized as "is this row eligible yet" checked at existing trigger points (write, reconnect, manual), not a new interval timer.
- **Mirroring the SQLite schema 1:1 into 4 Postgres tables:** premature for a push-only phase where the payload is opaque until Phase 3's pull logic needs to read from it — see Alternatives Considered.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP request/response fakes for unit tests | A custom fake `http.Client` subclass | `package:http/testing.dart`'s `MockClient` | Ships inside the already-mandated `http` package — zero new dependency, verified against pub.dev docs. |
| Constant-time secret comparison | Manual `for` loop / `===` string compare | `node:crypto`'s `timingSafeEqual` | Built into Node, avoids reinventing a security-sensitive primitive incorrectly. |
| Retry/backoff scheduling | A generic "job queue" or new background-execution library | The existing `attempt_count` column + a new `last_attempt_at` column, checked at existing trigger points | Matches the project's explicit "no continuous polling" constraint; adding a queue library would be new architecture for 3 endpoints and one retry policy. |
| SQL injection protection | Manual string escaping/interpolation | `neon()`'s tagged-template parameter binding | Built into the mandated driver; templates are the documented, safe way to interpolate values. |

**Key insight:** Everything this phase needs — idempotency, versioning, retry timing, auth — already has either an existing column/field in the local schema or a built-in primitive in the mandated stack. The work is wiring, not building new infrastructure.

## Common Pitfalls

### Pitfall 1: Delete-op outbox payloads have no `logical_version`
**What goes wrong:** `GeoTriggerLocalDataSource.deleteOrphaned()`, `.deleteByAudioAssetId()`, and `GeoPathLocalDataSource.deleteByAudioAssetId()`/`.deleteById()` call `_sync.enqueueOutbox(op: 'delete', payload: {...})` with payloads like `{'reason': 'orphan_geo_path'}` or `{'audio_asset_id': ...}` — no `uuid`/`logical_version` in the payload itself (though `record_uuid` is a separate column on the outbox row, so the row itself is identifiable — but the server's version-based upsert (Pattern 1) needs a `version` number for every op, and deletes don't currently compute/bump one).
**Why it happens:** Delete call sites `SELECT uuid` before deleting but never `SELECT logical_version`, and never call `withUpdateMetadata` (which is what bumps `logical_version`) before enqueueing the delete.
**How to avoid:** Since this phase is already touching `enqueueOutbox`'s callers to wire the auto-push hook, fix delete call sites to also select `logical_version`, bump it (`existingVersion + 1`, consistent with `withUpdateMetadata`'s logic), and include it in the delete payload. This is a small, contained fix in 4 already-open files, not a new problem to solve from scratch.
**Warning signs:** If the plan's server-side upsert SQL assumes every outbox item has a `version` field and a delete payload doesn't, the deploy will either crash on a null constraint or silently treat all deletes as version `NULL`/0, breaking the "keep current + 1 previous" guarantee for deleted rows.

### Pitfall 2: `sync_outbox` has no timestamp for "when was this last attempted"
**What goes wrong:** True exponential backoff needs `now() >= last_attempt_at + backoff(attempt_count)` to decide whether a row is eligible to retry. The current schema only has `attempt_count` (a counter), not a timestamp — so there is no way to compute "has enough time passed" without adding a column.
**Why it happens:** `sync_outbox` was designed (Phase 1 groundwork) with just enough to support a manual, non-time-gated push button; it was never exercised against a real backoff policy.
**How to avoid:** Add `last_attempt_at INTEGER` (epoch seconds, consistent with `sync_state.last_sync_at`'s existing convention) via a new migration block (`oldVersion < 6`, bumping `_dbVersion` from 5 to 6), following the exact `ALTER TABLE ... ADD COLUMN` + try/catch pattern already used at `oldVersion < 4` in `app_database.dart`. Set it in `SyncLocalDataSource.incrementOutboxAttempt` (rename/extend to also stamp the timestamp) instead of adding a new timer.
**Warning signs:** If the plan implements backoff purely in-memory (e.g. a `Map<int, DateTime>` in `RunSyncUseCase`), it resets on every app restart/kill — which defeats the point of backoff for exactly the scenario SYNC-03 cares about (spotty connectivity, app backgrounded/killed between attempts).

### Pitfall 3: `connectivity_plus` "connected" is not "internet reachable"
**What goes wrong:** Treating a non-empty `List<ConnectivityResult>` (or one not equal to `[ConnectivityResult.none]`) as "the push will succeed" — it only reports interface type (WiFi/mobile/etc.), not actual reachability. A captive portal or a WiFi network with no real internet still reports "connected."
**Why it happens:** The package name and API surface (`checkConnectivity`) sound authoritative, but the package's own docs are explicit about this limitation (confirmed by CLAUDE.md's existing research).
**How to avoid:** Use `onConnectivityChanged`/`checkConnectivity` only to decide *when to attempt* a push (skip pointless wake-ups when clearly offline), never to decide the outbox is synced. The real reliability signal stays the HTTP response (or its absence) from the actual push attempt, exactly as D-05 already specifies.
**Warning signs:** `DiagnosticsPanel` or any UI showing "synced" based on connectivity state rather than actual `ackedIds`/`last_sync_at` from a real push response.

### Pitfall 4: `sql.transaction()` batch failure semantics
**What goes wrong:** If any single outbox row's upsert statement in a batch fails (malformed payload, constraint violation), the Neon HTTP driver's `sql.transaction()` rolls back the *entire* batch — none of the rows in that push get acked, even ones that were individually fine.
**Why it happens:** `sql.transaction()` is a non-interactive transaction: all statements commit together or none do. There's no per-statement partial-success mode in the HTTP driver.
**How to avoid:** Given `limit: 50` default batch size and a single-editor use case, accept all-or-nothing semantics for this phase (simpler, matches "don't over-build" scope) but validate/sanitize payload shape server-side *before* building the SQL so malformed-payload failures are rare. If this becomes a real problem in practice, the fix is smaller batches or per-item try/catch with the WebSocket `Pool` driver (see Alternatives Considered) — not something to build preemptively.
**Warning signs:** A single always-failing row (e.g. from a schema drift) silently blocking the entire outbox from ever draining, since every batch containing it will roll back forever until that specific row is identified and cleared.

## Code Examples

See Architecture Patterns above — all code examples there are sourced/verified as noted inline (AWS Full Jitter formula, Vercel docs for handler signature, Neon serverless README for `neon()`/`sql.transaction()`, existing codebase for the migration pattern).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Vercel Functions as Express-style `(req, res)` handlers only | Fetch Web Standard handlers (`export default { fetch(request) {...} }` or `export function GET/POST`) also supported, now the *recommended* style; legacy `(request, response)` with `request.body`/`request.query` helpers still fully supported | Ongoing (Vercel docs updated 2026-08-11) | Either style works. This research recommends the **legacy style** for this phase specifically because it auto-parses JSON bodies (`request.body`) with zero extra code — the smaller diff for 3 simple endpoints. |
| `@neondatabase/serverless` at early 0.x | 1.1.0 (verified current), driver reached GA/1.0 stability | Documented in Neon's "serverless driver GA" blog post | Confirms this is a stable, production-ready choice, not an early-access risk. |

**Deprecated/outdated:** None identified as deprecated in this domain during research — this is a stack chosen fresh in CLAUDE.md's own recent research, not a legacy area.

## Open Questions

1. **Should non-401 4xx errors (e.g. malformed payload, 400) also be treated as terminal (no backoff) rather than transient?**
   - What we know: D-03 only explicitly calls out 401 as terminal.
   - What's unclear: A 400 (bad request shape) also won't succeed on retry, but CONTEXT.md doesn't address it.
   - Recommendation: Treat all non-401 4xx as transient-but-logged for this phase (simplest interpretation of the locked decisions, doesn't invent a new terminal-error category); revisit if it proves noisy in practice. Flag this choice explicitly in the plan so it's a visible decision, not an accident.

2. **Server cursor semantics for `/sync/push`'s response — what should `serverCursor` actually be?**
   - What we know: `SyncPushResult.serverCursor` is persisted to local `sync_state` and echoed back on the next push; Phase 3 will need a cursor `/sync/changes` can page from.
   - What's unclear: Whether a simple `now()` timestamp string is sufficient for Phase 2 (push-only, cursor is unused downstream until Phase 3) or whether Phase 3's pull design needs a specific cursor shape (e.g. a monotonic sequence number) decided now to avoid a migration later.
   - Recommendation: Use an ISO timestamp string for Phase 2 (matches `receivedAt`'s shape, trivially simple) since pull doesn't exist yet and nothing consumes the cursor's internal structure this phase — but note this explicitly as a decision Phase 3's research should revisit, not silently lock in.

3. **All-or-nothing batch semantics (Pitfall 4) — acceptable for this phase's success criteria?**
   - What we know: Success criterion 2 ("kill mid-push, reopen, no duplicates") is satisfied regardless of batch semantics (idempotent upsert handles it).
   - What's unclear: Whether a single bad row permanently blocking a whole batch violates the spirit of SYNC-03's "reintenta ... sin perder escrituras ni colgar el loop."
   - Recommendation: Acceptable for this phase given the scale (single editor, small batches) — a genuinely malformed row is a bug to fix, not a runtime scenario to design elaborate partial-batch recovery for. Server-side payload validation (reject the whole request with 400 + a clear error listing which item failed) surfaces the problem loudly instead of silently stalling.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|--------------|-----------|---------|----------|
| Node.js (local dev) | Backend function development, `vercel dev` | ✓ (assumed — not directly probed; Flutter/Dart toolchain confirmed present) | — | — |
| Flutter SDK | Client-side `SyncApiHttp` implementation | ✓ | 3.35.2 (stable) | — |
| Neon account + project | Backend datastore | Not probed (external account, cannot verify from this environment) | — | Plan must include a setup step: create Neon project, get `DATABASE_URL`, add to Vercel env |
| Vercel account + project | Backend hosting | Not probed (external account) | — | Plan must include a setup step: `vercel link`/`vercel env add` |

**Missing dependencies with no fallback:**
- None identified as blocking — Neon/Vercel account creation is a one-time manual setup step to include as an early task in the plan, not a missing tool.

**Missing dependencies with fallback:**
- None beyond the account-setup items above.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework (Flutter) | `flutter_test` (already in `pubspec.yaml` dev_dependencies) + `package:http/testing.dart` `MockClient` (no new dependency) |
| Framework (backend) | `node:test` (Node 24 LTS built-in) — no existing backend test infra since the backend directory doesn't exist yet |
| Config file | None currently for backend (Wave 0: create `backend/package.json` test script `"test": "node --test"`) |
| Quick run command (Flutter) | `flutter test test/data/sync/` |
| Full suite command (Flutter) | `flutter test` |
| Quick run command (backend) | `node --test backend/api/_lib/*.test.ts` (via `tsx`/`ts-node` loader, or compile first — decide in plan) |
| Full suite command (backend) | `node --test` from `backend/` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|--------------------|--------------|
| SYNC-01 | `SyncApiHttp.pushOutbox` sends correct request shape, parses response | unit (Flutter, `MockClient`) | `flutter test test/data/sync/sync_api_http_test.dart` | ❌ Wave 0 |
| SYNC-02 | Same `uuid`+`logical_version` sent twice → server state unchanged, both acked | integration (real Neon branch, or `node:test` hitting a local Postgres/Neon dev branch) | `node --test backend/api/sync/push.test.ts` | ❌ Wave 0 |
| SYNC-02 | "Kill mid-push" simulated: two identical `pushOutbox` calls from Flutter side against `MockClient` returning the same ack twice | unit (Flutter) | `flutter test test/domain/usecases/run_sync_usecase_test.dart` | ❌ Wave 0 |
| SYNC-03 | Transient error (500/timeout) → `markAttempt`/`last_attempt_at` updates, row stays pending, eligible-later logic gates re-send | unit (Flutter, `MockClient` returning 500) | `flutter test test/data/sync/sync_api_http_test.dart` | ❌ Wave 0 |
| SYNC-03 | 401 → row stays pending, `last_attempt_at`/backoff untouched, distinct log entry | unit (Flutter, `MockClient` returning 401) | `flutter test test/data/sync/sync_api_http_test.dart` | ❌ Wave 0 |
| SYNC-06 | After 3 pushes on the same uuid, server row has only current + 1 previous (not 3) | integration (real Neon branch) | `node --test backend/api/sync/push.test.ts` | ❌ Wave 0 |
| SYNC-07 | Request with missing/wrong `Authorization` header → 401; correct header → 200 | unit (backend, `node:test` calling handler directly with a fake request object) | `node --test backend/api/_lib/auth.test.ts` | ❌ Wave 0 |
| SYNC-08 | `DiagnosticsPanel` never shows a "synced" state when `_outboxCount > 0` | manual QA (widget test optional — UI is already mostly correct, this is a regression check not new behavior) | manual device/emulator check | N/A — human verification |

### Sampling Rate
- **Per task commit:** `flutter test test/data/sync/ test/domain/usecases/` (Flutter) and `node --test` from `backend/` (backend) — whichever side the task touched.
- **Per wave merge:** Full suite both sides: `flutter test` and `node --test` (backend).
- **Phase gate:** Both full suites green, plus one real end-to-end push against an actual Neon dev branch + deployed (or `vercel dev`) endpoint before `/gsd:verify-work` — this is the one thing unit tests with mocks can't catch (real SQL behavior, real HTTP round-trip, real auth header handling).

### Wave 0 Gaps
- [ ] `backend/` directory doesn't exist yet — needs `package.json`, `tsconfig.json`, and `node --test` wired as the test command.
- [ ] `test/data/sync/sync_api_http_test.dart` — new file, covers SYNC-01/SYNC-02/SYNC-03 client-side behavior via `MockClient`.
- [ ] `test/domain/usecases/run_sync_usecase_test.dart` — new file, covers idempotent-retry-after-kill and ack/markAttempt bookkeeping (this can reuse a fake `SyncApi` implementation, not necessarily HTTP-level).
- [ ] `backend/api/sync/push.test.ts` — new file, needs a real (or Neon-branch) Postgres connection for true integration coverage of the upsert SQL; a pure-SQL unit test against an in-memory/sqlite stand-in would NOT actually validate Postgres-specific `ON CONFLICT`/`JSONB` behavior, so this specific test should run against a real Neon dev branch (per CLAUDE.md's Development Tools: "Neon branching ... free tier includes up to 10 branches").
- [ ] `backend/api/_lib/auth.test.ts` — new file, pure unit test, no DB needed.

## Sources

### Primary (HIGH confidence)
- `CLAUDE.md` (this repo) — Technology Stack section, already-settled Neon+Vercel research with sources cited; not re-verified here per phase boundary instructions.
- https://vercel.com/docs/functions/runtimes/node-js — fetched directly 2026-08-29 (page `last_updated: 2026-08-11`), confirmed Node 24 LTS GA, both fetch-Web-Standard and legacy `(request, response)` handler styles, `request.body`/`request.query`/`request.cookies` auto-parsing helpers.
- https://raw.githubusercontent.com/neondatabase/serverless/main/README.md — fetched directly, confirmed `neon()` tagged-template usage and `sql.transaction([...])` dynamic-length batch semantics.
- https://pub.dev/packages/connectivity_plus (and its docs page) — fetched directly, confirmed v7.x API returns `List<ConnectivityResult>` from both `checkConnectivity()` and `onConnectivityChanged`.
- pub.dev API (`https://pub.dev/api/packages/{http,connectivity_plus,mocktail}`) — fetched directly for exact current version numbers and publish dates.
- `npm view @neondatabase/serverless version`, `npm view vercel version`, `npm view @vercel/node version` — fetched directly for exact current version numbers.
- AWS Architecture Blog, "Exponential Backoff And Jitter" — Full Jitter formula (`sleep = random(0, min(cap, base * 2^attempt))`), cross-confirmed by multiple secondary sources in the same WebSearch batch (DEV Community, Medium, ElasticDog) all describing the same three canonical algorithms (Full/Equal/Decorrelated Jitter) consistently.
- Direct code reads (this repo): `lib/data/sync/sync_api.dart`, `sync_api_stub.dart`, `sync_client.dart`, `run_sync_usecase.dart`, `api_config.dart`, `service_locator.dart`, `sync_local_data_source.dart`, `audio_local_data_source.dart`, `geo_trigger_local_data_source.dart`, `geo_path_local_data_source.dart`, `region_local_data_source.dart`, `app_database.dart` (schema + migration pattern), `diagnostics_panel.dart`, `pubspec.yaml`, `test/data/datasources/local/db_recovery_test.dart` (test-style precedent).

### Secondary (MEDIUM confidence)
- WebSearch "Vercel Functions Node.js 2026 request handler export default" — cross-checked against the directly-fetched Vercel docs page above; consistent.
- pub.dev search result summary for `package:http/testing.dart` `MockClient` — consistent with well-established, stable API; not independently fetched from the raw docs page but corroborated by multiple search results describing identical usage.

### Tertiary (LOW confidence)
- None retained as unverified/single-source claims in this document — all flagged uncertainties were instead written up as explicit Open Questions or Common Pitfalls rather than stated as fact.

## Metadata

**Confidence breakdown:**
- Standard stack (versions): HIGH — every version fetched directly from pub.dev/npm registries same day as research.
- Architecture (backend SQL design, auto-push hook point): MEDIUM-HIGH — the hook point (`enqueueOutbox`) and the two schema gaps (delete-op version, `last_attempt_at`) are HIGH confidence (verified by direct code read, not inference). The specific `synced_entities` table shape is a research-time design recommendation (MEDIUM), not a documented external pattern — the planner should treat the SQL as a strong starting point, not gospel.
- Pitfalls: HIGH for the two code-derived pitfalls (delete payload gap, missing `last_attempt_at`) since both are directly observable in the current codebase, not speculative. HIGH for the `connectivity_plus` reachability caveat (directly verified against package docs).

**Research date:** 2026-08-29
**Valid until:** ~30 days for library versions (stable ecosystem, low churn expected); the code-derived findings (hook point, schema gaps) remain valid until the referenced files change.
