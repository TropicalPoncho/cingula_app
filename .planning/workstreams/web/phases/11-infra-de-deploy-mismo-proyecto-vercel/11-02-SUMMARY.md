---
phase: 11-infra-de-deploy-mismo-proyecto-vercel
plan: 02
subsystem: infra-deploy
status: complete
tags: [vercel, neon, infra, INFRA-02]
requires: []
provides:
  - "backend/scripts/check-preview-db.sh: verificación repetible de host de DATABASE_URL por entorno"
  - "Preview + Development apuntan a la rama Neon dev nueva (ep-calm-dream-awxrq5ul), Production aislado"
affects:
  - "plan 11-04: puede crear el primer Preview real — INFRA-02 cerrado, ya no bloquea"
tech-stack:
  added: []
  patterns:
    - "Verificación de config por HOST únicamente (nunca connection string completa) vía `vercel env pull` a un tmpdir con trap de borrado"
key-files:
  created:
    - backend/scripts/check-preview-db.sh
    - .gitattributes
  modified:
    - .gitignore
decisions:
  - "DATABASE_URL en Vercel: la integración Neon (`cingula-back`) no expone (ni en el dashboard de Storage de este tipo de integración, solo 'Update Name', ni por CLI) un toggle de 'create a database branch for deployment' — se trató como efectivamente OFF/no aplicable a esta integración. Se usó Rama A: `DATABASE_URL` manual con scope Preview (branch-specific, `--git-branch=ws/web`) + Development, apuntando a una rama Neon nueva creada desde `main` (la rama dev original había sido borrada). Production quedó con su `DATABASE_URL` de integración (scope Production/Preview original) sin tocar — el override manual por variable con mismo nombre + scope más específico gana."
  - ".gitattributes con '*.sh text eol=lf' agregado (deviation Rule 1/3): core.autocrlf=true en Windows convierte LF->CRLF al commitear, lo que rompe el shebang de check-preview-db.sh en cualquier checkout Linux/CI. Sin este archivo el script 'repetible' se hubiera roto la primera vez que alguien lo corriera fuera de Windows."
metrics:
  duration: "~2h (incluye 2 pausas de checkpoint humano)"
  completed: "2026-09-28"
---

# Phase 11 Plan 02: Infra de deploy — verificación INFRA-02 (Vercel/Neon) Summary

**Estado: COMPLETO.** `check-preview-db.sh` da `INFRA-02 OK`: Preview y Development apuntan a una
rama Neon dev nueva, distinta del host de Production.

Relevamiento real del proyecto Vercel (Task 1, sin credenciales guardadas en el repo) + script
repetible de verificación de host de `DATABASE_URL` por entorno (Task 2, commiteado). El baseline
inicial dio `INFRA-02 FAIL: preview usa el mismo host que production` — confirmó el riesgo que
ADR-005 marcaba como "sin verificar". Task 3 corrigió los scopes en Vercel (Rama A: variable manual
apuntando a una rama Neon nueva) y la re-verificación post-fix da `INFRA-02 OK`.

## Task 1 — Relevamiento (sin secretos)

| # | Pregunta | Respuesta |
|---|---|---|
| a | Proyecto / scope | `cingula` en team `Rama's projects`, slug real `ramas-projects-e2ba61a0` (descubierto vía `vercel teams ls`, no asumido) |
| b | Root Directory | `backend` — confirmado también por `vercel project inspect cingula` |
| c | Git conectado | `tropicalponcho/cingula_app`, Production Branch `main` — confirmado |
| d | Deployment Protection | "Vercel Authentication" activo; alcance (¿solo Preview?) no confirmado por el usuario ("no lo dice"). Sin "Protection Bypass for Automation". **Riesgo para más adelante**: el smoke test del plan 04 contra un deploy Preview puede recibir una página HTML de login de Vercel en vez de JSON — no bloquea este plan, queda anotado para plan 04. |
| e | Integración Neon | Conectada (`cingula-back`, Neon Free, resource `store_eSXUJQmSQ3McizD1`), cubre `production` y `preview` (confirmado por `vercel integration-resource inspect cingula-back`). Si "create a database branch for deployment" está activo no se pudo determinar por CLI (no expuesto en `integration-resource inspect`; es un toggle solo de dashboard) — ver pregunta pendiente para Task 3. |
| f | Rama dev de Neon | No existe — el usuario la eliminó. Invalida el supuesto "Rama A" original del plan (reusar rama dev existente). |
| g | Dominio de producción | `cingula.vercel.app` |

