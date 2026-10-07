---
phase: "12"
slug: "web-de-lectura"
status: approved
reviewed_at: "2026-10-03"
shadcn_initialized: false
preset: none
created: "2026-10-03"
---

# Phase 12 — UI Design Contract (Web de lectura)

> Contrato visual y de interacción para la Fase 12. Generado por gsd-ui-researcher, verificado por gsd-ui-checker. Fuente visual de verdad: prototipo de Claude Design (D-14), 8 tableros locales en `C:/Users/ramac/AppData/Local/Temp/claude/C--Users-ramac-source-TropicalPoncho-cingula-app-web/29f727aa-f106-404e-bb83-b00973e4fecf/scratchpad/cingula/project/*.dc.html` (abreviado `Main.dc.html`, `Obras.dc.html`, `Artistas.dc.html`, `Acceso.dc.html`; el CSS compartido y `buildView()` viven en `Main.dc.html`). Tokens: Cíngula Design System (`tokens.css` + `components/bundle.css`, reusados tal cual). Decisiones del usuario: `12-CONTEXT.md` D-01..D-18 (D-14..D-18 prevalecen sobre `12-CLAUDE-DESIGN-PROMPT.md`).
>
> Regla de lectura: lo marcado **[PROTOTIPO]** es decisión de diseño bloqueada (no re-preguntar). Lo marcado **[REAL]** es una corrección contra el esquema real que el prototipo no podía conocer (datos de muestra inventados). Lo marcado **[DEFAULT]** es una decisión de este contrato sin validación del usuario. Lo marcado **[ABIERTO]** está sin resolver y figura en "Items abiertos".

---

## Decisiones y riesgos (leer primero)

Estas decisiones afectan el futuro de la fase (modelo de datos visible, escalado del mapa, contrato con Fase 13). Van antes que cualquier detalle de ejecución.

| # | Decisión | Por qué (fuente) | Alternativa descartada | Riesgo mientras no se resuelva |
|---|----------|------------------|------------------------|--------------------------------|
| R1 | **Un portal NO es hijo de un path: es una fila de `paths` con `kind='portal'`, hija directa de la obra.** Vista "Portal" = ese path + su (único) trigger (posición, radio, offset, descripción). Jerarquía real: Obra > Path(route) > Trigger(s) y Obra > Path(portal). | `web/schema.sql:78-90` (`paths.kind IN ('route','portal')`, `obra_uuid NOT NULL`, `audio_uuid` en el path); `web/schema.sql:92-106` (no existe tabla `portales`; `triggers` tiene `name`/`description`/`radius_meters`/`offset_ms`); `lib/data/migration/v7_migration.dart:120-148` (los triggers sueltos y los de path colgante se migraron a un path `kind='portal'` con el nombre y el audio del trigger); `lib/domain/entities/geo_path.dart:6` ("Recorrido o portal. La geometría son sus triggers"). Esto responde la pregunta abierta de D-16 ("¿pueden existir sueltos en la obra?"): sí, siempre cuelgan de la obra. | Modelar `portal` como entidad hija de un path (supuesto de D-16 y del prototipo, `Main.dc.html:299` `p.portales`, y la tabla "Portales · con sonido propio" del detalle de path de D-18). | **ALTO.** El detalle de path del prototipo muestra una tabla de portales del path y un "Orden: N de M en el path": no existe en los datos. Este contrato la reemplaza por "Portales de la obra" (ver Panel > path). Confirmar con el usuario antes de planificar (OI-01). |
| R2 | **La cobertura de una obra es una caja (bbox) + centro, no un polígono.** La capa "Cobertura" dibuja un rectángulo con `cover_min_lat/max_lat/min_lon/max_lon`; el hecho "Cobertura" dice la extensión en metros, no "Polígono · N vértices". Obra sin triggers tiene las 6 columnas en NULL: no se dibuja, no entra al auto-ajuste, se lista con "Sin cobertura todavía". | `web/schema.sql:51-56`; `web/api/_lib/cover.js:1`; `web/schema.sql:127` (índice por bbox). El prototipo dibuja polígonos de 6 a 11 vértices (`Main.dc.html:246-253`), inventados. | Calcular un casco convexo de los triggers en el cliente (más código, y no es lo que el servidor guarda). | Medio. Visual distinto al prototipo (rectángulo en vez de polígono orgánico); el contrato de capas no cambia. |
| R3 | **Enums reales** (los del prototipo eran inventados): `obras.visibility ∈ {draft, private, public}` → etiquetas "Borrador / Privada / Pública"; `audios.kind ∈ {grabacion, final}`; `paths.kind ∈ {route, portal}`. | `web/schema.sql:49`, `:21`, `:81`. Prototipo: `publicada/borrador/oculta`, `walk`, `ambient/voz/portal` (`Main.dc.html:246-279`). | Mantener las etiquetas del prototipo. "Oculta" no corresponde a `private`. | Bajo. Cualquier valor fuera del CHECK se muestra crudo en monoespaciado (no se oculta). |
| R4 | **Los triggers de un path `route` se muestran anónimos** ("Trigger 007" = `position + 1`), aunque la fila tenga `name`/`description`. El único dato "con significado" de un trigger de ruta es `offset_ms` = momento del audio en que se grabó ese punto. | `lib/core/services/recorder_service.dart:188-194`: el grabador escribe `name='<path> trigger N'`, `description='Auto-generated'`, `offset_ms=<ms de audio>`. | Mostrar `name`/`description` de cada trigger (rompe D-16 y mete ruido). | Bajo. **Resuelto 2026-10-05:** el usuario confirmó que los triggers no tienen nombre; el nombre es del **path** (incluido el path `kind=portal`, cuyo nombre es el del portal). WEB-05 enmendado en REQUIREMENTS.md. Los campos `triggers.name`/`description` de la BD no se muestran como nombre de trigger. |
| R5 | **El `offset_ms` de un portal se muestra pero la app lo ignora** (un portal arranca siempre en 0). Se rotula "Offset" con el valor crudo y sin interpretación. | `lib/domain/usecases/monitor_user_location_usecase.dart:247-256` (`effectiveOffsetMs = isPortal ? 0 : …`). | Ocultar el offset en portales. | Bajo; evita que el artista crea que el offset de un portal tiene efecto. Copy exacto en "Copywriting". |
| R6 | **Círculos con cientos de triggers reales: RESUELTO 2026-10-07 (OI-02): `CIRCLES_MIN_ZOOM = 16`, `CIRCLES_MAX = 600`** (el máximo real es 35 triggers por obra: el tope nunca actúa). Contrato [medido]: los círculos sólo se dibujan con zoom >= 16, recortados al viewport, tope duro de 600; por debajo del umbral el modo Círculos se ve como Corredor con una pista "Acercá el mapa para ver los círculos". Roving tabindex (un solo tab stop por path). | D-17 (riesgo declarado), prototipo sólo con 3 a 40 triggers sintéticos por path (`Main.dc.html:283-300`). Umbral 16 sale de: a lat -42° un metro = 0,56 px en z16 (radio 20 m ≈ 11 px) y 0,28 px en z15 (radio 20 m ≈ 5,6 px). | Agrupar (clustering) triggers: más código y semántica poco clara para "ver huecos". | Medido: riesgo bajo con los datos actuales (35 triggers por obra como máximo); el corte por viewport y el tope siguen como defensa si el catálogo crece. |
| R7 | **Audio: sin forma de onda falsa y sin reproducción en esta fase.** La tarjeta de audio tiene 3 estados (sin audio asignado / sin archivo todavía / archivo en el servidor) y un slot reservado para el reproductor que llega en Fase 13. | `web/schema.sql:19-31` (`storage_key` NULL = sin archivo; `duration_seconds` real). El prototipo dibuja 56 barras decorativas con `Math.sin` (`Main.dc.html:425`): datos falsos. `12-CONTEXT.md` (dominio): STOR-04 es "indicar cuando no hay archivo", no gestionar. | Reusar las barras del prototipo como decoración. | Bajo. Desvío visual del prototipo, justificado: la UI no puede mostrar un dato que no existe. |
| R8 | **Copy del 401 corregido:** el prototipo dice "Revisá que sea la clave de lectura y no la del celular" pero el backend acepta TAMBIÉN `SYNC_API_KEY` para leer (role `sync`). | `web/api/_lib/auth.js:7-9` (`KEYS = [['sync',…],['web',…]]`, ambos roles autentican); `Acceso.dc.html:124`. | Copy del prototipo (afirma algo falso). | Bajo. Copy nuevo en la tabla de Copywriting. |
| R9 | **Foco visible en formas SVG ausente en el prototipo.** `.mk:focus-visible{outline:none}` y `box-shadow` (regla global del DS) no pinta sobre elementos SVG. El contrato exige un foco propio para capas Leaflet (ver Accesibilidad). | `Main.dc.html:61-62`, `bundle.css` regla `[tabindex]:focus-visible{box-shadow:var(--glow-focus)}`. | Heredar el prototipo. | Medio: sin esto el mapa no es operable con teclado (incumple contraste/foco WCAG 2.4.7). |
| R10 | **Tipografía normalizada:** el prototipo usa 8 tamaños (12/13/14/15/17/20/25/40). El contrato fija **exactamente 4 tamaños en total** (13 / 15 / 20 / 40, todos tokens `--fs-*` del DS) y **exactamente 2 pesos en total: 300 (sólo Display 40 px) y 400 (todo lo demás)**; ver R14 por el desvío del DS. Se fusionaron los antiguos 20 y 25 en un único tamaño de título (20). | Ver Typography. Regla del checker: 3-4 tamaños, 2 pesos. | Copiar los 8 tamaños; o declarar 4 + 1 display "fuera de la cuenta" (relabel, rechazado por el checker). | Bajo; ajustes de 1 a 5 px respecto del prototipo, listados. El título del panel compacto, el `h1` de toolbar/login y los títulos de fila pasan de 25/17 a 20: la jerarquía contra el display (40) se mantiene. |
| R11 | **Faltan assets del DS en la copia local:** `tokens.css` referencia `fonts/*.woff2` (Chillax/Synonym) y el login usa `assets/logo-mark-light.png`; la copia guardada sólo trae `README.md`, `tokens.css` y `components/bundle.css`. | `ls …/artifact-files/5a5f7c08-…/project/` (3 archivos). | Sustituir por fuentes del sistema (rompe D-15). | Medio: sin los `.woff2` la tipografía cae a `Futura/system-ui`. Obtenerlos del proyecto del DS antes de implementar (OI-06). |
| R12 | **El cursor es string.** `change_seq` y `nextCursor` viajan como string (bigint); nunca pasar por `Number()`, se compara/ordena sólo como BigInt y se muestra tal cual. | `12-CONTEXT.md` (Phase 10 D-04..D-13), `web/api/sync/pull.js:26-33,57`; REQUIREMENTS PULL-02. | Parsear a número. | Bajo hoy (48213), pierde precisión > 2^53. |
| R13 | **Layout móvil no existe en el prototipo.** Se propone una regla mínima [DEFAULT/NO VALIDADO] (ver Layout y Responsive). | Prototipo fijo a 1440x900 (`$preview` en cada `data-props`). | Diseñar móvil completo (fuera de alcance, herramienta desktop-first). | Medio en pantallas < 900 px. |
| R14 | **DESVÍO DEL DS (flagged, el usuario puede revertirlo): exactamente 2 pesos, 300 (sólo Display 40 px) y 400 (todo lo demás, incluidos Heading y etiquetas).** El README del DS dice "sentence-case headings step up to medium below 25px" y el prototipo aprobado usa 500 en etiquetas `.lbl`, títulos de 20 px y registro `CÍNGULA`; este contrato los baja a 400. La jerarquía pasa a depender de tamaño (13/15/20/40), mayúscula y `--ls-label` en etiquetas, y color (`--text-primary` vs `--text-secondary`), no de peso. Implementación: sobreescribir a 400 el peso de `.lbl`, `.cg-label`, `.cg-portal-type`, `.tbl th`, `.seg`, `.btn`, nav links y de `h1..h4` a 20 px (la regla global `h1..h4` del DS es light/300: ahí el contrato exige 400, el 300 queda sólo en `.dtitle`). | Regla del checker (máximo 2 pesos, Dimension 4) contra la regla del DS. Se eligió esta ruta por quedar más cerca de D-14/D-15: conserva el título display 40 px light aprobado y el único cambio es 500 -> 400. | (a) 400/500 en todo con Display también en 400/500: contradice "display light" del DS y cambia el título aprobado. (b) Declarar el 300 "fuera de la cuenta": relabel, rechazado por el checker (igual que con los tamaños). | Bajo/Medio. Etiquetas y títulos de 20 px se ven algo más livianos que en el prototipo (500); Chillax a 400 sigue siendo legible, pero verificar contraste visual de etiquetas 13 px mayúscula sobre `--surface-card` en la revisión de UAT. Si el usuario prefiere el 500 del prototipo, el cambio es acotado: la fila 13/20 de Typography y este R14 (pasaría a 3 pesos, con nueva excepción documentada del checker). |

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (sin shadcn, sin Tailwind; `web/components.json` no existe) |
| Preset | not applicable |
| Component library | none: componentes React escritos a mano que replican las clases del prototipo (`.hdr .pill .panel .row .fact .seg .strip .card .ent .btn .ib .lnk .crumb .sel .inp .tbl`) |
| Icon library | `lucide-react` (el DS declara Lucide, trazo 1,5 px, `currentColor`, puntas redondeadas; el prototipo usa SVG inline equivalentes) |
| Font | Display/etiquetas: Chillax (300 sólo Display; 400 el resto). Texto: Synonym (400). Mono: `ui-monospace, "SFMono-Regular", Menlo, monospace` (`--font-mono`) |

