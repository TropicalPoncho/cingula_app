# Referencia de diseño de la Fase 12 (snapshot)

Copia byte a byte, hecha al planificar (2026-10-06), de los insumos que vivían en un directorio
temporal de la sesión (research H6, UI-SPEC OI-06). Las referencias `Main.dc.html:NN` de
`12-UI-SPEC.md` siguen siendo válidas contra estos archivos.

| Archivo | Origen | Uso |
|---------|--------|-----|
| `ds/tokens.css`, `ds/components/bundle.css`, `ds/README.md` | Cíngula Design System (artifact `5a5f7c08-…`, D-15) | Fuente prístina; el plan 12-01 copia los CSS a `web/src/ds/` (recortando `@font-face`) |
| `prototype/Main.dc.html` | Prototipo Claude Design (D-14), tablero "Mapa general · obra abierta"; los tableros `Mapa-*` son el mismo archivo con otras props | CSS del shell/panel/mapa (líneas 13-112) y `buildView()` (347-430) |
| `prototype/Obras.dc.html`, `Artistas.dc.html`, `Acceso.dc.html` | Mismo prototipo | CSS y estructura de cada página |

Reglas: `12-UI-SPEC.md` (R1-R14) prevalece sobre el prototipo donde difieran. Los datos del
prototipo son inventados (OI-03): no copiarlos como fixtures ni como datos de producción.
Faltan en el snapshot (no estaban en la copia local): los `.woff2` y `logo-mark-light.png` del DS
(los provee el usuario en el checkpoint del plan 12-01).
