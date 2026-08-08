---
phase: 01-blindaje-de-datos-y-separaci-n-debug-usuario
plan: 03
subsystem: ui
tags: [flutter, material3, app-mode-toggle, data-recovery-banner]

# Dependency graph
requires:
  - phase: 01-blindaje-de-datos-y-separaci-n-debug-usuario
    provides: "AppModeConfig, HiddenTapGesture, UserModeView (01-02); AppDatabase.lastRecoveryEvent, DatabaseRecoveryEvent (01-01)"
provides:
  - "HomePage as StatefulWidget wired to AppModeConfig.isDebugMode with a hidden 5-tap toggle and debug/user body split"
  - "Non-blocking MaterialBanner shown once after a DB recovery, sourced from AppDatabase.lastRecoveryEvent"
affects: [01-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "HomePage build() delegates to _buildDebugBody/_buildUserBody private methods gated on AppModeConfig.isDebugMode, keeping the FAB outside both branches"

key-files:
  created: []
  modified:
    - lib/presentation/pages/home_page_impl.dart

key-decisions:
  - "Task 1's plan text assumed home_page_impl.dart already contained a _RecordingBanner widget wired to RecorderService (lines 69-165) — that content does not exist in this worktree's git history (see Deviations)."

patterns-established:
  - "Recovery/error banners use showMaterialBanner (never showDialog) so the app stays usable mid-recording, per D-02."

requirements-completed: [UI-01, DATA-01]

# Metrics
duration: ~20min
completed: 2026-08-08
---

# Phase 01 Plan 03: HomePage Debug/Usuario Wiring + Recovery Banner Summary

**HomePage converted to a StatefulWidget with a hidden 5-tap AppBar-title gesture that toggles `AppModeConfig.isDebugMode` (with SnackBar confirmation), a debug/user body split (`UserModeView` in user mode, existing switch+audio+`DiagnosticsPanel` column in debug mode), and a one-shot `MaterialBanner` that surfaces `AppDatabase.lastRecoveryEvent` after a DB rename-recovery.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-08-08
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- 5 taps on the "Cingula" AppBar title (within 3 seconds, via the existing `HiddenTapGesture`) flips `AppModeConfig.isDebugMode`, persists it, and shows a 2-second `SnackBar` ("Modo debug activado" / "Modo usuario activado") — matches UI-SPEC copy verbatim.
- `build()` now branches on `AppModeConfig.isDebugMode`: user mode renders `UserModeView` (switch + audio card, no `DiagnosticsPanel`); debug mode renders the original `SingleChildScrollView` column (switch, audio card, `DiagnosticsPanel`) unchanged. The Iniciar/Detener FAB stays outside both branches (D-11).
- After the first frame, `_showRecoveryBannerIfNeeded()` reads `getIt<AppDatabase>().lastRecoveryEvent`; if a DB recovery happened, it shows a non-blocking `MaterialBanner` (never `showDialog`) with the exact UI-SPEC copy naming the renamed backup file, styled with `colorScheme.errorContainer`/`onErrorContainer`, and clears the event so it only shows once.

## Task Commits

Each task was committed atomically:

1. **Task 1: HomePage stateful con gesto oculto y rama debug/usuario** - `d7800dd` (feat)
2. **Task 2: Banner no bloqueante de recuperación de base de datos** - `bbc6aef` (feat)

**Plan metadata:** pending (this commit)

## Files Created/Modified
- `lib/presentation/pages/home_page_impl.dart` - `HomePage` converted to `StatefulWidget`; added `_toggleMode`, `_buildDebugBody`/`_buildUserBody`, `HiddenTapGesture`-wrapped title, and `_showRecoveryBannerIfNeeded` (called from `initState` via `addPostFrameCallback`).

## Decisions Made
- Kept the debug body's `SingleChildScrollView` padding as the original `EdgeInsets.all(16)` rather than the `EdgeInsets.fromLTRB(16, 16, 16, 96)` quoted in the plan text — the plan's instruction was to move the existing column "TAL CUAL" (as-is, unchanged), and the actual current file uses `EdgeInsets.all(16)`. Preserving the real existing value honors "don't touch debug styling" more faithfully than the plan's (apparently misremembered) quoted value. Not a functional deviation — debug mode's FAB-overlap-vs-padding behavior is unchanged from before this plan.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking/missing referenced code] Plan's Task 1 assumed a pre-existing `_RecordingBanner` widget and `RecorderService` usage in `build()` that do not exist on this branch**
- **Found during:** Task 1, at `<read_first>` (plan cites `_RecordingBanner` at lines 69-165 and instructs moving `getIt<RecorderService>()` from `build()` into `_buildDebugBody`)
- **Issue:** The actual committed `home_page_impl.dart` in this worktree (built from `01-01`+`01-02` merged onto local `main`) is only 56 lines with no `_RecordingBanner` class and no `RecorderService`/`getIt` reference anywhere in the file. Investigation traced this to `stash@{0}` ("On main: WIP: sync/geofencing work before Phase 1 execution") in the parent repo — a substantial, deliberately-stashed set of uncommitted changes (mic-recording banner, `RecorderService` recording flow, sync/geofencing work) that the user set aside specifically so Phase 1 could execute against a clean base. `01-CONTEXT.md` and `01-UI-SPEC.md` both reference this same content (e.g. UI-SPEC's "`_RecordingBanner`'s red mic indicator (`home_page_impl.dart:137-147`)") — the planning artifacts were generated while that WIP was still in the working tree, before it was stashed.
- **Fix:** Implemented the StatefulWidget conversion, hidden-gesture wiring, and debug/user body split exactly as specified, but without conditioning a `_RecordingBanner`/`RecorderService` reference that doesn't exist in this branch's `home_page_impl.dart` — there is nothing to hide in user mode on this line of work since the mic-recording banner isn't part of the committed codebase. D-10's outcome ("no se ve ... el banner de grabación de micrófono" in user mode) still holds vacuously: user mode renders `UserModeView`, which never includes any recording banner.
- **Files modified:** `lib/presentation/pages/home_page_impl.dart` (same file already in scope)
- **Verification:** `flutter analyze` clean, `flutter test` green (28/28). Acceptance-criteria greps for `_RecordingBanner(recorder` and `getIt<RecorderService>()` inside `_buildDebugBody` are not applicable and were skipped for this reason; all other Task 1 acceptance-criteria greps pass.
- **Committed in:** `d7800dd` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking/missing-referenced-code)
**Impact on plan:** No scope creep — the deviation is an omission (not conditioning nonexistent code) rather than an addition. UI-01 and DATA-01 acceptance criteria that don't depend on the stashed WIP all pass as written.