Hoja de estilos, en este orden (README del DS, "Using this system"): `tokens.css` y luego `components/bundle.css`, copiados dentro de `web/` (ej. `web/public/ds/` o `web/src/ds/`); las `@font-face` de `tokens.css` resuelven `fonts/` relativo al CSS. Tema por defecto `oscuro` (`:root`); el tema `claro` NO se usa en esta fase. Reglas globales del DS que se heredan sin tocar: foco `--glow-focus` en `a/button/input/select/[tabindex]`, `::selection` violeta, `h1..h4` Chillax light, enlaces mint con subrayado al 40%.

---

## Component Inventory

Could not enumerate: el Cíngula Design System no es un paquete instalado (no existe `node_modules/<pkg>` ni `exports` que consultar); se entrega como archivos copiados (`tokens.css`, `components/bundle.css`) y su `bundle.js` React (`window.CNgulaDesignSystem_fa472e`) no está en la copia local ni se usa por D-15. Fuente verificable y re-ejecutable de lo que sí provee: `grep -n "^  --" <ruta-del-DS>/tokens.css` (tokens) y `grep -n "^\\." <ruta-del-DS>/components/bundle.css` (clases base `.cg-label`, `.cg-portal-type`).

Esta tabla es una lista **no exhaustiva** de componentes conocidos y no una lista cerrada. Componentes que esta fase construye (no vienen del DS), derivados del prototipo:

| Componente | Origen en el prototipo | Notas |
|-----------|------------------------|-------|
| `AppHeader` (marca, nav, `SyncPill`, "Salir de la web") | `.hdr .brand .nav .nl .pill .quiet` (`Main.dc.html:21-37`) | 56 px, `--surface-raised`, borde inferior hairline; pestaña activa con subrayado mint 2 px |
| `SyncPill` + popover | `.pill .pop .perr` (`:31-36`) | Ver sección Sync |
| `SidePanel` (único, 5 tipos) | `.panel .rail .phead .crumbs .ptools .pbody` (`:63-72`) | Ver sección Panel |
| `EntityDetail` (contenido del panel y del detalle de Obras) | `buildView()` (`:347-430`) | Un solo objeto de vista alimenta panel y página (prototipo lo declara: "el MISMO objeto alimenta el panel del mapa y el detalle de la página Obras") |
| `MapView` (Leaflet) + `MapBar` (selector, capas, modo) + `Legend` + `Attribution` | `.mapwrap .mapbar .mcard .chk .sw .legend .attr .seg` (`:52-62`, `:108-109`) | Ver sección Mapa |
| `Facts` (`dl`) y `FactRow` | `.facts .fact .lnk` (`:75-77`, `:46-47`) | Etiqueta 124 px / valor |
| `ListRow` (`.row`, 52 px) y `EntityRow` (`.ent`, 64 px) | `:78-82`, `:103-107` | `.row` dentro de paneles, `.ent` en listados de página |
| `AudioCard` | `.card .empty .player` (`:85-89`) | 3 estados, ver Panel |
| `CoverageStrip` | `.strip` (`:110`) | Un cuadro por trigger, ámbar = hueco |
| `DataTable` | `.tbl .tblbtn` (`:91-96`) | Tabla de portales; encabezados en registro de etiqueta |
| `Toolbar` (filtros de página) y `Select`, `Segmented` | `.toolbar .fld .sel .seg` | `Select` es `<select>` nativo (ponytail: sin librería) |
| `LoginCard` | `Acceso.dc.html` | Ver Pantalla de acceso |
| `EmptyBlock` (dashed ámbar) | `.empty` (`:87`) | Sólo para "falta algo" (sin archivo, sin audio); las listas vacías usan texto `dim` |

---

## Spacing Scale

