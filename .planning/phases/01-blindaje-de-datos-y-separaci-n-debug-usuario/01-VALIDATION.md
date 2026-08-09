---
phase: 01
slug: blindaje-de-datos-y-separaci-n-debug-usuario
status: planned
nyquist_compliant: true
wave_0_complete: n/a
created: 2026-08-08
updated: 2026-08-08
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (bundled with Flutter SDK, already in `dev_dependencies`) |
| **Config file** | none — no `dart_test.yaml` in repo; tests run via default `flutter test` discovery of `test/**/*_test.dart` |
| **Quick run command** | `flutter test test/<archivo>_test.dart` (targeted) |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds (small suite) |
| **New dev dependencies** | none — `sqflite_common_ffi` NO se adopta (ver "Decisión de planning") |

---

## Decisión de planning (2026-08-08)

El research ofrecía dos caminos para DATA-01: adoptar `sqflite_common_ffi` para probar el ciclo real `openDatabase` → fallo → rename → reopen, o dejarlo como QA manual. Se eligió un tercer camino, más barato y con mejor cobertura del riesgo real:

- La lógica de riesgo (renombrar sin borrar, incluidos los sidecars `-wal`/`-shm`/`-journal`) vive en `lib/data/datasources/local/db_recovery.dart`, que importa **solo `dart:io`**. Se prueba con un directorio temporal real, sin sqflite, sin `path_provider`, sin plugins y sin dependencias nuevas.
- El pegamento restante en `AppDatabase.init()` (llamar al helper y reabrir) queda cubierto por el chequeo estático `grep -rn "deleteDatabase(" lib/` → 0 y por la QA manual en dispositivo.

Por el mismo criterio se descartaron los widget tests de `HomePage` completa (`home_page_gesture_test.dart` / `home_page_mode_test.dart` propuestos por el research): exigirían montar todo el grafo de `getIt` + Provider (`RecorderService`, `MonitorUserLocationUseCase` con 6 repositorios, `DiagnosticsPanel`) para verificar un booleano de una línea. En su lugar se extrajeron las piezas con lógica real a widgets propios sin DI (`HiddenTapGesture`, `UserModeView`), que sí se prueban directamente.

---

## Sampling Rate

- **After every task commit:** `flutter test`
- **After every plan wave:** `flutter test` + `flutter analyze`
- **Before `/gsd:verify-work`:** suite verde + auditoría ponytail (plan 01-04 task 1) + QA manual (plan 01-04 task 2)
- **Max feedback latency:** 30 segundos

---

## Per-Task Verification Map

Archivos de test realmente creados en la fase (los 4 exigidos por el plan 01-04):

| Test File | Plan | Requirement | Automated Command | Status |
|-----------|------|-------------|-------------------|--------|
| `test/data/datasources/local/db_recovery_test.dart` | 01-01 | DATA-01 | `flutter test test/data/datasources/local/db_recovery_test.dart` | ✅ green |
| `test/core/config/app_mode_config_test.dart` | 01-02 | UI-01 | `flutter test test/core/config/app_mode_config_test.dart` | ✅ green |
| `test/presentation/widgets/hidden_tap_gesture_test.dart` | 01-02 | UI-01 | `flutter test test/presentation/widgets/hidden_tap_gesture_test.dart` | ✅ green |
| `test/presentation/pages/home/widgets/user_mode_view_test.dart` | 01-02 | UI-01 | `flutter test test/presentation/pages/home/widgets/user_mode_view_test.dart` | ✅ green |

Verificación estática + suite completa por plan:

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 01-01-01 | 01 | 1 | DATA-01 | unit | `flutter test test/data/datasources/local/db_recovery_test.dart` | ✅ green |
| 01-01-02 | 01 | 1 | DATA-02 | static + suite | `flutter analyze` + `flutter test` + `grep -rn "recreateForTesting\|importDatabase\|file_picker\|deleteDatabase(" lib/ test/` → 0 | ✅ green |
| 01-02-01 | 02 | 1 | UI-01 | unit | `flutter test test/core/config/app_mode_config_test.dart` | ✅ green |
| 01-02-02 | 02 | 1 | UI-01 | widget | `flutter test test/presentation/widgets/hidden_tap_gesture_test.dart` | ✅ green |
| 01-02-03 | 02 | 1 | UI-01 | widget | `flutter test test/presentation/pages/home/widgets/user_mode_view_test.dart` | ✅ green |
| 01-03-01 | 03 | 2 | UI-01 | static + suite | `flutter analyze` + `flutter test` + greps de `<acceptance_criteria>` del plan 01-03 | ✅ green |
| 01-03-02 | 03 | 2 | DATA-01 | static + suite | `flutter analyze` + `flutter test` + `grep -c "showDialog" lib/presentation/pages/home_page_impl.dart` → 0 | ✅ green |
| 01-04-01 | 04 | 3 | DATA-01/02, UI-01 | suite + static | `flutter analyze` + `flutter test` + greps de completitud | ✅ green |
| 01-04-02 | 04 | 3 | DATA-01, UI-01 | manual (checkpoint) | ver "Manual-Only Verifications" | ⬜ pending (aguarda QA en dispositivo real) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

No hay 3 tareas consecutivas sin verificación automatizada: cada tarea de los planes 01-01 a 01-04 corre al menos `flutter test`.

---

## Wave 0 Requirements

Ninguno. Los 4 archivos de test los crea la tarea que implementa el código correspondiente (tareas marcadas `tdd="true"` en los planes 01-01 y 01-02, con el bloque `<behavior>` fijando los casos antes de escribir la implementación). No hay ningún `<verify>` que apunte a un archivo que no exista al momento de correrse.

*(No hacen falta fixtures compartidos — cada archivo de test es autocontenido, según la convención del repo.)*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|--------------------|
| Arranque en frío tras corromper `cingula.db`: la app abre normal (sin UI bloqueante), muestra el `MaterialBanner` con el copy del UI-SPEC, y el archivo renombrado queda en disco | DATA-01 | Requiere manipular el estado real del filesystem del sandbox de la app en un dispositivo; automatizarlo pediría un integration test con `adb` para un evento de arranque único | Plan 01-04, task 2, pasos 9-13 (incluye los comandos `adb run-as`) |
| Persistencia del toggle entre reinicios reales de la app, y que el gesto de 5 taps sea alcanzable/no descubrible en el AppBar real | UI-01 | `SharedPreferences` está mockeado en tests (no hay reinicio de proceso real); la ergonomía del gesto sobre el AppBar solo se juzga en dispositivo | Plan 01-04, task 2, pasos 1-7 |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** firmado en el plan 01-04, task 1 (auditoría ponytail completa, `flutter analyze`/`flutter test` verdes, greps de completitud en cero). La fila 01-04-02 (QA manual en dispositivo) queda `⬜ pending` hasta que el checkpoint humano del task 2 se resuelva.
