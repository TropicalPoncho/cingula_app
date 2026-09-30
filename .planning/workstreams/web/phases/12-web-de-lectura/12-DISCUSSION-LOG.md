# Phase 12: Web de lectura - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-30
**Phase:** 12-web-de-lectura
**Areas discussed:** Stack del frontend, Mapa general (WEB-01), Navegación / arquitectura de información, Identidad visual

---

## Claude Design (surgió como "Other" antes de elegir áreas)

El usuario preguntó por "un design system de claude design" sin que Claude supiera qué era —
resultó ser Claude Design, producto separado de Anthropic Labs (research preview en claude.ai,
lanzado abril 2026, actualizado junio 2026 con import de design system desde repo, potenciado por
Opus 4.8). No es una skill ni una integración de esta sesión de Claude Code.

**Resultado:** se le entregó al usuario un prompt completo para pegar en Claude Design, guardado en
`12-CLAUDE-DESIGN-PROMPT.md`. El usuario aún no lo corrió al momento de cerrar esta discusión.

---

## Stack del frontend

| Option | Description | Selected |
|--------|-------------|----------|
| Vite + React + Leaflet/OSM | Lo que ya propone el ERS. Ecosistema de mapas maduro (react-leaflet), Vite rápido, Vercel lo soporta nativo. | ✓ |
| Next.js | SSR/rutas API propias del lado web. Más pesado de lo que este milestone (solo lectura) necesita. | |
| Otro framework (Svelte, Vue, etc.) | Si hubiera preferencia personal. | |

**User's choice:** Vite + React + Leaflet/OSM, tras dos preguntas de seguimiento:
1. "¿Qué me traería SSR?" — respondido: SEO/first-paint público, ninguno aplica a una herramienta de
   un solo editor autenticado.
2. "Si más adelante se abre a público general para que otros gestionen sus propios recorridos, ¿no
   generará retrabajo pasar a Next?" — respondido: la migración de framework es acotada (componentes/
   hooks se llevan casi 1:1); el rework real de un pivot multi-tenant público está en autenticación
   real y modelo de datos con "dueño", ninguno de los dos depende del framework de frontend.

**Notes:** Durante esta discusión el usuario describió una visión extensa a futuro (edición de
recorridos/obras/artistas, perfiles de artista, subida/descarga de audios, edición de paths/triggers,
parámetros de reproducción, estadísticas) — todo registrado en Deferred Ideas de CONTEXT.md, no
forma parte de esta fase.

---

## Mapa general (WEB-01)

### Vista inicial

| Option | Description | Selected |
|--------|-------------|----------|
| Zoom automático a todas las obras | Encuadra automáticamente todo lo que existe. | ✓ |
| Centrado fijo en Lago Puelo/Comarca Andina | Vista fija predefinida. | |

### Capas del mapa (cobertura, paths, triggers)

| Option | Description | Selected |
|--------|-------------|----------|
| Todo visible, colores por tipo | Todo dibujado a la vez, sin clicks extra. | |
| Capas activables (checkboxes) | Prender/apagar cobertura, paths, triggers por separado. | ✓ |

**Follow-up:** ¿arrancan prendidas o apagadas? → **Todas prendidas por defecto.**

### Filtro por recorrido

| Option | Description | Selected |
|--------|-------------|----------|
| Selector fijo arriba del mapa | Dropdown/lista siempre visible. | ✓ |
| Panel lateral con más filtros | Sidebar combinando varios filtros a futuro. | |

### Interacción al tocar un elemento

| Option | Description | Selected |
|--------|-------------|----------|
| Navega directo al detalle | Un click lleva a la página de detalle. | |
| Popup con resumen + link al detalle | Popup chico, un paso más. | |
| **Respuesta libre del usuario** | Panel lateral izquierdo que se abre/cierra con botón, con info básica; botón para expandir a pantalla completa (mapa se achica), sin navegar a otra pantalla ni recargar. | ✓ (reemplazó ambas opciones) |

**Follow-up 1:** El panel expandido, ¿muestra más info (detalle completo) o la misma info agrandada?
→ **Detalle completo** (visibilidad, artistas, cobertura, paths — lo mismo que WEB-04).

**Follow-up 2:** ¿El mismo panel se usa para path/trigger también? → **Sí, un solo patrón reusado.**

---

## Navegación / arquitectura de información

### Home post-login