Escala estándar (múltiplos de 4; tokens del DS entre paréntesis):

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px (`--sp-1`) | Separación entre ítems de nav, gap de `.crumbs` y de `.strip`, `h` márgenes mínimos |
| sm | 8px (`--sp-2`) | Gap de botón-ícono, margen entre `.row`, padding vertical de `.mcard` y de `.fact`, gap vertical de `.perr` |
| md | 16px (`--sp-4`) | Padding horizontal de controles, gap de mapbar, padding de `.empty` |
| lg | 24px (`--sp-6`) | Gap del header, margen del login |
| xl | 32px (`--sp-8`) | Gap de `dgrid` (panel expandido), padding de `.detpane` |
| 2xl | 48px (`--sp-12`) | Panel plegado (riel) |
| 3xl | 64px (`--sp-16`) | Reservado; no se usa en esta fase |

Excepción justificada E1 — pasos intermedios del DS (12 / 20 / 40): son múltiplos de 4 pero no pertenecen al juego 4/8/16/24/32/48/64. Se conservan **tal cual** porque `tokens.css` (`--sp-3`, `--sp-5`, `--sp-10`) se reusa sin modificar (D-15) y el prototipo bloqueado (D-14) está dimensionado con ellos; snapearlos obligaría a redefinir el espaciado del DS. Uso permitido, sólo estos:

| Token | Value | Usage |
|-------|-------|-------|
| 12 | 12px (`--sp-3`) | Gap de pill, de fact grid, padding de popover rows y de `.perr` |
| 20 | 20px (`--sp-5`) | Padding del cuerpo del panel (`.pbody`), de `.card` y de `.listpane`, padding del header |
| 40 | 40px (`--sp-10`) | Padding del login card |

Ningún otro valor fuera de la escala estándar y de E1 puede usarse como espaciado (gap/padding/margin). Los valores 6 px (`.perr`), 10 px (`.fact`), 2 px (`.crumbs`) y 3 px (`.strip`) del prototipo se **snapearon** a 8 / 8 / 4 / 4 (ajuste de 1 a 2 px, sin cambio de estructura).

Otras excepciones (todas dimensiones estructurales, no espaciado entre bloques de texto):
- Objetivos táctiles: 44 px mínimo (`--touch-min`) en `.pill .btn .ib .sel .inp .seg .chk` y 28 px en `.crumb` (enlace de texto en línea, dentro de un grupo; área clickeable extendida a 44 px de alto con padding vertical si se mide en auditoría [DEFAULT]).
- Estructurales fijos: header 56 px; fila `.row` 52 px; fila `.ent` 64 px; fila de tabla 52 px; columna de etiqueta de facts 124 px (popover 104 px); `.listpane` 560 px; popover de sync 400 px; login card 440 px; panel 380 px / 62% / 48 px; mini-mapa de Obras 240 px de alto; leyenda/atribución a 16 px de los bordes.
- No múltiplos de 4 que se conservan por ser tamaño de glifo/forma y no espaciado: 18 px (lado del checkbox y de la muestra `.sw`), 14 px (`--r-md`, radio de borde), y las medidas de las marcas de la tira de cobertura (6×20 px y 18×20 px). Ningún gap, padding ni margin usa estos valores.

---

## Typography

Contrato normalizado a **4 tamaños en total** (13 / 15 / 20 / 40; tokens `--fs-xs`, `--fs-sm`, `--fs-md`, `--fs-2xl` del DS) y **exactamente 2 pesos en total: 300 (sólo el Display de 40 px) y 400 (todo lo demás)**. Desvío del DS (500 -> 400 en etiquetas y títulos) declarado y reversible en R14. No existe ningún otro tamaño de fuente en la fase (incluida la atribución de OSM, la leyenda, los errores y las etiquetas de mapa: todos 13). Fuente de los valores: `tokens.css` y el CSS del prototipo; el redondeo se declara fila por fila.

| Role | Size | Weight | Line Height | Notas |
|------|------|--------|-------------|-------|
| Caption / etiqueta / meta | 13px | 400 (etiquetas `.lbl`: mayúscula, `--ls-label` .12em, Chillax; meta, mono, crumbs, leyenda, errores; el prototipo usaba 500 en `.lbl`, ver R14) | 1.35 (meta) / 1.2 (etiqueta) | Prototipo usa 12 px para `.lbl` (`--type-label`) y 12-14 para meta: se unifica en 13. Mono (`--font-mono`) también 13 |
| Body | 15px | 400 | 1.62 (`--lh-relaxed`) | `--type-body-sm`; texto base de la app, filas `.row .t`, celdas de tabla (prototipo 14 -> 15) |
| Heading | 20px | 400 (Chillax; el prototipo usaba 500, ver R14) | 1.3 | Fusión del antiguo Subheading (17 -> 20) y Heading (25 -> 20): títulos de `.card h4` y de `.ent .t`, título del panel compacto (`.ptitle`), `h1` de toolbar de página y del login. Títulos de sección de popover no (esos son etiqueta) |
| Display | 40px | 300 (Chillax light) | 1.14 | Sólo título del panel expandido y del detalle de Obras/Artistas (`.dtitle`). Único uso del peso 300 y único rol que lo declara: es uno de los 2 pesos del contrato (300 + 400), mandato del DS ("display en light; nunca bold") |

Reglas: títulos en minúscula/mayúscula de oración, nunca negrita; el registro `CÍNGULA` (`.cg-portal-type`, Chillax 400 13 px, `--ls-portal` .42em, mayúscula) sólo para la marca del header y del login; etiquetas `.lbl` en mayúscula con `--ls-label`; jamás espaciar letras de texto en minúscula. Numeración y metadatos técnicos (uuid, cursor, lat/lon, `kind`, `tolerance_meters`, offsets) en `--font-mono`. Los offsets se formatean con separador de miles por espacio: `+1 200 ms` (`fms`, `Main.dc.html:307`). Lat/lon con 5 decimales.

---

## Color

Fuente: `tokens.css` (tema oscuro). El mapa es el elemento dominante; la proporción 60/30/10 se mide sobre cromo de la UI (no sobre los tiles).

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `#08070B` (`--surface-base`, ink-900) y `#050409` (`--surface-sunken`, fondo del mapa/mini-mapa) | Fondo de la app, toolbars de página, lienzo del mapa |
| Secondary (30%) | `#17151E` (`--surface-card`, ink-600) y `#0D0C12` (`--surface-raised`, ink-800) | Panel lateral, popover de sync, login card, tarjetas internas; header, selects, inputs; velo del mapa `--surface-veil rgba(8,7,11,.72)` + `--backdrop-veil` sólo en `.mcard` y `.legend` (único uso permitido de blur) |
| Accent (10%) | `#8AE2C8` (`--c-mint`) | Ver lista reservada abajo |
| Destructive | not applicable (`#FF0074` magenta NO se usa) | Fase de solo lectura: no existe ninguna acción destructiva. Magenta queda reservado a "en vivo/ahora" del DS y no aparece en esta fase |

Accent reserved for (mint `#8AE2C8`, D-15):
1. Portales (borde, relleno 16% y punto central en el mapa).
2. Selección: borde 1 px de `.row.on`/`.ent.on` (fondo `rgba(138,226,200,.07)`), `.seg[aria-pressed=true]` (fondo 12%), cobertura de la obra relacionada/del recorrido seleccionado.
3. Pestaña activa del header (subrayado 2 px).
4. Anillo de foco (`--focus-ring`).
5. Enlaces (`--text-link`) y `accent-color` de los checkboxes.
6. Punto de estado "listo": visibilidad Pública, sync al día, "Huecos: Ninguno".
7. Parte reproducida de la futura barra de audio (reservado Fase 13).
Nunca para texto corrido, títulos ni fondos de bloque.

Otros roles semánticos fijos (D-15, "no se inventan tonos nuevos"):

| Color | Valor | Uso exclusivo |
|-------|-------|---------------|
| Violeta | `#9900FF` (`--action-primary`), hover `#C77CFF` | Acción primaria: "Ver detalle completo" y "Entrar a la web". Una sola acción primaria visible por pantalla. Texto blanco (contraste ≈ 5,5:1), hover con texto `--ink-900` |
| Azure | `#578CCB` (`--c-azure`), soft `#A8C6E7` | Geometría de paths y triggers (línea, corredor, círculos); `--azure-soft` sólo para el path/trigger resaltado |
| Ámbar | `#FFBC00` (`--c-ambar`), soft `#FFD980` | Hueco entre triggers, atención, error/stale de sync, "Sin archivo todavía", visibilidad Borrador, `.perr`/`.empty` (relleno 6-8%, borde 40-55%) |
| Ink-200 / texto | `--text-primary #F4F1F7`, `--text-secondary #9C96AB`, `--text-muted #6E6880` | `--text-muted` (contraste ≈ 3,4:1 sobre `#17151E`, no cumple AA para texto) sólo para placeholders y separadores `/` del breadcrumb (no esenciales); toda información va en `--text-secondary` o más claro. Visibilidad Privada usa punto `--ink-200` |
| Hairline | `rgba(244,241,247,.12)` / strong `.28` | Bordes de fila, panel, tabla / controles |

