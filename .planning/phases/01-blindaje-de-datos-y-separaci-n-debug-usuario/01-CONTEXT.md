# Phase 1: Blindaje de Datos y Separación Debug/Usuario - Context

**Gathered:** 2026-08-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Esta fase entrega tres cosas: (1) la app nunca destruye la base de datos local sin dejar un respaldo recuperable, ni siquiera ante un fallo de apertura que hoy dispara un borrado silencioso; (2) las acciones destructivas de la UI de debug que sigan existiendo requieren confirmación explícita — y las que no son necesarias se eliminan directamente en vez de reforzarlas; (3) un toggle en runtime (gesto oculto, no flavor de Flutter) separa un modo usuario final — con su propia estética, no solo widgets ocultos — del panel de debug actual.

</domain>

<decisions>
## Implementation Decisions

### Recuperación ante fallo de apertura de DB (DATA-01)
- **D-01:** Si `AppDatabase.init()` falla al abrir la base, el archivo corrupto se renombra (no se copia) con timestamp — ej. `cingula.db.corrupto-<timestamp>` — dejándolo intacto y accesible en el mismo directorio, antes de crear una base nueva vacía en la ruta original.
- **D-02:** Después de renombrar y crear la base nueva, la app arranca normalmente (no bloquea al usuario) y muestra un aviso (banner/diálogo) indicando que hubo un problema y dónde quedó el archivo renombrado. Prioridad: que la app siga siendo usable en el campo si esto pasa a mitad de una grabación.

### Acciones destructivas de debug (DATA-02)
- **D-03:** La acción "recrear DB" (`recreateForTesting()`) se elimina por completo de la UI de debug (`data_browser_page.dart`). No se deja disponible ni siquiera para tests automatizados — no se automatizan funciones destructivas contra datos reales bajo ninguna circunstancia. Ver Constraint del proyecto reforzado explícitamente en esta discusión.
- **D-04:** La acción "importar DB" (`importDatabase()`, reemplaza toda la base con un archivo externo) también se elimina por completo de la UI de debug, mismo criterio que recrear.
- **D-05:** No se agrega confirmación escrita (tipo "escribir BORRAR") a ninguna acción — al eliminarse ambas acciones destructivas, esa pregunta queda sin objeto por ahora. Revisar si hacen falta funciones destructivas (con la fricción que corresponda) recién cuando sync/backup esté funcionando como red de seguridad real.
- **D-06:** El patrón de confirmación ya existente en el código (`showDialog<bool>` + `AlertDialog` con Cancelar/Confirmar, usado ya 5 veces en `data_browser_page.dart`) es el patrón a reutilizar si en el futuro se necesita confirmar alguna otra acción — no inventar un componente nuevo.

### Toggle debug/usuario (UI-01)
- **D-07:** El toggle se activa por gesto oculto (ej. tocar varias veces el título del AppBar) — no un ícono/switch visible, no ocupa espacio en la UI de usuario final.
- **D-08:** El estado por defecto (incluyendo la primera vez que se instala este cambio) es modo debug — no cambia el flujo de trabajo actual del usuario, que hoy vive en el panel de debug para grabar y diagnosticar. El usuario decide activamente cuándo pasar a modo usuario para probarlo.
- **D-09:** El estado del toggle persiste entre reinicios de la app (reutilizar el patrón de `SharedPreferences` ya usado en `LocationConfig` para esto).

### Alcance del modo usuario
- **D-10:** En modo usuario se ocultan: `DiagnosticsPanel` completo (incluye el acceso a `DataBrowserPage`) y el banner de grabación de micrófono (`_RecordingBanner`) — grabación de campo no está lista para público general todavía.
- **D-11:** Quedan visibles en modo usuario: el switch de monitoreo de ubicación en background, la card de audio activo/reproduciéndose, y el botón flotante Iniciar/Detener — es la funcionalidad core de consumo para un usuario final.
- **D-12:** El modo usuario no es solo "ocultar widgets de debug" — necesita una estética final propia, trabajada como UI real, no una versión recortada del panel de debug. El usuario quiere que el trabajo de diseño se haga de forma general (no solo esta pantalla) para no tener que repetirlo pantalla por pantalla más adelante.
- **D-13:** Dado que el roadmap ya marca esta fase con `UI hint: yes`, el camino recomendado es correr `/gsd:ui-phase 1` después de este discuss-phase (antes de `/gsd:plan-phase 1`) para generar el contrato de diseño (UI-SPEC.md) de la vista de usuario final, en vez de intentar cerrar la estética dentro de esta conversación.

