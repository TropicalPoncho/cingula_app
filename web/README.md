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
npm test            # backend (node:test), sólo api/ y scripts/
npm run test:ui     # SPA: Vitest (jsdom), sólo src/**/*.spec.{js,jsx}
npm run test:e2e    # SPA: Playwright (Chromium), red mockeada; levanta vite en :5173
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

### SPA de lectura (Fase 12)

La SPA (Vite + React 19, JS sin TypeScript) vive en `web/src/` y se sirve desde el MISMO proyecto
Vercel que `web/api/` (mismo origen: sin CORS, CSP `connect-src 'self'`).

```bash
cd web && npm run dev     # Vite en :5173; proxy de /sync a https://cingula.vercel.app (DEV_API_TARGET lo cambia)
```

- El login en dev usa la `WEB_API_KEY` de **Production** (la crea el plan 12-03); el proxy nunca
  inyecta claves, la clave se tipea en `/acceso` y vive sólo en `sessionStorage`.
- La CSP y los demás headers sólo se aplican en Vercel (no en `vite dev`).
- `vercel dev` sigue roto en este equipo (ver nota abajo, H1): el gate de ruteo es un Preview real
  más `scripts/smoke-preview.sh`.

`web/vercel.json`: `framework: vite`, build a `dist/`, y el rewrite `/sync/:path*` -> `/api/sync/:path*`
declarado PRIMERO, antes del fallback SPA (`/:path((?!api/|sync/|assets/)[^.]*)` -> `/index.html`).
Invertir ese orden o relajar las exclusiones puede tragarse `/sync/push` del celular en producción.

Nota: un spike local de este mecanismo (fase 11, plan 03) encontró que `vercel dev`
(`@vercel/node@16.0.1`, CLI 60.1.3, Node 22.14, Windows) crashea al invocar CUALQUIER función local
(hasta un handler sin imports) — `500 FUNCTION_INVOCATION_FAILED`, subproceso del builder muere al
arrancar. El ruteo/descubrimiento sí se validó (rutas reales dan 500 "encontrada, intentó invocar"
vs. rutas inexistentes dan 404; los estáticos sirven bien desde la misma Root Directory) — es un bug
de la herramienta de dev local, no del mecanismo de ruteo. La evidencia real (`SMOKE OK`, 401/405
JSON) se obtiene contra un Preview real, que no pasa por este código local.

## Deploy

Antes de mergear a `main` el smoke extendido es **obligatorio**:

```bash
VERCEL_BYPASS=... bash web/scripts/smoke-preview.sh <preview-url>   # SMOKE_API_KEY opcional
bash web/scripts/check-preview-db.sh <rama-git>
```

`smoke-preview.sh` (sólo GET) confirma: `/sync/state` y `/api/sync/*` responden JSON de las
funciones (401/405, no HTML), un deep link (`/obras/x`) devuelve el `index.html` de la SPA, un asset
inexistente no devuelve HTML, y `/` trae CSP con `frame-ancestors 'none'`, `Referrer-Policy` y
`nosniff`. `VERCEL_BYPASS` (Protection Bypass for Automation) se pasa por el entorno de la sesión,
nunca en un archivo. `check-preview-db.sh` confirma que Preview/Development no usan el host de
`DATABASE_URL` de Production.