Mapa de visibilidad -> punto: `public` mint, `draft` ámbar, `private` `--ink-200`. Brillo (`--glow-*`) no se usa en esta fase (reservado a elementos "vivos"; no hay reproducción).

---

## Layout y Shell [PROTOTIPO]

Ruteo (D-07..D-10, planificador elige librería; D-01 aclara que el ruteo es lo único que cambia si algún día se migra a Next):

| Ruta | Pantalla | Estado en la URL |
|------|----------|------------------|
| `/acceso` | Pantalla de acceso | `?motivo=401` cuando se vuelve por clave inválida |
| `/` | Mapa general (home, D-07) | `?rec=<uuid>` filtro de recorrido, `?sel=<tipo>:<uuid>` elemento del panel, `?x=1` panel expandido, `?modo=circ` modo Círculos. Se escribe con `history.replaceState` (el panel nunca crea entradas de historial ni "navega", D-05) [DEFAULT] |
| `/obras` y `/obras/:obraUuid` | Obras (D-08) | `?sel=path:<uuid>` / `portal:<uuid>` / `trigger:<uuid>` para el elemento anidado; el listado elige la primera obra filtrada por defecto [DEFAULT] |
| `/artistas` y `/artistas/:artistaUuid` | Artistas (D-09) | — |

No hay ruta de Recorridos (D-10) ni de Audios (D-11). Reglas de despliegue (de `12-CONTEXT.md`, discreción): el fallback de la SPA no puede interceptar `/sync/*` ni `/api/*`.

Shell (todas las pantallas salvo `/acceso`): `AppHeader` 56 px arriba, contenido debajo ocupando `100vh - 56px`, `overflow:hidden` en el shell y scroll interno sólo en `.pbody`, `.listpane`, `.detpane`. Header: marca "Cíngula" (registro `.cg-portal-type`) + etiqueta "Web de lectura"; nav "Mapa / Obras / Artistas" (`aria-label="Secciones"`, `aria-current="page"` en la activa); espaciador; `SyncPill`; "Salir de la web" (texto silencioso, sin confirmación: sólo borra `sessionStorage`).

### Responsive [DEFAULT, NO VALIDADO]

El prototipo no tiene versión móvil. Regla mínima propuesta (marcar para validar con el usuario, OI-05):
- >= 1200 px: layout del prototipo tal cual.
- 900-1199 px: igual; el panel expandido sigue en 62% y el mapa conserva el resto; la `mapbar` envuelve (`flex-wrap`, ya presente).
- < 900 px: el panel deja de ser columna y pasa a **hoja de pantalla completa** (`position:fixed; inset:56px 0 0 0`; compacto = hoja inferior de 55% de alto, expandido = pantalla completa, plegado = tira de 48 px de alto abajo); en Obras y Artistas el listado ocupa todo el ancho y el detalle lo reemplaza con un botón "Volver al listado"; el texto de la pill de sync se oculta y quedan punto + ícono, el popover pasa a ancho completo.
- Los objetivos de 44 px ya cumplen táctil.

---

## SidePanel (componente único, 5 tipos) [PROTOTIPO + REAL]

Un solo componente `SidePanel` (D-06/D-18) recibe `view = buildView(sel)` y no tiene ramas por tipo en su chrome; el contenido por tipo lo decide `buildView`. Tipos: `recorrido`, `obra`, `path` (kind route), `portal` (path kind portal), `trigger`. La selección es un string `<tipo>:<uuid>` (formato del prototipo, `Main.dc.html:340`).

### Estados y anchos

| Estado | Ancho | Contenido |
|--------|-------|-----------|
| Cerrado | 0 (no se renderiza) | `sel = null` |
| Compacto | 380 px | Cabecera + info básica + listas recortadas + botón "Ver detalle completo" |
| Expandido | 62% del ancho del contenedor | Detalle completo en grilla `5fr / 7fr`, gap 32 px |
| Plegado (riel) | 48 px | Botón "Abrir panel" (chevron-right) + texto vertical `{TIPO} · {título}` (`writing-mode: vertical-rl`, rotado 180°, máx 420 px, una línea, recorta) |

- Transición: `width var(--dur-base) var(--ease-drift)` (320 ms; con `prefers-reduced-motion` el DS ya pone `--dur-base: 1ms`). Plegar conserva el flag expandido: al reabrir vuelve al estado previo. Elegir cualquier elemento (mapa o panel) desplaza `collapsed=false`. Cerrar (X) pone `sel=null`, `expanded=false`.
- El mapa nunca desaparece: es `flex:1; min-width:0`, y se achica (nunca navega). Al terminar el cambio de ancho el mapa debe llamar `invalidateSize` (por `ResizeObserver` sobre el contenedor, coalescido en `requestAnimationFrame`) conservando el centro. No se re-encuadra automáticamente por abrir/expandir/plegar.
- Sombra `--shadow-card`, borde derecho hairline, fondo `--surface-card`. `aside` con `aria-label="Detalle del elemento seleccionado"`.
- Esc: expandido -> compacto; compacto -> cerrar y devolver el foco al marcador del mapa que lo abrió (si existe) [DEFAULT].

### Cabecera (`.phead`, siempre visible salvo plegado)

Izquierda: breadcrumb (`aria-label="Ruta"`); derecha: tres botones de 44 px: expandir/volver (`Maximize2`/`Minimize2`, `aria-label` "Expandir a pantalla completa" / "Volver al panel angosto"), plegar (`ChevronLeft`, "Plegar panel"), cerrar (`X`, "Cerrar panel").

### Breadcrumb y "volver" (D-12)

Cada segmento menos el último es un botón que cambia `sel` (nunca recarga). Separador `/` en `--text-muted`. Origen "mapa" antepone el recorrido; origen "página Obras" antepone `Obras` y omite el recorrido (`root`/`pageObras`, `Main.dc.html:353`). Regla para obras sin recorrido: se omite el segmento recorrido.

| Tipo | Breadcrumb (origen mapa) | Botón "Volver a …" |
|------|--------------------------|--------------------|
| recorrido | `Recorrido` (sólo el actual) | no |
| obra | `Recorrido / Obra` | no |
| path | `Recorrido / Obra / Path` | `Volver a {Obra}` |
| portal [REAL] | `Recorrido / Obra / Portal` (el prototipo ponía el path en el medio) | `Volver a {Obra}` |
| trigger | `Recorrido / Obra / Path / Trigger NNN` | `Volver a {Path}` |

El botón "Volver a" (`.btn`, ícono `ArrowLeft`) se muestra en compacto y expandido, debajo del subtítulo.

### Contenido por tipo (compacto vs expandido)

Compacto muestra: etiqueta de tipo (registro `.lbl`), título 20/400, subtítulo, [Volver], `Facts`, hasta 4 filas por lista con "+N más" y el botón primario `Ver detalle completo` (ancho completo, violeta, ícono `Maximize2`). Expandido: etiqueta, título 40/300, subtítulo, [Volver]; columna izquierda (5fr): `Facts` + descripción; columna derecha (7fr): tarjeta de audio, tira de cobertura, listas completas, tabla. En la página Obras (`pageObras`) se usa el mismo contenido expandido en `.detpane` y se agrega un mini-mapa de 240 px de alto (no interactivo: sin arrastre ni zoom con rueda, resalta la selección).

| Tipo | Facts (etiqueta -> valor) | Sólo expandido | Listas |
|------|---------------------------|----------------|--------|
| **recorrido** | Obras (n), Paths (n), Portales (n), Triggers (n), Créditos (artistas únicos de sus obras, enlace a Artistas) | Descripción (`recorridos.description`, si no está vacía) | Obras (nombre; sub: `{visibilidad} · {n path(s)}`) |
| **obra** | Visibilidad (punto + etiqueta), Recorrido (enlace -> abre el panel del recorrido; "Sin recorrido" si NULL), Artistas (enlaces a `/artistas/:uuid`), Cobertura (`{ancho} × {alto} m` desde el bbox, o "Sin cobertura todavía"), Paths (n route), Portales (n) | — | Paths (sub: `route · {n} triggers · {m} hueco(s)`), Portales (sub: `radio {r} m · {offset} · {con archivo / sin archivo todavía}`) |
| **path** (route) | Obra (enlace), `kind` (mono), `tolerance_meters` (mono, `{n} m`), Grabación de origen (título del audio `grabacion_uuid`; "—" si NULL), Triggers (`{n} · radio {r} m · cada ≈ {x} m`), Huecos (punto: ámbar si hay, mint si "Ninguno") | Tarjeta "Audio del path"; tira de cobertura; nota de huecos; tabla "Portales de la obra" [REAL, ver R1] | Portales de la obra (compacto) |
| **portal** (path kind portal) | Obra (enlace), Posición (`lat, lon` mono), Radio (`radius_meters`), Offset (`offset_ms`, mono) | Descripción (`triggers.description`); tarjeta "Audio del portal" | Otros portales de la obra |
| **trigger** (route) | Path (enlace), Posición (mono), Radio, Orden (`{pos} de {n}`), Offset en el audio (`offset_ms`, mono) | Nota fija (ver Copywriting) | Vecinos en el path (Anterior/Siguiente con distancia en m) |