| Option | Description | Selected |
|--------|-------------|----------|
| El mapa | Entra directo al mapa general. | ✓ |
| Dashboard/landing con accesos | Pantalla intermedia con links a cada sección. | |

### Listados fuera del mapa (pregunta original: Recorridos/Obras/Artistas/Audios)

| Option | Description | Selected |
|--------|-------------|----------|
| Páginas propias por sección | Cada uno con su URL. | Parcial — ver notas |
| Mismo panel lateral expandible en todos lados | Todo en una pantalla con el mismo panel. | Parcial — ver notas |

**User's response (no eligió directamente, cuestionó la premisa):** "audios están vinculados con
obras entonces ¿por qué un listado separado? ¿para qué serían estos listados? Explicate mejor."

**Claude explicó** el rol de cada listado como "vista inversa/de gestión cruzada" (audio→paths que lo
usan, recorrido agrupa obras de varios artistas, artista aparece en varias obras) — ninguno duplica
lo que ya se ve navegando obra por obra desde el mapa.

**Resultado final, por sección:**
- **Audios:** el usuario aclaró que la reutilización entre paths era un caso de **debug de la app**,
  no un uso real — **sin listado propio**, metadata inline en el detalle del path (confirmado en
  follow-up separado, ver abajo).
- **Artistas:** **página propia**, para "gestionar su información aparte" (lectura en esta fase;
  gestión/edición es visión a futuro, anotada en Deferred).
- **Recorridos:** el usuario señaló que agrupa obras en una zona/trail — quiere: seleccionarlo filtra
  el mapa a sus obras, y una "pantalla extendida" de recorrido usa el mismo esquema de panel
  plegable/expandible que se venía hablando para el mapa → **sin página propia**, vive en el esquema
  de panel (D-10 de CONTEXT.md).

### Follow-up: WEB-06 sin listado de Audios, ¿alcanza con metadata inline en el path?

| Option | Description | Selected |
|--------|-------------|----------|
| Sí, alcanza | El audio se ve donde se usa. | ✓ |
| Igual quiero verlos todos juntos | Vista de conjunto aparte. | |

### Navegación obra → path

| Option | Description | Selected |
|--------|-------------|----------|
| Sí, con navegación hacia atrás clara | Breadcrumb o botón "volver a la obra". | ✓ |
| No hace falta pensarlo ahora | A criterio de research/planning. | |

### Estado de sync (WEB-07)

| Option | Description | Selected |
|--------|-------------|----------|
| Indicador fijo en el header | Badge/ícono siempre visible en cualquier pantalla. | ✓ |
| Pantalla/sección propia | Página dedicada a navegar. | |

---

## Identidad visual

### ¿Ya corriste el prompt en Claude Design?

| Option | Description | Selected |
|--------|-------------|----------|
| Todavía no, lo hago después | Research/planning arrancan sin esa referencia. | ✓ |
| Ya tengo un resultado | Link/export para usar como referencia canónica ya. | |

### Preferencia de estilo más allá de Claude Design

| Option | Description | Selected |
|--------|-------------|----------|
| Abierto / lo que recomiende el research | Sin preferencia fuerte todavía. | ✓ |
| Tengo algo en mente | Colores/referencias/tono específico. | |

---

## Claude's Discretion

- Densidad exacta de los listados (Obras, Artistas).
- Estados vacíos y manejo de errores de pull más allá de "estado honesto".
- Ancho del panel lateral, animación de apertura/cierre/expansión.
- Colores/tipografía finales hasta que exista un resultado de Claude Design.
- Configuración de build de Vite dentro de `web/` sin colisionar con `web/api/` ni el rewrite de
  `/sync/*` (ya en producción desde la Fase 11).

## Deferred Ideas

- Escritura desde la web (ADR-006 etapas 1 y 2): editar recorridos/obras, asignar artistas (nombre +
  link de contacto), perfiles de artista con bio, subida/descarga de audios.
- Edición de paths: mover triggers, cambiar radios, crear/eliminar triggers, crear portales/paths.
- Parámetros de reproducción configurables (tiempo según velocidad de movimiento) — probablemente
  para la app del celular, no la web.
- Estadísticas de reproducción.
- Reconsiderar Next.js si el producto se abre a público general con necesidad real de SEO.
- Listado propio de Audios si dejan de ser de un solo path en la práctica.