## Task 2 — Link, inventario y script (commit `b14cefd`)

`npx vercel@latest link --yes --project cingula --scope ramas-projects-e2ba61a0` desde la raíz.
`.vercel/` queda ignorado (`.gitignore` + `.gitattributes` nuevo para forzar LF en `*.sh`,
ver Deviations). `git status --porcelain` no mostró `.vercel` en ningún momento.

### Inventario de env vars (`vercel env ls`, solo nombres/scopes, sin valores)

| Variable | Tipo | Entornos | Origen |
|---|---|---|---|
| `DATABASE_URL` | Config | Production, Preview | Integración Neon (`cingula-back`) |
| `DATABASE_URL_UNPOOLED`, `POSTGRES_*`, `PG*`, `NEON_PROJECT_ID` (14 vars más) | Config | Production, Preview | Integración Neon, mismo grupo que `DATABASE_URL` |
| `SYNC_API_KEY` | Secret | Production, Development, **Preview** | Manual (Fase 2/10) |
| `WEB_API_KEY` | — | **ninguno** | No existe todavía en Vercel — gap real, pero fuera del alcance de Rama B en este plan (ver Task 3 del PLAN); queda para plan 04 o antes si hace falta para el smoke test |

Nota: no hay ninguna entrada con scope `Development` para `DATABASE_URL` (ni sus variantes
`POSTGRES_*`/`PG*`) — la integración Neon solo cubre Production+Preview, nunca Development.

### Baseline de `check-preview-db.sh ws/web` (solo hosts, corrida real)

```
production: ep-fancy-waterfall-aw1wz0ru-pooler.c-12.us-east-1.aws.neon.tech
preview(ws/web): ep-fancy-waterfall-aw1wz0ru-pooler.c-12.us-east-1.aws.neon.tech
development: VACÍO
INFRA-02 FAIL: preview usa el mismo host que production
```

**Esto confirma el riesgo de ADR-005**: hoy, sin ningún deploy Preview real todavía hecho sobre
`ws/web`, un `env pull --environment=preview` devuelve el mismo host `ep-fancy-waterfall-...` que
Production. Si el plan 04 desplegara un Preview ahora mismo (antes de cerrar este plan), ese
deploy leería y escribiría la base de PRODUCCIÓN.

No se puede determinar solo con esta corrida si esto es (a) la integración Neon con "create a
database branch for deployment" **desactivado** (Preview siempre apunta a la rama principal), o
(b) el toggle está **activado** pero el branch-per-deploy recién se crea cuando existe un deploy
Preview real para esa rama git (no hay ninguno todavía) — en cuyo caso el `env pull` manual, sin
deploy, cae al valor base (= producción) y este mismo resultado sería esperable incluso con la
integración funcionando bien.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `.gitattributes` con `*.sh text eol=lf`**
- **Encontrado durante:** Task 2, al hacer `git add` de `check-preview-db.sh`
- **Problema:** `core.autocrlf=true` en Windows iba a convertir el script a CRLF al commitear,
  rompiendo el shebang (`#!/usr/bin/env bash\r`) en cualquier checkout Linux/CI — el script deja
  de ser "repetible" (requisito explícito del plan) apenas alguien lo corre fuera de Windows.
- **Fix:** `.gitattributes` en la raíz forzando `eol=lf` para `*.sh`, `git add --renormalize`
  antes de commitear. Verificado con `git show :backend/scripts/check-preview-db.sh | od -c` — el
  blob commiteado tiene `\n`, no `\r\n`.
- **Archivos:** `.gitattributes` (nuevo)
- **Commit:** `b14cefd`

## Task 3 — corrección de scopes (Rama A) y verificación final

**Hallazgo que cerró la ambigüedad Rama A/B:** en el dashboard de Storage para esta integración
Neon (Marketplace, no la integración nativa "Neon for Vercel" con branching por deploy) la única
opción visible en Settings es "Update Name" — no existe el toggle "create a database branch for
deployment" para este tipo de conexión. Se trató como efectivamente OFF/no aplicable, y se usó
**Rama A** del plan: `DATABASE_URL` manual, con scope más específico que el de la integración, para
que gane sobre el valor de Production en Preview/Development.

