---
phase: 02
slug: backend-real-push-sync
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-29
---

# Phase 02 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (Flutter)** | `flutter_test` (already in `pubspec.yaml` dev_dependencies) + `package:http/testing.dart` `MockClient` (no new dependency) |
| **Framework (backend)** | `node:test` (Node 24 LTS built-in) — no existing backend test infra, `backend/` directory doesn't exist yet |
| **Config file** | None currently for backend — Wave 0 creates `backend/package.json` with `"test": "node --test"` |
| **Quick run command (Flutter)** | `flutter test test/data/sync/ test/domain/usecases/` |
| **Full suite command (Flutter)** | `flutter test` |
| **Quick run command (backend)** | `node --test backend/api/_lib/*.test.ts` (via `tsx`/`ts-node` loader, or compile first — decide in plan) |
| **Full suite command (backend)** | `node --test` from `backend/` |
| **Estimated runtime** | ~30s Flutter, ~10s backend (excludes the one real Neon-branch integration check) |

---

## Sampling Rate

- **After every task commit:** Run the quick command for whichever side (Flutter/backend) the task touched
- **After every plan wave:** Run both full suites — `flutter test` and `node --test` from `backend/`
- **Before `/gsd:verify-work`:** Both full suites green, PLUS one real end-to-end push against an actual Neon dev branch + deployed (or `vercel dev`) endpoint — this is the one thing mocked unit tests can't catch (real SQL `ON CONFLICT` behavior, real HTTP round-trip, real auth header handling)
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-XX | TBD | TBD | SYNC-01 | unit (Flutter, MockClient) | `flutter test test/data/sync/sync_api_http_test.dart` | ❌ W0 | ⬜ pending |
| 02-XX | TBD | TBD | SYNC-02 | integration (real Neon branch) | `node --test backend/api/sync/push.test.ts` | ❌ W0 | ⬜ pending |
| 02-XX | TBD | TBD | SYNC-02 | unit (Flutter) — kill-mid-push simulation | `flutter test test/domain/usecases/run_sync_usecase_test.dart` | ❌ W0 | ⬜ pending |
| 02-XX | TBD | TBD | SYNC-03 | unit (Flutter, MockClient 500) | `flutter test test/data/sync/sync_api_http_test.dart` | ❌ W0 | ⬜ pending |
| 02-XX | TBD | TBD | SYNC-03 | unit (Flutter, MockClient 401) | `flutter test test/data/sync/sync_api_http_test.dart` | ❌ W0 | ⬜ pending |
| 02-XX | TBD | TBD | SYNC-06 | integration (real Neon branch) | `node --test backend/api/sync/push.test.ts` | ❌ W0 | ⬜ pending |
| 02-XX | TBD | TBD | SYNC-07 | unit (backend, node:test) | `node --test backend/api/_lib/auth.test.ts` | ❌ W0 | ⬜ pending |
| 02-XX | TBD | TBD | SYNC-08 | manual QA | manual device/emulator check | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*Task IDs/plan/wave columns filled in by the planner once PLAN.md files exist.*

---

## Wave 0 Requirements

- [ ] `backend/` directory scaffold — `package.json`, `tsconfig.json`, `node --test` wired as the test command
- [ ] `test/data/sync/sync_api_http_test.dart` — new file, covers SYNC-01/SYNC-02/SYNC-03 client-side behavior via `MockClient`
- [ ] `test/domain/usecases/run_sync_usecase_test.dart` — new file, covers idempotent-retry-after-kill and ack/markAttempt bookkeeping (can reuse a fake `SyncApi`, not necessarily HTTP-level)
- [ ] `backend/api/sync/push.test.ts` — new file, needs a real (or Neon-branch) Postgres connection for true integration coverage of the upsert SQL — a sqlite/in-memory stand-in would NOT validate Postgres-specific `ON CONFLICT`/`JSONB` behavior
- [ ] `backend/api/_lib/auth.test.ts` — new file, pure unit test, no DB needed

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|--------------------|
| `DiagnosticsPanel` never shows a "synced" state when outbox count > 0 | SYNC-08 | UI is already mostly correct — this is a regression check on existing behavior, not new UI logic worth a widget test | Write locally with backend unreachable, confirm outbox count stays > 0 and no false "todo sincronizado" appears |
| Real end-to-end push against deployed/`vercel dev` backend + Neon dev branch | SYNC-01, SYNC-02, SYNC-06 | Mocked HTTP/SQL tests can't catch real network round-trip, real Postgres `ON CONFLICT` behavior, or real auth header wiring | Run app against `vercel dev` pointed at a Neon branch; write an entity, confirm it lands in Neon; kill app mid-push and relaunch, confirm no duplicate row |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