### Claude's Discretion
- Mecanismo exacto del gesto oculto (cuántos taps, dónde exactamente) — implementar el patrón estándar (N taps sobre el título del AppBar en poca ventana de tiempo) salvo que el UI-SPEC diga otra cosa.
- Texto exacto del aviso de recuperación de DB (D-02) y formato del timestamp en el nombre del archivo renombrado.
- Si `recreateForTesting()`/`importDatabase()` como métodos en `AppDatabase` quedan como código muerto sin caller o se eliminan del todo — priorizar eliminarlos si no hay ningún otro caller real (ver Feedback: nunca dejar funciones destructivas alcanzables "por las dudas").

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requisitos y roadmap
- `.planning/PROJECT.md` — constraint de integridad de datos (máxima prioridad de este milestone) y decisión de toggle runtime vs flavors
- `.planning/REQUIREMENTS.md` — DATA-01, DATA-02, UI-01
- `.planning/ROADMAP.md` — Fase 1: objetivo y criterios de éxito
- `.planning/research/PITFALLS.md` — Pitfall 1 y 2 (borrado silencioso de DB, botones destructivos sin confirmación) con estrategia de prevención

No hay ADRs ni specs externas de diseño — el contrato de diseño de la vista de usuario se generará después de este discuss-phase vía `/gsd:ui-phase 1`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `showDialog<bool>` + `AlertDialog` (Cancelar/Confirmar) — patrón de confirmación ya usado 5 veces en `lib/presentation/pages/data_browser_page.dart` (líneas ~83, ~115, ~246, ~280, ~374). Reusar este patrón para cualquier confirmación nueva que haga falta.
- `LocationConfig` (`lib/core/config/location_config.dart`) — patrón ya establecido de persistencia simple vía `SharedPreferences` con carga/guardado estático. Reusar la misma mecánica para persistir el estado del toggle debug/usuario.

### Established Patterns
- `AppDatabase.init()` (`lib/data/datasources/local/app_database.dart` líneas ~25-53): hoy, si `openDatabase` falla, hace `deleteDatabase(path)` y recrea sin ningún respaldo — este es el código a modificar para D-01/D-02.
- `AppDatabase.recreateForTesting()` (líneas ~257-273) e `importDatabase()` (líneas ~311-329): métodos ya existentes, hoy invocados desde `data_browser_page.dart:128` y `:259` respectivamente — estos call sites en la UI son los que se eliminan (D-03/D-04).
- `HomePage` (`lib/presentation/pages/home_page_impl.dart`): hoy embebe `DiagnosticsPanel` incondicionalmente (línea 51) y siempre muestra `_RecordingBanner` (línea 55) — este es el punto de integración del toggle.

### Integration Points
- `DiagnosticsPanel` (`lib/presentation/pages/home/widgets/diagnostics_panel.dart`) es el panel completo de debug (mapa, triggers, regiones, sync manual, logs) y contiene el `Navigator.push` hacia `DataBrowserPage` (línea ~451) — todo ese árbol se oculta en modo usuario.

</code_context>

<specifics>
## Specific Ideas

- El usuario fue explícito y enfático: nunca automatizar ni dejar alcanzables funciones destructivas contra la base de datos real, "eso es lo peor que podemos hacer" — esto aplica más allá de esta fase, ver memoria de feedback guardada (`feedback_no_destructive_automation`).
- Revisar la necesidad de funciones destructivas de nuevo recién cuando el sync (Fases 2-3) esté funcionando como red de seguridad real.

</specifics>

<deferred>
## Deferred Ideas

- Diseño visual completo del modo usuario (estética final, no solo qué widgets se ocultan) — se resuelve como su propio paso vía `/gsd:ui-phase 1`, no dentro de esta discusión ni de la implementación funcional de la Fase 1 en sí.
- Reintroducir funciones destructivas de administración de DB (con la fricción que corresponda) — explícitamente pospuesto hasta que sync/backup esté sólido (Fases 2-3).

### Reviewed Todos (not folded)
None — no matching todos found for this phase.

</deferred>

---

*Phase: 01-blindaje-de-datos-y-separaci-n-debug-usuario*
*Context gathered: 2026-08-08*
