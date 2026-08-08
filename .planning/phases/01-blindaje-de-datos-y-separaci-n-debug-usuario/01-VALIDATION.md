---
phase: 01
slug: blindaje-de-datos-y-separaci-n-debug-usuario
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-08
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (bundled with Flutter SDK, already in `dev_dependencies`) |
| **Config file** | none — no `dart_test.yaml` in repo; tests run via default `flutter test` discovery of `test/**/*_test.dart` |
| **Quick run command** | `flutter test test\core\app_database_test.dart` (targeted once new files exist) |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds (small suite) |

---

## Sampling Rate

- **After every task commit:** Run `flutter test`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green, plus the manual QA step for the DB-recovery banner
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 0 | DATA-01 | unit | `flutter test test/core/app_database_test.dart` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | DATA-01 | manual | Corrupt `cingula.db` on device/emulator, cold-start, confirm banner text + renamed file present | N/A manual-only | ⬜ pending |
| 01-01-03 | 01 | 1 | DATA-02 | unit / static check | `flutter test` + `grep -rn "recreateForTesting\|importDatabase" lib/` returns no matches outside intentionally-kept code | ✅ existing suite | ⬜ pending |
| 01-01-04 | 01 | 0 | UI-01 | unit | `flutter test test/core/config/app_mode_config_test.dart` | ❌ W0 | ⬜ pending |
| 01-01-05 | 01 | 1 | UI-01 | widget | `flutter test test/presentation/pages/home_page_gesture_test.dart` | ❌ W0 | ⬜ pending |
| 01-01-06 | 01 | 1 | UI-01 | widget | `flutter test test/presentation/pages/home_page_mode_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/core/app_database_test.dart` — stubs for DATA-01 rename-recovery behavior (only if `sqflite_common_ffi` is adopted; otherwise this becomes a manual-only verification, see Manual-Only Verifications below)
- [ ] `test/core/config/app_mode_config_test.dart` — stubs for UI-01 persistence/default behavior, using `SharedPreferences.setMockInitialValues({})` (no new dependency needed)
- [ ] `test/presentation/pages/home_page_gesture_test.dart` — stubs for UI-01 tap-count/timeout gesture
- [ ] `test/presentation/pages/home_page_mode_test.dart` — stubs for UI-01 conditional widget visibility

*(No shared fixtures/conftest-equivalent needed — each new test file is self-contained per existing repo convention.)*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|--------------------|
| App starts normally (no blocking UI) after a DB recovery event; banner text matches UI-SPEC copy | DATA-01 | Requires real filesystem state manipulation on-device; low ROI to automate a one-time startup event | Corrupt `cingula.db` on a device/emulator, cold-start app, confirm banner text + dismiss works, confirm renamed file present in app documents dir |

*Planner may choose to automate the DATA-01 rename-recovery unit test via `sqflite_common_ffi` (adds one dev dependency) instead of relying solely on this manual step — either approach satisfies Nyquist as long as the chosen path is reflected in the Per-Task Verification Map above.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
