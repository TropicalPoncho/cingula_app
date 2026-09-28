# cingula-sync-backend

Vercel Functions (`/sync/push`, `/sync/state`, `/sync/pull`) sobre Neon Postgres. Implementa el
contrato HTTP documentado en `.planning/workstreams/app/phases/02-backend-real-push-sync/02-02-PLAN.md`.

## Setup

```bash
cd backend
npm install
cp .env.example .env   # completar DATABASE_URL y SYNC_API_KEY
```

`WEB_API_KEY` (opcional): clave de solo lectura para la web (pull/state; el push la rechaza con
403). Contrato de pull: Notion, ERS · Backend — protocolo de sync.

## Test

```bash
npm test
```

Los tests de integración (`api/sync/push.test.js`) requieren `DATABASE_URL` apuntando
a una branch de Neon; sin esa env var se saltean (verde igual).

## Dev local

Las funciones viven en `backend/api/` pero Vercel solo descubre funciones dentro de
`<Root Directory>/api`. Por eso `backend/api/` **no se mueve** (ADR-005: mantiene su propio
`package.json`, tests y `.env.example` autocontenidos) — en cambio, `web/api/sync/{push,pull,state}.js`
re-exportan (`export { default } from '../../../backend/api/sync/<f>.js'`) el handler real, y el
proyecto Vercel usa **Root Directory = `web`**. `web/vercel.json` tiene el rewrite
`/sync/:path* -> /api/sync/:path*` y el `installCommand: npm ci --prefix ../backend` (así el
deploy instala las deps de `backend/`, no solo las de `web/`). Función nueva en `backend/api/sync/`
= shim nuevo en `web/api/sync/`.

```bash
npx vercel@latest dev
```

Corrido desde la raíz del repo linkeada al proyecto real (Root Directory `web` en la config del
proyecto). Development usa la rama Neon `dev`.

Nota: un spike local de este mecanismo (fase 11, plan 03) encontró que `vercel dev`
(`@vercel/node@16.0.1`, CLI 60.1.3, Node 22.14, Windows) crashea al invocar CUALQUIER función local
(hasta un handler sin imports) — `500 FUNCTION_INVOCATION_FAILED`, subproceso del builder muere al
arrancar. El ruteo/descubrimiento sí se validó (rutas reales dan 500 "encontrada, intentó invocar"
vs. rutas inexistentes dan 404; los estáticos sirven bien desde la misma Root Directory) — es un bug
de la herramienta de dev local, no del mecanismo de ruteo. La evidencia real (`SMOKE OK`, 401/405
JSON) se obtiene contra el primer Preview real (fase 11, plan 04), que no pasa por este código local.

## Deploy

Antes de mergear a `main`:

```bash
bash backend/scripts/smoke-preview.sh <preview-url>          # SMOKE_API_KEY/VERCEL_BYPASS opcionales
bash backend/scripts/check-preview-db.sh <rama-git>
```

`smoke-preview.sh` confirma que `/sync/state` responde JSON de la función (no HTML de un
rewrite/SPA-fallback/Deployment Protection mal configurado). `check-preview-db.sh` confirma que
Preview/Development no usan el host de `DATABASE_URL` de Production.
