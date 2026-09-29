---
status: partial
phase: 01-blindaje-de-datos-y-separaci-n-debug-usuario
source: [01-VERIFICATION.md]
started: 2026-08-28T00:00:00.000Z
updated: 2026-08-28T00:00:00.000Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Recuperación no destructiva de la base de datos ante corrupción (DATA-01) — confirmación end-to-end en dispositivo real
expected: Con la base corrompida y la app cerrada, un arranque en frío (a) es usable sin bloqueo, (b) muestra el `MaterialBanner` "Base de datos restaurada automáticamente" nombrando el archivo `cingula.db.corrupto-<timestamp>`, y (c) deja en disco tanto la base nueva como el archivo corrupto renombrado (nunca borrado). Ver pasos 9-14 de `01-04-PLAN.md` Task 2.
result: [pending — deferido explícitamente por el usuario el 2026-08-28: no quiso corromper la base en su celular real (única copia de datos de campo) y declinó la alternativa de probarlo en un emulador. La lógica de renombrado está cubierta por `test/data/datasources/local/db_recovery_test.dart` (5 tests, verde), pero la confirmación humana del flujo completo `AppDatabase.init()` sobre hardware real con sqflite/path_provider no se hizo.]

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
