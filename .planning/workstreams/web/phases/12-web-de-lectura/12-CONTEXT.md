# Phase 12: Web de lectura - Context

**Gathered:** 2026-09-30
**Status:** Ready for planning

<domain>
## Phase Boundary

El usuario abre la web, se autentica una vez con `WEB_API_KEY` (AUTH-02), y ve todo el contenido del
servidor (mapa, recorridos, obras, artistas, paths, audios inline, estado de sync) leyendo por el
mismo protocolo de pull que usa el celular (ADR-004, contrato cerrado en Phase 10). Es 100% lectura
— sin ningún formulario de creación/edición.

Fuera de esta fase: cualquier escritura desde la web (ADR-006, etapas 1 y 2 — ver Deferred), storage
de audio real (Phase 13 — reproducción de archivos que ya existan; STOR-04 es literalmente "indicar
cuando no hay archivo todavía", no subir/gestionar archivos).

</domain>

<decisions>
## Implementation Decisions

### Stack del frontend
- **D-01:** **Vite + React + Leaflet/OSM**, SPA client-side rendered — confirmado sobre Next.js.
  Razón: esta fase es de solo lectura para un único editor autenticado — ninguno de los beneficios
  de SSR (SEO, first-paint público) aplica. El costo real de un eventual pivot a producto público
  multi-usuario está en autenticación real (hoy es una sola `WEB_API_KEY`) y en el modelo de datos
  (hoy sin concepto de "dueño" de un recorrido/obra) — ninguno de los dos depende del framework de
  frontend. Migrar de Vite a Next.js más adelante es trabajo acotado (componentes/hooks se llevan
  casi 1:1; cambia sobre todo el ruteo), así que no vale la pena pagar la complejidad de Next.js hoy
  para un problema todavía no validado.
  - Alternativa descartada: Next.js — se reconsideraría solo si en el futuro la web se abre a
    público general Y ese público necesita descubrir recorridos por SEO/búsqueda (no solo gestión
    por editores autenticados).

### Mapa general (WEB-01)
- **D-02:** Vista inicial: zoom automático para encuadrar todas las obras existentes (no un centro
  fijo en Lago Puelo/Comarca Andina).
- **D-03:** Cobertura de obra, paths y triggers se muestran en **capas activables (checkboxes)**,
  todas **prendidas por defecto**.
- **D-04:** Filtro por recorrido: **selector fijo arriba del mapa**. Elegir un recorrido filtra qué
  obras se muestran en el mapa.
- **D-05 (patrón clave de toda la fase):** Tocar una obra, un path, un trigger, o **seleccionar un
  recorrido** abre un **panel lateral izquierdo** (drawer), angosto, con info básica del elemento.
  Un botón permite **abrir/cerrar** el panel, y otro botón lo **expande a pantalla completa** (el
  mapa se achica proporcionalmente, nunca desaparece ni se navega a otra URL/recarga). El panel
  expandido muestra el **detalle completo** de ese elemento (para una obra: visibilidad, recorrido,
  artistas, cobertura, paths — el mismo contenido de WEB-04), no solo la misma info básica agrandada.
- **D-06:** Un único componente de panel lateral se **reusa** para los 4 tipos: obra, path, trigger,
  recorrido. No hay 4 implementaciones separadas.

### Navegación / arquitectura de información
- **D-07:** La pantalla de entrada (home) tras loguearse es **el mapa general** — no hay dashboard
  intermedio.
- **D-08:** **Obras** (WEB-04): página propia con su URL — listado filtrable por recorrido y
  visibilidad + detalle. Accesible TAMBIÉN desde el panel del mapa (D-05) — mismo contenido, dos
  entradas (directa por URL, o vía el mapa).
- **D-09:** **Artistas** (WEB-03): página propia con su URL — listado + detalle (obras en las que
  aparece cada artista). No usa el esquema de panel del mapa.
- **D-10:** **Recorridos** (WEB-02): **NO tiene página propia**. Vive enteramente dentro del esquema
  de panel del mapa (D-05/D-06) — seleccionarlo en el filtro del mapa (D-04) abre el panel con sus
  créditos calculados y lista de obras, expandible igual que una obra.
- **D-11:** **Audios** (WEB-06 — reinterpretado): **sin listado propio**. La reutilización de un
  mismo audio en varios paths es un caso de **debug de la app** (celular), no un uso real esperado
  en producción — en la práctica cada audio pertenece a un solo path. Su metadata (título,
  descripción, `kind`) se muestra **inline dentro del detalle del path** que lo usa (WEB-05), nunca
  en una vista aparte. WEB-06 queda satisfecho así, no por una página de listado.
- **D-12:** Navegar de obra → path mantiene un camino de vuelta claro (breadcrumb o botón "volver a
  la obra"), sin importar si se llegó desde el panel del mapa o desde la página de Obras.
- **D-13:** Estado de sync (WEB-07): **indicador fijo en el header**, visible en cualquier pantalla
  (último pull, cursor, errores explícitos) — mismo criterio de "estado honesto" que ya tiene la app
  del celular. No es una pantalla separada a la que haya que navegar.

### Identidad visual
- **D-14:** El usuario va a prototipar las pantallas en **Claude Design** (producto de Anthropic
  Labs, research preview en claude.ai, no integrado a este flujo de Claude Code) usando el prompt
  guardado en `12-CLAUDE-DESIGN-PROMPT.md`. **Todavía no lo corrió** al cerrar esta discusión —
  research/planning arrancan SIN esa referencia visual. Cuando el usuario tenga el resultado
  (link o export), actualizar este CONTEXT.md o correr `/gsd:ui-phase 12 web` con esa referencia
  antes de implementar el detalle visual final.
- **D-15:** Sin preferencia de colores/tipografía por ahora — abierto a lo que proponga Claude
  Design o el research de la fase, apropiado para una herramienta de gestión de arte sonoro en la
  naturaleza (sin caer en literalismo — nada de hojas/árboles por default, ver el prompt guardado).

### Claude's Discretion
- Densidad exacta de los listados (Obras, Artistas).
- Estados vacíos y manejo de errores de pull más allá del criterio de "estado honesto" ya establecido.
- Ancho del panel lateral, animación de apertura/cierre/expansión.
- Colores/tipografía finales hasta que exista un resultado de Claude Design (D-14).
- Cómo estructurar el build de Vite dentro de `web/` sin colisionar con el descubrimiento de
  funciones de Vercel (`web/api/`, ya en producción desde la Fase 11) — configuración de
  `outputDirectory` en `web/vercel.json` y orden de reglas de rewrite (la SPA no puede interceptar
  `/sync/*` ni `/api/*`, per nota dejada en `11-03-SUMMARY.md`).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requisitos y roadmap
- `.planning/workstreams/web/ROADMAP.md` §Phase 12 — goal, 4 criterios de éxito, `UI hint: yes`,
  ponytail audit obligatorio como último plan/tarea
- `.planning/workstreams/web/REQUIREMENTS.md` — AUTH-02, WEB-01..08, STOR-04 (STOR-04 depende de
  Phase 13 para archivos reales; acá solo se deja la UI lista para indicar "sin archivo todavía")
- `.planning/PROJECT.md` §ADRs — ADR-004 (web participante del protocolo de sync, sin CRUD aparte),
  ADR-006 (escritura por etapas — fuera de esta fase, ver Deferred), ADR-008 (la web funciona solo
  online)
- `.planning/PROJECT.md` §"Current Milestone — workstream web" — stack propuesto originalmente
  (Vite+React+Leaflet), confirmado en D-01

### Contrato de datos (Phase 10, ya cerrado)
- `.planning/workstreams/web/phases/10-pull-cerrado-auth-dual-key/10-CONTEXT.md` — forma exacta de
  `GET /sync/pull` (D-04 a D-13 de esa fase): paginación por `cursor`/`limit`, respuesta
  `{changes:[{table,change_seq,payload}], nextCursor, hasMore}`, filas borradas como fila completa
  con `deleted_at` (que esta web debe filtrar siempre, WEB-08), alcance de `WEB_API_KEY` (solo
  lectura: pull/state sí, push 403)

### Infra de deploy (Phase 11, ya cerrado)
- `.planning/workstreams/web/phases/11-infra-de-deploy-mismo-proyecto-vercel/11-05-SUMMARY.md` —
  estructura final real de `web/` (backend disuelto ahí, sin shims), Root Directory = `web`,
  `web/vercel.json` con el rewrite `/sync/:path*` — la SPA de esta fase se agrega al MISMO proyecto,
  sin tocar ese rewrite
- `web/README.md` — flujo de dev/deploy vigente

### Diseño (cuando exista)
- `.planning/workstreams/web/phases/12-web-de-lectura/12-CLAUDE-DESIGN-PROMPT.md` — prompt usado
  para prototipar en Claude Design (D-14); actualizar con el link/export cuando el usuario lo tenga

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `web/api/*` (Phase 10/11) — el pull real (`GET /sync/pull`), `GET /sync/state`, y la auth dual-key
  ya están en producción. Esta fase consume ese contrato, no lo modifica.
- Ninguna vista/componente de frontend existe todavía — `web/` hoy solo tiene el backend (API +
  scripts). Esta fase es un build de frontend completamente nuevo (greenfield).

### Established Patterns
- Ninguno de frontend todavía. El único patrón establecido y relevante es el contrato de pull
  (forma de la respuesta, paginación, filtrado de `deleted_at`) de Phase 10.
- `web/vercel.json` ya define el rewrite `/sync/:path*` → `/api/sync/:path*` — cualquier config de
  build de la SPA (Vite) tiene que convivir con ese rewrite y con el descubrimiento de funciones en
  `web/api/`, sin interceptarlos (nota ya dejada en `11-03-SUMMARY.md` para la Fase 12).

### Integration Points
- Nueva app Vite dentro de `web/` (junto al `api/` ya existente) — mismo proyecto Vercel, mismo
  Root Directory (`web`, desde Fase 11).
- `WEB_API_KEY` ya aceptada por el backend (Fase 10) — la pantalla de acceso (AUTH-02) solo necesita
  guardarla en `sessionStorage` y mandarla como `Authorization: Bearer` en cada pull.

</code_context>

<specifics>
## Specific Ideas

- El panel lateral izquierdo plegable/expandible (D-05/D-06) es LA decisión de UX que más define
  esta fase — se repite para obra, path, trigger y recorrido. Vale la pena que research/planning lo
  traten como un componente central, no un detalle menor.
- El filtro de recorrido en el mapa (D-04) y la "página" de recorrido (D-10) son la MISMA interacción
  — seleccionar un recorrido simultáneamente filtra el mapa y abre su panel. No son dos features
  separadas.
- Prompt completo para Claude Design ya entregado al usuario y guardado en
  `12-CLAUDE-DESIGN-PROMPT.md` (D-14).

</specifics>

<deferred>
## Deferred Ideas

Todo esto es visión a futuro del usuario, explícitamente fuera de esta fase (mucho ya anticipado por
ADR-006, alguna pieza nueva a registrar):

- **Escritura desde la web (ADR-006 etapas 1 y 2):** editar/completar recorridos, obras, asignación
  de artistas (nombre + link de contacto), crear/editar perfiles de artista con bio, subir y
  descargar audios de las obras finales.
- **Edición de paths:** mover triggers, cambiar radios, crear/eliminar triggers, crear
  portales/paths nuevos.
- **Parámetros de reproducción configurables** desde la web (ej. ajuste de tiempo de reproducción
  según velocidad de movimiento) — probablemente una config que consume la APP del celular, no la
  web en sí; queda para cuando se defina esa pieza (workstream `app` o un ADR nuevo).
- **Estadísticas de reproducción.**
- **Reconsiderar Next.js** si el producto se abre a público general con necesidad real de SEO
  (gente externa descubriendo recorridos por búsqueda, no solo editores autenticados) — ver D-01.
- **Listado propio de Audios** si algún día se reutilizan entre paths más allá de un caso de debug
  (ver D-11) — revisar si esto pasa antes de asumir que la decisión sigue vigente.

</deferred>

---

*Phase: 12-web-de-lectura*
*Context gathered: 2026-09-30*
