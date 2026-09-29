---
phase: 11-infra-de-deploy-mismo-proyecto-vercel
plan: 05
subsystem: infra-deploy
tags: [vercel, ponytail, merge, db-integrity, INFRA-01, INFRA-02, INFRA-03]

requires:
  - phase: 11-01
    provides: "smoke-preview.sh, web/ limpio de Flutter"
  - phase: 11-02
    provides: "INFRA-02 verificado, proyecto Vercel real linkeado"
  - phase: 11-03
    provides: "ruteo /sync/* (mecanismo revisado el mismo día: merge backend/ -> web/, sin shim)"
  - phase: 11-04
    provides: "Preview real verificado, Root Directory = web"
provides:
  - "Fase 11 cerrada: web/ es la única fuente de la API de sync (backend/ ya no existe), ws/web mergeado a main, producción real verificada post-merge"
  - "web/.vercelignore: excluye *.test.js del deploy (hallazgo ponytail del plan 04)"
  - "lib/data/migration/db_backup.dart: fix de un bug real no relacionado a infra (sqflite database_closed), encontrado durante este plan al verificar el push real del celular"
affects: [12]

tech-stack:
  added: []
  patterns:
    - "web/.vercelignore para excluir archivos de test del descubrimiento automático de funciones de Vercel"
    - "sqflite singleInstance: false para conexiones 'de paso' (peek) que no deben interferir con la conexión real de la app al mismo path"

key-files:
  created:
    - web/.vercelignore
  modified:
    - lib/data/migration/db_backup.dart
    - test/data/migration/db_backup_test.dart
    - .planning/workstreams/web/phases/11-infra-de-deploy-mismo-proyecto-vercel/11-VALIDATION.md

key-decisions:
  - "Auditoría ponytail adaptada a la estructura real (backend/ disuelto en 11-03/pre-checkpoint-04), no a la que el plan 05 asumía al planificarse. Documentado explícitamente en 11-VALIDATION.md para que no se lea como incumplimiento del plan original."
  - "El bug de sqflite (DatabaseException(database_closed)) encontrado durante la compuerta humana de este plan se arregló y commiteó por separado (2f4f2c6) del trabajo de infra — no es INFRA-01/02/03, es una corrección de la app misma, a pedido explícito del usuario."
  - "Verificación del push real del celular se hizo por consulta DIRECTA a Postgres de producción (leyendo DATABASE_URL, que es Config, no Secret) en vez de por la API con key — más fuerte como evidencia (confirma la fila real, no solo un 200 HTTP) y no requiere la SYNC_API_KEY del celular, que es Secret y no legible."

requirements-completed: [INFRA-01, INFRA-02, INFRA-03]

duration: ~2h (incluye una interrupción de ~1h por el bug de sqflite, no planificada)
completed: 2026-09-29
---

# Phase 11 Plan 05: Cierre de fase — auditoría ponytail + merge a main Summary

**Auditoría ponytail de la config de ruteo (adaptada al merge `backend/`→`web/` del mismo día), fix de un bug real de `sqflite` encontrado en el camino, merge de `ws/web` a `main`, y verificación end-to-end con dos pushes reales del celular (pre y post merge, uno de ellos grabado offline) confirmados por consulta directa a la base de producción.**

## Performance

- **Duration:** ~2h (incluye ~1h de interrupción no planificada: bug de `sqflite` encontrado durante la verificación del celular)
- **Completed:** 2026-09-29
- **Tasks:** 3/3

## Accomplishments