## Issues Encountered
- Same root cause as the deviation above: this worktree was created from `origin/main` (predates `.planning/` entirely) rather than from local `main`'s HEAD. Fast-forwarded (`git merge --ff-only main`, a non-destructive operation since the worktree branch was a strict ancestor with zero divergent commits) to pick up `.planning/`, `CLAUDE.md`, and the `01-01`/`01-02` merges before starting execution.
- `flutter pub get`/`flutter analyze`/`flutter test` regenerated `linux/flutter/generated_plugin_registrant.*`, `macos/Flutter/GeneratedPluginRegistrant.swift`, and `windows/flutter/generated_plugin_registrant.*` with line-ending-only churn (no content diff). Left uncommitted/unstaged — out of scope for this plan's `files_modified` list.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- UI-01 (runtime debug/user toggle) and DATA-01 (non-blocking DB recovery notice) are both now observable in `HomePage`. No blockers for `01-04`.
- If a future plan needs the mic-recording banner / `RecorderService` UI wiring, that content still lives in the parent repo's `stash@{0}` ("WIP: sync/geofencing work before Phase 1 execution") and was intentionally not restored here.

---
*Phase: 01-blindaje-de-datos-y-separaci-n-debug-usuario*
*Completed: 2026-08-08*

## Self-Check: PASSED

- FOUND: lib/presentation/pages/home_page_impl.dart
- FOUND commits: d7800dd, bbc6aef