Tabla "Portales de la obra" (reemplaza "Portales · con sonido propio" del prototipo; columnas `#`, `Nombre`, `Radio`, `Offset`, `Posición`; `#` es el índice en el orden de listado por nombre `localeCompare('es')`, no una posición persistida; nombre = botón que abre el portal). Encabezados en registro de etiqueta (`.tbl th`).

### Tarjeta de audio (`AudioCard`) — 3 estados

| Estado (dato) | Render |
|---------------|--------|
| Sin audio asignado (`audio_uuid` NULL) | Etiqueta ("Audio del path" / "Audio del portal"), texto `dim`: "Este path no tiene audio asignado." (sin `EmptyBlock`) |
| Sin archivo todavía (`audio_uuid` presente, `storage_key` NULL) | Título, descripción, `kind: grabacion|final` (mono), duración `mm:ss` si `duration_seconds > 0`; debajo `EmptyBlock` ámbar punteado: "Sin archivo todavía" + "El audio está registrado, pero su archivo todavía no existe en el servidor." (STOR-04) |
| Archivo en el servidor (`storage_key` presente) | Igual, con punto mint "Archivo en el servidor" y un **slot vacío reservado** para el reproductor de Fase 13 (sin botón Play, sin barras decorativas) |

Si el audio apunta a un uuid que no existe o está borrado: mismo estado "Sin audio asignado".

### Tira de cobertura y huecos (path route)

Un cuadro por trigger en orden de `position`: 6×20 px, radio 2 px, azure; un hueco entre dos triggers consecutivos se inserta como cuadro 18×20 con borde punteado ámbar y relleno `rgba(255,188,0,.12)`. Contenedor `role="img"` con `aria-label` "{n} triggers, {m} huecos" (mejora sobre el prototipo, que sólo da una descripción fija). Nota debajo: `Hueco de ≈ {m} m entre el trigger {NNN} y el {NNN}` (uno por hueco, separados por ". "), o "Los triggers se solapan de punta a punta: el path no tiene huecos." Con muchos huecos la nota se recorta a los 3 primeros + "+N más".

---

## Mapa general [PROTOTIPO + REAL]

Leaflet 1.9.x imperativo dentro de un único `MapView` (sin `react-leaflet`: las panes propias, los atributos ARIA sobre elementos SVG y el recálculo de grosor por zoom son imperativos de todos modos; el planificador puede decidir distinto). Base OSM con la atribución visible (© OpenStreetMap contributors, abajo a la derecha, 13 px `--text-secondary`). Los tiles se oscurecen por CSS sobre `.leaflet-tile-pane` (p. ej. `filter: invert(1) hue-rotate(180deg) brightness(.8) contrast(.9)`) [DEFAULT]: sin dependencia de un proveedor de tiles oscuros; verificar la política de uso de tiles de OSM (tráfico de un solo editor). Control de zoom de Leaflet abajo a la derecha (arriba izquierda está ocupado por la `mapbar`), botones de 44 px.

### Controles (`mapbar`, arriba, `pointer-events:none` salvo los hijos)

Tres tarjetas `.mcard` con velo: (1) selector "Recorrido" (D-04; opción "Todos los recorridos" + una por recorrido + "Sin recorrido" si hay obras con `recorrido_uuid` NULL); (2) grupo "Capas" con checkboxes **Cobertura** (muestra con trazo punteado), **Paths** (azure), **Portales** (mint, trazo 4 px), todos prendidos por defecto (D-03); (3) grupo "Paths" con dos botones segmentados `Corredor` (default) / `Círculos` (`aria-pressed`). Elegir un recorrido hace dos cosas a la vez (D-04 + D-10, es la misma interacción): filtra obras visibles y abre el panel del recorrido; volver a "Todos" cierra el panel. Leyenda abajo a la izquierda: `{n} obra(s) · {n} path(s) · {n} trigger(s) · {n} portal(es)` (pluralización del prototipo, `Main.dc.html:520`; cuenta sólo lo visible por el filtro; paths = `kind route`; portales = paths `kind portal`).

### Auto-ajuste (D-02)

Encuadrar la unión de los bbox de cobertura de las obras visibles con `fitBounds` y padding de 70 px. Se re-encuadra al cambiar el filtro de recorrido y en la primera carga; nunca por togglear capas, cambiar de modo, ni por abrir/expandir/plegar el panel. Cuando una selección se hace desde un enlace del panel (no un clic en el mapa) se hace `fitBounds` al bbox del elemento seleccionado (obra: su bbox; path/portal/trigger: sus triggers) para no dejarlo fuera de la parte visible [DEFAULT]. Si ninguna obra tiene cobertura: vista de respaldo centrada en Lago Puelo `[-42.08, -71.62]`, zoom 11 (único centro fijo permitido; D-02 prohíbe usarlo cuando hay datos).

### Capas y reglas de dibujo

Orden de apilado (panes propias, de abajo hacia arriba): cobertura -> corredor -> línea de path -> segmentos de hueco -> círculos de trigger -> portales -> etiquetas de obra. Todos los trazos son **no escalables** (en Leaflet el `weight` ya es en píxeles de pantalla; se mantiene así, jamás se escala con el zoom).

| Capa | Geometría | Trazo / relleno (valores del prototipo, `Main.dc.html:478-500`) |
|------|-----------|--------------------------------------------------------------------|
| Cobertura de obra [REAL: rectángulo] | `L.rectangle` del bbox | Normal: relleno `rgba(244,241,247,.04)`, trazo 1,25 px `rgba(156,150,171,.75)` punteado `6 5`. Obra del recorrido seleccionado o con elemento seleccionado: relleno `rgba(138,226,200,.08)`, trazo 1,75 mint. Obra seleccionada: relleno `.14`, trazo 2,5 `--text-primary` |
| Etiqueta de obra | `divIcon` en el centro (`cover_lat/lon`) | Chillax 13 px, mayúscula, `.12em`, `--text-primary` al 85%, `pointer-events:none`, oculta si la capa Cobertura está apagada |
| Corredor (modo Corredor) | `L.polyline` por **tramo continuo** (corrida entre huecos), `lineCap`/`lineJoin` redondos | Ancho = **diámetro del trigger en metros** convertido a px: `px = 2·r / (156543.03392·cos(lat)/2^zoom)`, recalculado en `zoomend`; r = mediana de `radius_meters` del path (aproximación si hay radios mezclados). Color `rgba(87,140,203,.28)`; path resaltado `rgba(168,198,231,.42)`; no interactivo |
| Línea de path | `L.polyline` por los centros de los triggers en orden de `position`, **más** una polilínea transparente de 16 px como área de clic (la visible no es interactiva) | Azure 1,5 px; resaltado `--azure-soft` 3 px. Puntos del path = triggers (el prototipo dibuja la línea desde puntos propios; en la web real la línea sale de los triggers) |
| Segmento de hueco | `L.polyline` entre los centros de los dos triggers del hueco | Ámbar 2,5 px, punteado `4 4`, en ambos modos, no interactivo |
| Triggers (modo Círculos) | `L.circle` con radio en **metros** (`radius_meters`) | Relleno azure `.10` (path resaltado `.20`, seleccionado `.50`), trazo azure 1 px (seleccionado 2,5 px `--text-primary`) |
| Portales | `L.circle` en metros (no interactivo) + `L.marker` con `divIcon` como objetivo de clic/teclado | Relleno mint `.16` (seleccionado `.35`), trazo mint 2,5 px (seleccionado 3,5 px `--text-primary`), punto central r 3,5 px (seleccionado 5 px); el `divIcon` tiene área de 44×44 px transparente |

**Regla de hueco:** dos triggers consecutivos por `position` en un path `route` forman un hueco si `distancia_m(a, b) > a.radius_meters + b.radius_meters` (distancia haversine entre `latitude/longitude`; el prototipo lo hace en unidades de mapa, `Main.dc.html:296`). Se calcula una vez por pull, no por frame ni por zoom. El conteo de huecos de un path sale de acá y se usa en el detalle del path, en la fila de path de la obra y en la tira.

