# Phase 11: Infra de deploy (mismo proyecto Vercel) - Context

**Gathered:** 2026-09-26
**Status:** Ready for planning

<domain>
## Phase Boundary

La web y el backend se sirven desde el mismo proyecto Vercel: `/sync/*` sigue llegando a las
funciones sin cambios de comportamiento (el celular real sincroniza contra producción hoy y no
puede notar el cambio), un deploy Preview usa una rama de Neon dev y nunca la `DATABASE_URL` de
producción, y `web/` queda libre de restos de Flutter web para alojar la SPA de la Fase 12.

Fuera de esta fase: la SPA en sí (Fase 12), pantalla de acceso/`AUTH-02` (Fase 12), storage de
audio (Fase 13), cualquier escritura desde la web.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

El usuario no tuvo preferencia en ninguna de las 4 áreas planteadas — quedan a criterio de research/planning, con estos defaults razonables:

- **Riesgo del cutover a producción:** no hace falta una ventana especial ni proceso de rollback
  formal más allá de lo que el propio ROADMAP ya exige (smoke test explícito de `GET /sync/state`
  devolviendo JSON válido en Preview, y confirmar que el push real del celular sigue funcionando,
  ambos ANTES de mergear a `main`). Si el smoke test pasa, aplicar el cambio; si no, no mergear.
  No se requiere coordinar con "que no haya grabación de campo en curso" — la app tolera
  conectividad intermitente por diseño (RNF-03), así que una ventana corta de `/sync/*` caído
  durante un deploy no arriesga datos (el outbox local reintenta).
- **Rama Neon dev:** verificar primero si ya existe una (con las tools de Neon/Vercel disponibles,
  o `vercel env ls` / consola de Neon); si no existe, esta fase la crea como parte de INFRA-02.
  Sin preferencia de nombre — usar algo descriptivo tipo `dev` o `preview`.
- **Mecanismo de ruteo:** sin preferencia previa sobre mover o no `backend/api/` — el spike de
  `vercel dev` (ya obligatorio por ROADMAP, criterio de éxito 1) decide objetivamente cuál de los
  3 mecanismos (shims de re-export, `functions` glob, mover `backend/api/` a la raíz) sirve tanto
  `/sync/*` como el resto del sitio. Preferir el que mueva menos archivos si dos opciones empatan en
  viabilidad (consistente con ADR-005: `backend/` es la carpeta propia del workstream `web`, evitar
  reestructurarla sin necesidad).
- **Limpieza de `web/`:** borrado total de los restos de Flutter web (`index.html`, `manifest.json`,
  `icons/`, `favicon.png`) sin conservar nada — la identidad visual de la SPA se define en la Fase 12
  desde cero, no hay razón para arrastrar un favicon de Flutter.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requisitos y roadmap
- `.planning/workstreams/web/ROADMAP.md` §Phase 11 — goal, 4 criterios de éxito, ponytail audit obligatorio como último plan/tarea
- `.planning/workstreams/web/REQUIREMENTS.md` — INFRA-01/02/03, tabla de decisiones del milestone (fila "`web/` se reusa: se borran los restos de Flutter web")
- `.planning/PROJECT.md` §ADRs — ADR-001 (Neon+Vercel), ADR-005 (monorepo, riesgo de Preview compartiendo `DATABASE_URL` con Production — sin verificar todavía)
- [Cíngula App — ADRs, ADR-005](https://app.notion.com/p/3e43d6cb9a5881749a19d3439a68a085) (Notion) — texto completo del riesgo: "Verificar (`vercel env ls` en `backend/`) antes del primer push de rama"

### Código y config existente
- `backend/vercel.json` — único `vercel.json` del repo hoy: `{"rewrites": [{"source": "/sync/:path*", "destination": "/api/sync/:path*"}]}`. Implica que el proyecto Vercel actual tiene Root Directory = `backend/`
- `backend/README.md` — confirma flujo actual: `cd backend && vercel dev` / `vercel link` corrido desde `backend/`, no desde la raíz del repo
- `backend/api/` — las 3 funciones existentes (`sync/push.js`, `sync/pull.js`, `sync/state.js`) y `_lib/` (`auth.js`, `db.js`, `spec.js`) — ninguna debe cambiar de comportamiento con el nuevo ruteo
- `web/` (raíz del repo) — restos de Flutter web a eliminar: `index.html`, `manifest.json`, `icons/`, `favicon.png`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Ninguno nuevo — esta fase es reconfiguración de deploy/ruteo, no código de aplicación.

### Established Patterns
- El rewrite `/sync/:path*` → `/api/sync/:path*` en `backend/vercel.json` ya resuelve el prefijo
  `/sync` para las 3 funciones existentes; cualquier mecanismo nuevo tiene que preservar esa regla
  (o su equivalente) sin que `app` (el celular) note el cambio.
- `backend/` es una unidad autocontenida (su propio `package.json`, `.env.example`, tests) — el
  research/spike debe evaluar el impacto de cualquier mecanismo sobre esa autocontención.

### Integration Points
- El proyecto Vercel único servirá: (a) las funciones de `backend/api/` sin cambios de comportamiento,
  y (b) el build estático/SPA que la Fase 12 pondrá en `web/` (todavía no existe — esta fase solo deja
  la carpeta limpia y lista, no construye la SPA).

</code_context>

<specifics>
## Specific Ideas

No hay ideas específicas — el usuario delegó las 4 áreas discutidas a criterio de research/planning
(ver Claude's Discretion arriba).

</specifics>

<deferred>
## Deferred Ideas

None — la discusión se mantuvo dentro del alcance de la fase.

</deferred>

---

*Phase: 11-infra-de-deploy-mismo-proyecto-vercel*
*Context gathered: 2026-09-26*