- **Auditoría ponytail (Task 1):** con `backend/` ya disuelto (decisión tomada horas antes, ver `11-03-SUMMARY.md` addendum), los 9 chequeos A-I del plan original se adaptaron a la estructura real: un solo `vercel.json` (`web/vercel.json`, solo el rewrite), `web/package.json` sin deps extra, scripts sin secretos impresos, sin restos de spike, README sin instrucciones viejas, `npm test` verde. Único hallazgo real: Vercel desplegaba `*.test.js` de `api/` como funciones (encontrado en 11-04) — resuelto con `web/.vercelignore`.
- **Verificación pre-merge (Task 2):** `check-preview-db.sh` y `smoke-preview.sh` corridos contra el Preview auditado (`SMOKE OK`), y push real del celular contra producción confirmado por consulta directa a Postgres (fila `"Mi rutaggfgg"`, `updated_at` a ~19 minutos del `now()` del servidor).
- **Bug real encontrado y arreglado en el camino:** al pedirle al usuario el push de prueba pre-merge, reportó `DatabaseException(database_closed 2)` en CUALQUIER operación de base, desde el arranque de la app — nada que ver con este plan, pero bloqueante para completar la verificación. Diagnosticado con `adb logcat` en el celular real: `lib/data/migration/db_backup.dart` abría y cerraba una conexión "de paso" (`backupBeforeMigration`, chequeo de versión pre-migración) sobre el MISMO path que `AppDatabase.init()` reabre inmediatamente después — con `singleInstance: true` (default de `sqflite`), ambas comparten la caché de conexión por path, y el `close()` de la primera dejaba inutilizable la conexión "real". Fix: `singleInstance: false` en la conexión de paso. Commiteado por separado (`2f4f2c6`), no como parte de INFRA-01/02/03.
- **Merge a `main`:** el usuario mergeó `ws/web` (PR #1). Deploy de producción nuevo verificado `Ready`, 3 funciones reales desplegadas (`api/sync/{pull,push,state}`, sin archivos de test gracias al `.vercelignore`).
- **Verificación post-merge:** `SMOKE OK` contra `https://cingula.vercel.app` (chequeo de ruteo). Push real del celular repetido — esta vez grabado con el celular DESCONECTADO y sincronizado al reconectar (outbox local, RNF-03) — confirmado por consulta directa: fila `"Mi ruta prueba ultima ahora"`, `updated_at` a ~2 minutos del `now()` del servidor en el momento de la consulta.
- `11-VALIDATION.md` cerrado: `status: complete`, `nyquist_compliant: true`, tabla de verificación reescrita con los comandos y resultados reales (paths `web/`, no `backend/`), Sign-Off completo.

## Task Commits

1. **Task 1: Auditoría ponytail** - `9a8c2a9` (chore) — excluye `*.test.js` del deploy
2. **Task 2: Compuerta humana** - sin commit propio (verificación); el fix de `db_backup.dart` que surgió en el medio se commiteó aparte: `2f4f2c6` (fix)
3. **Task 3: Cerrar 11-VALIDATION.md** - (this commit) `docs(11-05): close phase 11 validation`

**Plan metadata:** el merge de `ws/web` → `main` lo hizo el usuario (PR #1, `5b1ac2f`), no un commit de este agente.

## Files Created/Modified

- `web/.vercelignore` - excluye `**/*.test.js` del descubrimiento de funciones de Vercel (11-04 lo encontró, 11-05 lo resolvió)
- `lib/data/migration/db_backup.dart` - `singleInstance: false` en la conexión de chequeo pre-migración
- `test/data/migration/db_backup_test.dart` - test de regresión agregado (documenta el escenario; NO reproduce el bug en `sqflite_common_ffi`, la verificación real es en dispositivo)
- `.planning/workstreams/web/phases/11-infra-de-deploy-mismo-proyecto-vercel/11-VALIDATION.md` - cerrado con resultados reales

## Decisions Made

Ver `key-decisions` en el frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Bug real no relacionado a INFRA-*, encontrado durante la compuerta humana] `DatabaseException(database_closed)` en sqflite**
- **Encontrado durante:** Task 2, cuando el usuario probó el push real del celular pre-merge (paso 1 de la compuerta) y reportó que la app tiraba error en cualquier operación de base, incluso al arrancar.
- **Diagnóstico:** `adb logcat` en el dispositivo real mostró el stack trace completo apuntando a `ObraLocalDataSource.getAll` fallando en la primera query del home. Sin ningún rename/recovery de por medio (la base NO estaba corrupta) — confirmando que el problema era la conexión, no los datos.
- **Causa raíz:** `backupBeforeMigration()` en `lib/data/migration/db_backup.dart` abre `dbPath` con las opciones default de `sqflite` (`singleInstance: true`), corre `PRAGMA user_version`, cierra. `AppDatabase.init()` reabre el MISMO path inmediatamente después, también `singleInstance: true`. `sqflite` cachea conexiones por path bajo `singleInstance`; el `close()` de la primera función dejaba la conexión que `AppDatabase` obtiene después inutilizable, sin ningún error visible durante el arranque — recién fallaba en la primera query real.
- **Fix:** pasar `options: OpenDatabaseOptions(singleInstance: false)` en la apertura "de paso" de `backupBeforeMigration`, aislándola completamente de la caché que usa la conexión real de la app.
- **Verificación:** reproducido y confirmado arreglado en el dispositivo real del usuario vía `adb logcat` (build debug con `flutter build apk --debug` + `adb install -r`, dos veces: una para reproducir/arreglar el bug, otra porque la primera build se hizo sin `--dart-define-from-file=dart_defines.json` por error del agente, apuntando el celular a `localhost:3000` en vez de producción — corregido copiando `dart_defines.json` desde el checkout hermano `cingula-app` sin leer su contenido, y rebuildeando).
- **Impacto en este plan:** ninguno sobre INFRA-01/02/03 — es una corrección de la app, commiteada por separado a pedido explícito del usuario (`git commit` fuera del flujo de plan/tasks de GSD, ver `2f4f2c6`).
- **Nota para el equipo:** ningún test de la suite existente (que corre sobre `sqflite_common_ffi`, no el plugin Android real) reproduce este bug — la FFI no implementa la misma caché por singleInstance que el plugin real. La verificación de esta clase de bug tiene que ser en dispositivo.

**2. [Error del agente, auto-corregido] Build debug instalado sin dart-defines, celular apuntó a `localhost:3000`**
- **Encontrado durante:** verificación post-fix del bug de sqflite — el usuario reportó "error de red" apuntando a `localhost:3000`.
- **Causa:** el agente corrió `flutter build apk --debug` sin `--dart-define-from-file=dart_defines.json` (el archivo no existe en este worktree, está gitignoreado). El build cayó al default de `ApiConfig` (`http://localhost:3000`), sobreescribiendo el build correctamente configurado que el usuario ya tenía instalado.
- **Fix:** localizado `dart_defines.json` en el checkout hermano (`cingula-app/dart_defines.json`), copiado SIN leer su contenido (contiene la API key real de producción) al worktree de este plan, rebuild con `--dart-define-from-file`, reinstalado.
- **Impacto:** ninguno permanente — el celular volvió a apuntar a producción correctamente tras el segundo build.

---

**Total deviations:** 2 (1 bug real de la app arreglado por separado, 1 error operativo del agente auto-corregido)
**Impact on plan:** Ninguno sobre el resultado — INFRA-01, INFRA-02 e INFRA-03 verificados end-to-end, fase mergeada y confirmada en producción real con evidencia de dos pushes reales del celular.

## Issues Encountered

Ver Deviations arriba.

## User Setup Required

Ninguno pendiente. Completado durante este plan: merge a `main` (usuario, vía PR #1).

## Next Phase Readiness

- Fase 12 (Web de lectura, SPA completa) puede empezar: `web/` es ahora la Root Directory real del proyecto Vercel único, con la API de sync ya sirviendo desde ahí. La SPA de la Fase 12 se suma al mismo `web/`, sin necesidad de tocar Root Directory de nuevo.
- Pendiente para Notion/ADR-005 (acumulado de 11-02, 11-03, 11-04): registrar la decisión final (backend/ disuelto en web/, no shims), el bypass secret, WEB_API_KEY nueva, el hallazgo de env-vars-necesitan-redeploy, y el bug de sqflite arreglado en el camino (aunque no es de esta fase, es relevante para cualquiera que audite por qué el commit `2f4f2c6` no tiene requirement INFRA-* asociado).
- `web/README.md` ya documenta el flujo completo (dev, deploy, smoke) para quien retome desde acá.

## Known Stubs

Ninguno.

---
*Phase: 11-infra-de-deploy-mismo-proyecto-vercel*
*Completed: 2026-09-29*

## Self-Check: PASSED

- FOUND: web/.vercelignore
- VERIFIED: lib/data/migration/db_backup.dart tiene `singleInstance: false`
- VERIFIED: `main` en GitHub incluye el merge de `ws/web` (commit `5b1ac2f`)
- VERIFIED: producción (`cingula.vercel.app`) -> `SMOKE OK`, 3 funciones reales desplegadas, sin archivos de test
- VERIFIED: dos filas reales en `paths` de producción confirman push pre y post merge del celular
- VERIFIED: 11-VALIDATION.md -> `nyquist_compliant: true`, `status: complete`, Sign-Off completo