**Tolerancia a datos feos:** triggers con `deleted_at` ya vienen filtrados (WEB-08); un path `route` con 0 triggers se lista pero no se dibuja ("0 triggers"); con 1 trigger se dibuja sólo el círculo; un portal sin trigger se lista pero no se dibuja ni cuenta en el mapa.

### Escalado de Círculos con cientos de triggers [CERRADO — OI-02, 2026-10-07]

**Valores congelados (medidos en Production, 12-03): `CIRCLES_MIN_ZOOM = 16` y `CIRCLES_MAX = 600`.** El tope no se alcanza con datos reales (máx 35 triggers por obra); queda como defensa. Detalle de la medición en OI-02 (tabla "Items abiertos").

Contrato (R6): modo Círculos dibuja círculos sólo con zoom >= 16; sólo los que caen en `map.getBounds()` ampliado un 20%; tope duro de 600 círculos y, si se supera, se dibujan sólo los del path resaltado/seleccionado; por debajo de z16 el modo se ve como Corredor y aparece la pista (`.legend`-like, sobre el mapa) "Acercá el mapa para ver los círculos". Corredor, línea, huecos y portales se dibujan siempre. Validado con datos reales (OI-02).

### Interacción de la selección

Clic o Enter/Espacio en una obra, un path, un portal o un trigger -> `sel = <tipo>:<uuid>` y se abre el panel compacto (si estaba expandido, se queda expandido). Seleccionar una obra del recorrido filtrado no cambia el filtro. Una selección que ya no existe tras un refresco (soltó el uuid o quedó con `deleted_at`) muestra en el panel "Este elemento ya no existe en el servidor." con botón "Cerrar aviso".

---

## Pantallas de página [PROTOTIPO]

### Acceso (`/acceso`, AUTH-02)

Fondo `--grad-dusk` con dos ondas decorativas (`--c-mint` y `--c-azure`, 1,25 px, no escalables, opacidad .5; el DS permite `WaveLine` como motivo). Tarjeta 440 px centrada (`--surface-card`, `--r-lg`, `--shadow-raised`, padding 40 px): marca (`logo-mark-light.png` 56 px de alto), `CÍNGULA`, `h1` "Ingresá la clave de acceso", párrafo, etiqueta `API key`, input `type=password` `autocomplete=off` placeholder `WEB_API_KEY`, botón primario "Entrar a la web" (violeta, ancho completo, **es un botón de envío de formulario**, no un enlace como en el prototipo), nota inferior. Enter en el input envía. Estados: reposo; enviando (botón deshabilitado, texto "Entrando…"); 401 (bloque `.perr` con `role="alert"`); error de red/5xx (mismo bloque, copy distinto). La clave se valida con una llamada de lectura (`GET /sync/state` con `Authorization: Bearer`); si 200 se guarda en `sessionStorage` y se navega a `/`. [REAL] El prototipo no persiste la clave: este contrato sí (`12-CONTEXT.md` Integration Points: "guardarla en `sessionStorage`"); nunca va en el bundle ni en la URL. Una respuesta 401 durante la sesión (clave revocada) borra la clave y vuelve a `/acceso?motivo=401`; "Salir de la web" hace lo mismo sin mensaje.

### Obras (`/obras`, WEB-04)

Header + toolbar (título "Obras" 20/400, selectores "Recorrido" y "Visibilidad", conteo `{n} obra(s)`) + split: `.listpane` 560 px con `EntityRow` (`.ent`, 64 px): título 20/400, sub `{Recorrido o "Sin recorrido"} · {artistas}`, a la derecha visibilidad (`.vis`, punto + etiqueta 13 px). Fila seleccionada con borde mint. `.detpane` (padding 32 px): breadcrumb + `EntityDetail` expandido + mini-mapa. Opciones del selector Visibilidad: "Todas / Pública / Privada / Borrador". Sin coincidencias: "Ninguna obra coincide con los filtros." (texto `dim`, copy del prototipo).

### Artistas (`/artistas`, WEB-03)

Header + toolbar ("Artistas", conteo `{n} artistas`) + split: `.listpane` con `.ent` (nombre; sub `{n} obra(s)`) y `.detpane`: etiqueta `ARTISTA`, título 40/300, sub "Los créditos de cada recorrido se calculan con los artistas de sus obras.", `Facts` (Nombre, Obras, Bio si `bio` no es vacía [REAL: `artistas.bio` existe en `web/schema.sql:36`, el prototipo no la mostraba]), sección `APARECE EN` con filas `.row` de obra (nombre, sub = recorrido, visibilidad a la derecha) que enlazan a `/obras/:obraUuid`. `user_id` no se muestra.

---

## Estado de sync (WEB-07, D-13) [PROTOTIPO]

`SyncPill` fijo en el header en todas las pantallas (menos `/acceso`): botón de 44 px de alto, borde `--border-strong`, `--r-pill`; punto de 8 px + [ícono `TriangleAlert` 16 px sólo en error] + texto 15 px (rol Body; el prototipo usa 14) + cursor en mono `dim` (`cursor 48213`). Abre un popover (`role="dialog"`, `aria-label="Detalle del estado de sync"`, no modal): 400 px, `--surface-card`, `--r-lg`, `--shadow-raised`; `aria-haspopup` y `aria-expanded` en la pill; Esc o clic afuera cierran y devuelven el foco a la pill. La hora relativa se refresca cada 30 s. El cursor se muestra como string tal cual (R12).

| Estado | Punto | Texto de la pill | Filas del popover | Botón |
|--------|-------|------------------|-------------------|-------|
| Leyendo (carga inicial o refresco) | `--ink-200` sin animación | `Leyendo… {n} filas` | Estado: "Pull en curso · página {k}" | `Actualizar datos` deshabilitado |
| Al día | mint | `Sync al día · pull hace {rel}` | Último pull (`hoy HH:MM:SS · hace {rel}`), Cursor (mono), Filas leídas (`{n} · {m} con deleted_at descartadas`), Estado: "Sin errores" | `Actualizar datos` |
| Desactualizado [DEFAULT]: último pull OK hace > 15 min, sin error | ámbar | `Datos de hace {rel}` | Estado: "Hace más de 15 min que no se actualiza." | `Actualizar datos` |
| Error (con datos previos) | ámbar + `TriangleAlert` | `Error de pull · datos de hace {rel}` | Último pull OK, Cursor (`{c} (no avanzó)`), Estado: "Pull incompleto: se muestran los datos del último pull completo."; bloque `.perr` `role="alert"` etiqueta "Errores" con líneas `HH:MM:SS  GET /sync/pull?cursor={c} → {código} {texto} (página {k})` y `(reintento {i} de 3)` | `Reintentar lectura`; nota "Próximo reintento automático en 30 s." |
| Error (sin datos, primera carga) | ámbar + `TriangleAlert` | `Error de pull · sin datos` | igual, sin "Último pull OK" | `Reintentar lectura` |
| Sin conexión (`navigator.onLine === false`) | `--ink-200` | `Sin conexión · datos de hace {rel}` | Estado: "La web sólo funciona con conexión." | `Actualizar datos` deshabilitado |

Reglas: [DEFAULT] el pull de una carga es todo-o-nada: se acumula en un buffer y el store en memoria se reemplaza recién al completar la última página (`hasMore=false`); un pull fallado jamás deja una vista a medias (por eso el texto "se muestran los datos del último pull completo"). Reintento automático: 3 intentos cada 30 s; luego queda en error y la nota pasa a "Reintentá cuando tengas conexión." (cambio mínimo sobre el prototipo, que sólo mostraba el primer caso). El botón en estado Al día/Desactualizado hace un pull incremental desde el cursor guardado. Nunca se oculta un error: aunque el popover esté cerrado, la pill ya lo dice. Una fila de `deleted_at` no nulo se cuenta en "Filas leídas" y se descarta de todas las vistas (WEB-08).

---

## Estados por pantalla

| Pantalla | Cargando | Vacío | Error |
|----------|----------|-------|-------|
| Mapa `/` | Mapa base visible + velo `--surface-veil` central con "Leyendo el servidor…" y la pill en `Leyendo…`; selector y capas deshabilitados | Sin obras: velo con "Todavía no hay obras en el servidor." (vista de respaldo en Lago Puelo, sin capas). Sin recorridos: el selector sólo ofrece "Todos los recorridos". Obras sin cobertura: se omiten del mapa y la leyenda las cuenta; la lista de panel dice "Sin cobertura todavía" | Primer pull falla: `.perr` central "No se pudo leer el servidor." + código + botón `Reintentar lectura`; con datos previos: se mantiene el mapa y sólo cambia la pill |
| Obras | Lista con 3 filas esqueleto (bloques `--surface-raised`, sin animación shimmer; el DS no define esqueletos) y detalle vacío | "Todavía no hay obras en el servidor." / filtros sin resultado: "Ninguna obra coincide con los filtros." | Bloque `.perr` en el `listpane` con el mismo copy del mapa + `Reintentar lectura` |
| Artistas | Igual que Obras | "Todavía no hay artistas en el servidor." | Igual que Obras |
| Panel | Contenido ya en memoria: nunca carga por separado | Listas internas vacías se omiten (no se muestra el título de sección sin ítems); audio en sus 3 estados | Elemento inexistente (deep link o ya borrado): "Este elemento ya no existe en el servidor." + `Cerrar aviso`; en `/obras/:uuid` inexistente: "No encontramos esta obra." con enlace "Volver al listado" |
| Acceso | Botón "Entrando…" | — | 401 / red, ver Acceso |

