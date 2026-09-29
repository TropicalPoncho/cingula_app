# cingula-sync-backend

Vercel Functions (`/sync/push`, `/sync/state`, `/sync/pull`) sobre Neon Postgres. Implementa el
contrato HTTP documentado en `.planning/workstreams/app/phases/02-backend-real-push-sync/02-02-PLAN.md`.

## Setup

```bash
cd web
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

Las funciones viven en `web/api/` — es el mismo directorio que Vercel usa como Root Directory del
proyecto único (backend + futura web de gestión de la Fase 12). No hay indirección: Vercel descubre
y sirve directamente `web/api/sync/{push,pull,state}.js`. `web/vercel.json` tiene el rewrite
`/sync/:path* -> /api/sync/:path*`.

(Fase 11: hasta el plan 03 esto vivió separado en `backend/`, con `web/api/` como shims de
re-export — ADR-005 lo justificaba para mantener el backend autocontenido. Se descartó: es el
patrón atípico frente al estándar de Vercel de colocar `api/` junto al frontend que sirve, y backend
y web comparten la misma base de datos y evolucionan juntos. Todo se unificó en `web/`.)

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
bash web/scripts/smoke-preview.sh <preview-url>          # SMOKE_API_KEY/VERCEL_BYPASS opcionales
bash web/scripts/check-preview-db.sh <rama-git>
```

`smoke-preview.sh` confirma que `/sync/state` responde JSON de la función (no HTML de un
rewrite/SPA-fallback/Deployment Protection mal configurado). `check-preview-db.sh` confirma que
Preview/Development no usan el host de `DATABASE_URL` de Production.
