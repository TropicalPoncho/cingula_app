---
phase: 01-blindaje-de-datos-y-separaci-n-debug-usuario
plan: 02
subsystem: ui
tags: [flutter, shared_preferences, material3, widget-testing]

# Dependency graph
requires:
  - phase: 01-blindaje-de-datos-y-separaci-n-debug-usuario
    provides: "LocationConfig persistence pattern (lib/core/config/location_config.dart), AudioAsset entity, AudioDetails widget, 01-UI-SPEC.md visual contract"
provides:
  - "AppModeConfig — persisted debug/user mode flag, default debug, mirrors LocationConfig pattern"
  - "HiddenTapGesture — 5-tap-in-3-seconds secret activation widget"
  - "UserModeView — DI-free user-mode home screen body per 01-UI-SPEC.md"
affects: [01-03-home-page-wiring]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Static class + SharedPreferences persistence (mirrors LocationConfig): default value set at field declaration AND at the '?? default' fallback, both true, so a fresh install or a prefs read failure never leaves the debug gate closed."
    - "Presentation widgets built as pure functions of constructor params (no getIt/provider) so they're testable with plain MaterialApp/Scaffold wrappers, no DI graph."

key-files:
  created:
    - lib/core/config/app_mode_config.dart
    - lib/presentation/widgets/hidden_tap_gesture.dart
    - lib/presentation/pages/home/widgets/user_mode_view.dart
    - test/core/config/app_mode_config_test.dart
    - test/presentation/widgets/hidden_tap_gesture_test.dart
    - test/presentation/pages/home/widgets/user_mode_view_test.dart
  modified:
    - lib/core/app_initializer.dart

key-decisions:
  - "No deviations - plan executed exactly as written, including exact copy strings and TDD RED/GREEN commit sequence."

patterns-established:
  - "Isolated, DI-free presentation widgets for anything that needs to be unit-testable without mounting HomePage's getIt/Provider graph."

requirements-completed: [UI-01]

duration: 25min
completed: 2026-08-08
---

# Phase 01 Plan 02: AppModeConfig, HiddenTapGesture, UserModeView Summary

**Three isolated, DI-free building blocks for the runtime debug/user mode toggle: persisted mode flag defaulting to debug, a 5-tap-in-3-seconds secret gesture, and the Material 3 user-mode home screen body — none yet wired into HomePage (that's plan 01-03).**

## Performance

- **Duration:** 25 min
- **Started:** 2026-08-08T17:12:00Z
- **Completed:** 2026-08-08T17:37:14Z
- **Tasks:** 3
- **Files modified:** 7 (3 new lib files, 3 new test files, 1 modified lib file)

## Accomplishments
- `AppModeConfig` persists debug/user mode via SharedPreferences with a double-guaranteed debug default (field initializer + `?? true` fallback), wired into `AppInitializer.init()` right after `LocationConfig.loadFromPrefs()`.
- `HiddenTapGesture` implements the 5-taps-in-3-seconds secret activation contract from 01-UI-SPEC.md, with a `Timer`-based rolling window that resets both on window expiry and on successful activation.
- `UserModeView` renders the full user-mode screen body (status hero, monitoring switch, conditional audio card) exactly per 01-UI-SPEC.md's copy, color-role, and 4px spacing-scale contract, with zero `getIt`/`provider` imports.

## Task Commits

Each task followed TDD (RED then GREEN):

1. **Task 1: AppModeConfig** - `4d215c5` (test, RED) → `ece08c2` (feat, GREEN)
2. **Task 2: HiddenTapGesture** - `cc8044e` (test, RED) → `4c69fdb` (feat, GREEN)
3. **Task 3: UserModeView** - `c64f14e` (test, RED) → `8767608` (feat, GREEN)

No refactor commits were needed — each GREEN implementation matched the plan's literal `<action>` code and passed on the first try.

## Files Created/Modified
- `lib/core/config/app_mode_config.dart` - Persisted `isDebugMode` flag, defaults to debug, mirrors `LocationConfig`.
- `lib/core/app_initializer.dart` - Added `AppModeConfig.loadFromPrefs()` call after `LocationConfig.loadFromPrefs()`.
- `lib/presentation/widgets/hidden_tap_gesture.dart` - 5-tap/3-second secret gesture wrapper widget.
- `lib/presentation/pages/home/widgets/user_mode_view.dart` - User-mode screen body (status hero + monitoring switch + conditional `AudioDetails` card).
- `test/core/config/app_mode_config_test.dart` - 4 tests: fresh install default, persisted false/true, round-trip persistence.
- `test/presentation/widgets/hidden_tap_gesture_test.dart` - 5 tests: activation at 5 taps, no activation at 4, window expiry resets count, counter resets post-activation, child renders as-is.
- `test/presentation/pages/home/widgets/user_mode_view_test.dart` - 6 tests: default/monitoring copy, explicit statusMessage override, conditional `AudioDetails` rendering, switch callback.

## Decisions Made
None - followed plan as specified, including literal copy strings (with the U+2026 ellipsis character) and the exact widget/file structure from the plan's `<interfaces>` block.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. All three tasks' `flutter test` and `flutter analyze` acceptance criteria passed without iteration. `flutter analyze` on the full project shows 4 pre-existing issues in unrelated files (`data_browser_page.dart`, `trigger_map.dart`) that predate this plan and are out of scope per the plan's file list — not introduced by this work.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All three interfaces (`AppModeConfig`, `HiddenTapGesture`, `UserModeView`) match the exact contracts declared in this plan's `<interfaces>` block, ready for plan 01-03 to wire them into `HomePage` (toggle rendering + hidden gesture on the AppBar title + mode-switch `SnackBar` feedback).
- No blockers. Plan 01-03 will need `PlaybackNotifier`'s `isMonitoring`/`statusMessage`/`currentAsset` fields to feed `UserModeView`'s constructor params — those already exist and are unchanged by this plan.

---
*Phase: 01-blindaje-de-datos-y-separaci-n-debug-usuario*
*Completed: 2026-08-08*

## Self-Check: PASSED

- FOUND: lib/core/config/app_mode_config.dart
- FOUND: lib/presentation/widgets/hidden_tap_gesture.dart
- FOUND: lib/presentation/pages/home/widgets/user_mode_view.dart
- FOUND: test/core/config/app_mode_config_test.dart
- FOUND: test/presentation/widgets/hidden_tap_gesture_test.dart
- FOUND: test/presentation/pages/home/widgets/user_mode_view_test.dart
- FOUND commits: 4d215c5, ece08c2, cc8044e, 4c69fdb, c64f14e, 8767608