---

## Accesibilidad y teclado

Base: todos los controles >= 44 px (excepto `.crumb`, ver Spacing); contraste de texto >= 4,5:1 (`--text-secondary` y superiores; `--text-muted` sólo no esencial); foco siempre visible; `prefers-reduced-motion` ya colapsa las animaciones por tokens del DS (el `fitBounds` usa `animate:false` bajo esa media query).

Mapa (Leaflet) — equivalente al `tabindex=0 role=button aria-label` + `onKeyDown` del prototipo (`Main.dc.html:212-217`):

| Elemento | Mecanismo | Teclado |
|----------|-----------|---------|
| Portal | `L.marker` con `divIcon` (div nativo de Leaflet, `keyboard:true` -> `tabindex=0`) y `role="button"`, `aria-label="Portal {nombre}, radio {r} m"` | Enter / Espacio = seleccionar |
| Obra (rectángulo), path (polilínea de clic) | Renderer SVG por defecto (no Canvas, que no tiene nodos focuseables); tras `addTo`, `layer.getElement()` recibe `tabindex="0" role="button" aria-label="Obra {nombre}"` / `"Path {nombre}"`; `keydown` Enter/Espacio llama al mismo handler que el clic | Enter / Espacio |
| Trigger (modo Círculos) | Mismo mecanismo SVG, pero **roving tabindex**: sólo el trigger seleccionado (o el primero del path resaltado) tiene `tabindex=0`, el resto `-1`; `aria-label="Trigger {pos} de {n}, radio {r} m"` | Flechas izq./arriba = anterior, der./abajo = siguiente (orden por `position`, cambia el foco y la selección del panel); Enter / Espacio = seleccionar |
| Mapa en sí | `keyboard:true` de Leaflet (flechas = paneo, + / - = zoom) | — |

Foco visible [REAL, R9]: `box-shadow` no pinta en SVG, por lo tanto `.leaflet-interactive:focus-visible { outline: none; stroke: var(--text-primary); stroke-width: 3.5px; stroke-opacity: 1 }` para formas y `box-shadow: var(--glow-focus)` para los `divIcon`. Orden de tabulación del DOM: header, nav, pill, **panel (va antes del mapa en el DOM)**, controles del mapa (`mapbar`), mapa. Como alternativa no espacial a recorrer triggers, el panel del trigger ofrece "Anterior/Siguiente" en "Vecinos en el path". Anuncios: región `aria-live="polite"` que dice "Seleccionado: {Tipo} {título}" al cambiar `sel`; la pill y el popover de error usan `role="alert"` sólo al aparecer un error nuevo.

Listas: `role="list"`/`listitem` en `.listpane` (como el prototipo); tablas con `th` en `scope="col"`; la tira de cobertura y el mini-mapa son `role="img"` con `aria-label` descriptivo; los íconos decorativos `aria-hidden`.

---

## Copywriting Contract

Registro del DS (README, "Content fundamentals"): español rioplatense con voseo, frases cortas, sin signos de exclamación, sin emoji (nunca), sentencia en minúscula de oración, tres registros: `CÍNGULA` (marca), etiqueta mayúscula `PORTAL 03 · …` con `·` como separador de metadatos (`--ls-label`), y oración normal. Fechas `dd.mm.aa`, horas 24 h. "sólo" con tilde como en el prototipo validado.

| Element | Copy |
|---------|------|
| Primary CTA (acceso) | `Entrar a la web` |
| Primary CTA (panel) | `Ver detalle completo` |
| Acción secundaria de panel | `Volver a {nombre}` · `Expandir a pantalla completa` · `Volver al panel angosto` · `Plegar panel` · `Abrir panel` · `Cerrar panel` |
| Etiqueta de tipo (registro `PORTAL 03 · …`) | `RECORRIDO` · `OBRA` · `PATH` · `PORTAL` · `TRIGGER`; texto del riel `{TIPO} · {título}`; metadatos de ejemplo en este registro: `PORTAL · RADIO 30 M` (opcional, sólo si el planificador lo usa en filas) |
| Empty state heading (mapa/Obras) | `Todavía no hay obras en el servidor.` |
| Empty state body | `Cuando el celular sincronice la primera obra, va a aparecer acá.` |
| Empty state (Artistas) | `Todavía no hay artistas en el servidor.` |
| Sin coincidencias (filtros de Obras) | `Ninguna obra coincide con los filtros.` |
| Sin cobertura | `Sin cobertura todavía` (nota: `La obra no tiene triggers, así que no hay dónde dibujarla.`) |
| Audio sin archivo (STOR-04) | `Sin archivo todavía` / `El audio está registrado, pero su archivo todavía no existe en el servidor.` |
| Audio sin asignar | `Este path no tiene audio asignado.` (portal: `Este portal no tiene audio asignado.`) |
| Error de lectura (primera carga) | `No se pudo leer el servidor.` / `GET /sync/pull → {código}. Revisá tu conexión y reintentá.` |
| Error de pull (pill) | `Error de pull · datos de hace {rel}` / popover: `Pull incompleto: se muestran los datos del último pull completo.` |
| Pull sin datos | `Error de pull · sin datos` |
| Acceso: título / bajada | `Ingresá la clave de acceso` / `Esta web sólo lee. La clave vive en esta pestaña y se borra al cerrarla.` |
| Acceso: 401 [REAL, R8] | Etiqueta `Clave rechazada` / `El servidor respondió 401. Revisá que la clave esté completa y que siga vigente.` |
| Acceso: sesión vencida | Etiqueta `Clave rechazada` / `La clave dejó de ser válida. Ingresala de nuevo.` |
| Acceso: sin red | Etiqueta `Sin conexión` / `No se pudo llegar al servidor. Reintentá cuando tengas conexión.` |
| Acceso: nota | `Sin registro ni “recordarme”. Requiere conexión.` |
| Elemento borrado | `Este elemento ya no existe en el servidor.` |
| Trigger (nota fija) | `Los triggers sólo marcan el camino: no tienen nombre ni sonido propio. El sonido del path suena mientras el celular esté dentro de alguno.` |
| Portal: offset | Rótulo `Offset` con valor `+1 200 ms` y ayuda (`title`) `La app todavía ignora el offset de los portales: siempre arranca en 0.` [REAL, R5] |
| Hueco | `Hueco de ≈ {m} m entre el trigger {NNN} y el {NNN}` · sin huecos: `Los triggers se solapan de punta a punta: el path no tiene huecos.` |
| Pluralización | `1 obra` / `2 obras`; `1 path` / `2 paths`; `1 portal` / `2 portales`; `1 hueco` / `2 huecos` |
| Leyenda | `{n} obras · {n} paths · {n} triggers · {n} portales` |
| Pista Círculos | `Acercá el mapa para ver los círculos.` |
| Destructive confirmation | not applicable: no hay acciones destructivas en esta fase (sólo lectura). "Salir de la web" no confirma porque sólo borra `sessionStorage` |

---

## Items abiertos (no se arrastran en silencio)