**Pasos ejecutados por el usuario (fuera del alcance de credenciales del agente):**
1. Rama Neon nueva creada desde `main` en Neon Console (la rama `dev` original de la Fase 10 había
   sido eliminada — invalida el supuesto original del plan de "reusar la rama dev que ya existe").
2. `npx vercel@latest env add DATABASE_URL preview --git-branch=ws/web` y
   `npx vercel@latest env add DATABASE_URL development`, con el connection string pooled de la
   rama nueva pasado por prompt interactivo (nunca escrito a un archivo del repo ni al historial
   de shell).
3. `bash backend/scripts/check-preview-db.sh ws/web` corrido por el usuario desde la raíz, post-fix:

```
production: ep-fancy-waterfall-aw1wz0ru-pooler.c-12.us-east-1.aws.neon.tech
preview(ws/web): ep-calm-dream-awxrq5ul-pooler.c-12.us-east-1.aws.neon.tech
development: ep-calm-dream-awxrq5ul-pooler.c-12.us-east-1.aws.neon.tech
INFRA-02 OK: preview y development no usan el host de producción
```

Preview y Development comparten el host `ep-calm-dream-awxrq5ul-...` (la rama Neon nueva),
distinto del host de Production (`ep-fancy-waterfall-aw1wz0ru-...`). **INFRA-02 verificado, no
asumido.**

### Gotchas encontrados durante Task 3 (para ADR-005 en Notion y para quien repita este proceso)

1. **`vercel env pull --environment=preview --git-branch=<rama>` requiere que esa rama exista en
   el remoto de Git conectado al proyecto** (`tropicalponcho/cingula_app`). `ws/web` era una rama
   de worktree local que todavía no se había pusheado — el pull para esa rama fallaba/no
   resolvía el override branch-specific hasta que se hizo `git push` de `ws/web` al remoto. Riesgo
   para cualquier variable de entorno scoped-by-git-branch a futuro (no solo `DATABASE_URL`): si la
   rama no existe en GitHub, Vercel no puede aplicar el override y cae silenciosamente al valor
   base del entorno.
2. **`vercel env add` sin `--no-sensitive` marca la variable como Secret (Sensitive) por
   default**, y `vercel env pull` no puede bajar el valor real de una variable Sensitive — imprime
   un placeholder `[SENSITIVE]` en su lugar. Esto es más grave que el caso "vacío" que el plan ya
   contemplaba: el placeholder es una cadena **no vacía y distinta del host de producción**, así
   que `check-preview-db.sh` la habría interpretado como un host real distinto y reportado
   `INFRA-02 OK` **sin haber verificado nada** — un falso positivo silencioso sobre exactamente la
   garantía que este script existe para dar. Se corrigió borrando y re-agregando ambas variables
   (`vercel env rm DATABASE_URL preview ws/web --yes`, `vercel env rm DATABASE_URL development
   --yes`) con `--no-sensitive`. **Toda variable que `check-preview-db.sh` necesite leer por host
   tiene que agregarse con `--no-sensitive`, o el script no puede verificar nada y no lo va a
   avisar.**

Ambos puntos quedan para la nota que este plan pide agregar a ADR-005 en Notion al cierre de fase.

## Known Stubs

Ninguno — este plan no toca UI ni lógica de aplicación.

## Self-Check: PASSED

- `backend/scripts/check-preview-db.sh` — FOUND (creado y commiteado en `b14cefd`)
- `.gitattributes` — FOUND (creado y commiteado en `b14cefd`)
- `.gitignore` modificado con `.vercel/` — FOUND (`grep -n "^\.vercel/" .gitignore` da 1 línea)
- commit `b14cefd` — FOUND (`git log --oneline` lo muestra)
- Task 3 (corrección de scopes en Vercel): ejecutada por el usuario fuera del repo (config de
  Vercel, no hay archivo/commit que verificar en el árbol de trabajo); verificación es la salida
  de `check-preview-db.sh` pegada arriba, provista por el usuario tras correr el script él mismo
  post-fix — no re-ejecutada por el agente a pedido explícito del usuario.