| ID | Item | Quién lo resuelve | Cuándo |
|----|------|-------------------|--------|
| OI-01 | **Portales vs paths.** En los datos reales un portal es un `paths.kind='portal'` hijo de la obra (R1). Confirmar con el usuario que (a) la tabla "Portales" del detalle de path pasa a "Portales de la obra", (b) no hay "Orden de N en el path", (c) un portal con más de un trigger usa el primero por `position`. WEB-05/R4 resuelto 2026-10-05 (nombre = del path, no del trigger; requisito enmendado). | Usuario + planificador | **Parcial 2026-10-05:** el usuario confirmó que el portal cuelga de la obra ((a) y (b) quedan firmes). (c) resuelto 2026-10-05: un portal es un único círculo; si hubiera más de un trigger se usa el primero por `position`. **OI-01 cerrado.** |
| OI-02 | **Escalado de Círculos** (R6): medir triggers reales por obra/path en Neon y validar zoom >= 16 y tope 600 | Plan 1 de la fase (12-03) | **CERRADO 2026-10-07** (medición real contra Production con `web/scripts/measure-pull.mjs`; 1 página de 280 526 bytes, 1 873 ms). Triggers por path route máx/p50/p95 = 35 / 3 / 19; por obra máx/p50/p95 = 35 / 2 / 26; radio mín/mediana/máx = 9 / 12 / 20 m; separación mediana 12,6 m; huecos 4 en 3 paths. Regla: mediana 12 m · 0,563 · 2^(16-16) = 6,8 px >= 6 px (z15 daría 3,4 px) -> **`CIRCLES_MIN_ZOOM = 16`**; p95 por obra 26 < 600 -> **`CIRCLES_MAX = 600`** (nunca actúa con datos reales). Límite de página del pull sin cambios (`limit = 1000`; máx 0,28 MB << 3 MB). Hallazgos: ver notas debajo de la tabla. |
| OI-03 | **Datos de muestra inventados** (prototipo): nombres, uuids, geometría y los `kind` (`walk`, `ambient`, `voz`); sólo `Obra`/`Recorrido` nombres reales vendrán del pull. No copiar ninguno como fixture de producción | Ejecutor | Siempre |
| OI-04 | **Enums**: verificados contra `web/schema.sql` (R3), pero el CHECK podría ampliarse; mostrar el valor crudo si no coincide | Ejecutor | En el mapeo pull -> vista |
| OI-05 | **Responsive < 900 px** no validado (R13) | Usuario | Antes de cerrar la fase |
| OI-06 | **Assets del DS**: copiar `fonts/*.woff2` y `assets/logo-mark-light.png` desde el proyecto del DS al repo (R11); `tokens.css` los referencia por ruta relativa | Ejecutor | Plan 1 |
| OI-07 | **Base del mapa** del prototipo es una ilustración (`Main.dc.html:205-211` elipses y "río" dibujados): Leaflet/OSM la reemplaza; el filtro oscuro de tiles (CSS) y la política de uso de tiles de OSM están sin validar | Ejecutor | Plan del mapa |
| OI-08 | **Login no persistía** en el prototipo (el botón es un enlace): este contrato fija validación contra `/sync/state` + `sessionStorage` y redirige a `/acceso?motivo=401` ante 401 | Ejecutor | Plan de acceso |
| OI-09 | **Reintento automático** (3 × 30 s), umbral de "desactualizado" (15 min) y "primera obra por defecto" en Obras son [DEFAULT] sin validación | Usuario (opcional) | Revisión de UAT |
| OI-10 | **Corredor con radios mezclados**: usa la mediana por path; si hay dispersión > 10% entre radios de un path, el corredor es sólo aproximado (los círculos reales se ven en modo Círculos) | Ejecutor | Plan del mapa |

**Hallazgos de la medición real (12-03, 2026-10-07; 85 paths route, 74 obras con triggers vivos, 500 triggers vivos):**

- **RIESGO ABIERTO — `paths_portal: 0`.** No hay ningún `paths.kind='portal'` en Production: la capa de portales del mapa, el panel de portal y la tabla "Portales de la obra" no se pueden validar contra datos reales en esta fase; sólo contra fixtures sintéticas. No se inventa ninguna corrección. A confirmar con el usuario: puede que el celular todavía no haya producido filas `kind='portal'`, o que la migración v7 no las haya creado.
- H4: 3 obras con triggers vivos y cobertura NULL (de 74). El mapa las omite en la capa de cobertura y la tira de cobertura muestra el estado "sin cobertura" ya definido.
- H5: 0 paths con `position` repetida o con saltos; el orden `(position, uuid)` queda como defensa.
- OI-10: 0 paths con radios mezclados > 10 %; el corredor por mediana es exacto con los datos reales (radio 9 / 12 / 20 m mín / mediana / máx).
- D-11: 2 audios usados por más de un path (real, pocos). `AudioCard` muestra el audio por path, no hace falta listado ni deduplicado.
- Huecos: 4 huecos en 3 paths; la regla `distancia > r_a + r_b` se dispara con datos reales, así que la UI de huecos se ejercita.

---

## UI Considerations

Sonda ui-consideration (2026-10-05): 12 elementos, 77 consideraciones de estado; tipos de elemento confirmados por el usuario (sin tipos faltantes). Resolución elegida: **mapear cada categoría a las filas existentes del contrato** (los textos de estado vacío y error viven en `## Copywriting Contract` y se referencian, no se repiten). Resumen: 60 resueltas (explicit) y 17 resueltas con verificación backstop (overflow y long-text). Además, fuera de la taxonomía cerrada de la sonda: stale y tab-order (resueltas) y 1 sin resolver (responsive; many se resolvió el 2026-10-07 con OI-02), listadas abajo. Elementos: E1 mapa, E2 selector/capas, E3 panel, E4 Obras, E5 Artistas, E6 tarjeta de audio, E7 tira de cobertura, E8 tabla de portales, E9 acceso, E10 pill de sync, E11 nav/breadcrumb, E12 títulos y etiquetas largas.

| Category | Elements | Status | Resolution |
|----------|----------|--------|------------|
| empty | E1 E2 E3 E4 E5 E6 E7 E8 E9 E12 | resolved (explicit) | Copywriting Contract (vacío de mapa/Obras/Artistas, sin cobertura, audio sin asignar/sin archivo); listas internas vacías se omiten; selector sólo con "Todos los recorridos" |
| loading | E1–E12 | resolved (explicit) | Estados por pantalla (velo del mapa, filas esqueleto) y matriz de sync (`Leyendo… {n} filas`); buffer todo-o-nada, el panel nunca carga por separado |
| error | E1–E12 | resolved (explicit) | Matriz de sync (con y sin datos, sin conexión), Acceso (401 / sesión vencida / red), `.perr` por pantalla, "Este elemento ya no existe" |
| populated | E1 E3 E4 E5 E6 E7 E8 E12 | resolved (explicit) | Prototipo bloqueado (D-14) + contenido por tipo del panel; hay que verificar con datos reales de Neon (OI-03) |
| partial | E1 E2 E3 E4 E5 E6 E7 E8 E9 E12 | resolved (explicit) | "—" para grabación nula, sección omitida si falta descripción/bio, obra sin recorrido ("Sin recorrido"), obra sin cobertura, portal sin trigger |
| zero-one-many | E1 E3 E4 E5 E6 E7 E8 E12 | resolved (explicit) | Pluralización definida (1 obra / 2 obras, 1 hueco / 2 huecos, …) y leyenda; path con 0 o 1 trigger definido |
| overflow | E1 E3 E4 E5 E6 E7 E8 E11 E12 | resolved (backstop) | Listas del panel: 4 filas + "+N más"; tira `flex-wrap`; nota de huecos: 3 + "+N más"; `.pbody`/`.listpane`/`.detpane` con scroll interno. Verificar en prueba visual con un path de 30+ triggers |
| long-text | E1 E2 E3 E4 E9 E10 E11 E12 | resolved (backstop) | Filas: una línea con ellipsis y `title`; título del panel hasta 2 líneas; riel recorta a 420 px; etiqueta de obra en el mapa sin wrap. Verificar con un nombre de 60 caracteres |
| stale | E3 E1 | resolved (explicit) | Selección que desaparece tras un refresco: "Este elemento ya no existe en el servidor." + `Cerrar aviso` |
| tab-order | E1 E3 | resolved (backstop) | Roving tabindex en triggers; panel antes del mapa en el DOM; prueba de teclado manual + test de componente sobre un path de 30 triggers |
| many | E1 (modo Círculos) | resolved (explicit, medido 2026-10-07) | `CIRCLES_MIN_ZOOM = 16`, `CIRCLES_MAX = 600` (OI-02 cerrado; máx real 35 triggers por obra) |
| responsive | E1–E5, E10 | ⚠ unresolved — planner must treat as assumption | Regla < 900 px [DEFAULT] sin validar (OI-05) |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official | none (sin shadcn) | not required |
| third-party | none | not applicable: sin registries de terceros; dependencias de runtime previstas: `react`, `leaflet`, `lucide-react` (npm, versiones a fijar por el planificador; al 2026-10-03: react 19.3.0, leaflet 1.9.4, lucide-react 1.50.0 según `npm view`) |

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: PASS
- [x] Dimension 2 Visuals: PASS
- [x] Dimension 3 Color: PASS
- [x] Dimension 4 Typography: PASS
- [x] Dimension 5 Spacing: FLAG (excepción E1: 12/20/40, tokens DS)
- [x] Dimension 6 Registry Safety: PASS
- [x] Dimension 7 Inventory Provenance: FLAG (Could not enumerate, motivo real)

**Approval:** approved 2026-10-03 (checker, 3ª pasada; OI-01 y WEB-05 resueltos 2026-10-05; sonda UI Considerations corrida 2026-10-05)
