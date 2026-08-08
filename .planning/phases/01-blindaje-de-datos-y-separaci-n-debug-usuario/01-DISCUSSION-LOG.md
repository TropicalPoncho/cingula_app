# Phase 1: Blindaje de Datos y Separación Debug/Usuario - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-08
**Phase:** 01-blindaje-de-datos-y-separaci-n-debug-usuario
**Areas discussed:** Recuperación ante fallo de DB, Fuerza de la confirmación destructiva, Mecanismo y default del toggle, Qué queda visible en modo usuario

---

## Recuperación ante fallo de DB

| Option | Description | Selected |
|--------|-------------|----------|
| Backup + recrear + avisar | Renombra/backup, recrea DB vacía, la app sigue arrancando y avisa | ✓ |
| Bloquear la app | Pantalla de error bloqueante hasta resolver manualmente | |

**User's choice:** Backup + recrear + avisar (con la aclaración de que el "backup" es un rename del archivo corrupto, no una copia).
**Notes:** El usuario preguntó explícitamente si se puede renombrar la DB vieja en vez de solo hacer backup — se confirmó que renombrar el archivo corrupto con timestamp logra el mismo objetivo que un backup, de forma más barata.

---

## Fuerza de la confirmación destructiva

| Option | Description | Selected |
|--------|-------------|----------|
| Dejar el AlertDialog actual | Confirmación existente (Cancelar/Confirmar) es suficiente | |
| Confirmación escrita | Pedir escribir "BORRAR" antes de habilitar el botón, para recrear DB | |
| (surgió durante la discusión) Eliminar la acción del todo | No dejar la opción de recrear DB disponible en la app | ✓ |

**User's choice:** Eliminar "recrear DB" del todo de la UI de debug. Al preguntar por consistencia sobre "importar DB", el usuario también pidió eliminarla — y fue explícito en que el método subyacente tampoco debe quedar disponible ni siquiera para tests automatizados.
**Notes:** Feedback fuerte y explícito: "no se automatizan funciones destructivas... eso es lo peor que podemos hacer" — guardado como memoria de feedback para futuras sesiones. Revisar la necesidad de funciones destructivas recién cuando sync/backup esté sólido.

---

## Mecanismo y default del toggle

| Option | Description | Selected |
|--------|-------------|----------|
| Gesto oculto | Ej. tocar el título del AppBar varias veces | ✓ |
| Ícono/switch visible | Botón siempre visible para cambiar de modo | |

**User's choice:** Gesto oculto.

| Option (default) | Description | Selected |
|--------|-------------|----------|
| Debug por defecto | Arranca en modo debug, no cambia el flujo actual | ✓ |
| Usuario por defecto | Arranca en modo usuario limpio | |

**User's choice:** Debug por defecto.

---

## Qué queda visible en modo usuario

| Option | Description | Selected |
|--------|-------------|----------|
| Solo ocultar DiagnosticsPanel | Switch, card de audio y banner de grabación quedan visibles | |
| Ocultar también el banner de grabación | Grabación es función de creación de contenido, no de consumo | ✓ (ampliado) |

**User's choice:** Ocultar también el banner de grabación — y además, el modo usuario necesita una estética final propia trabajada como diseño real (no solo widgets condicionalmente ocultos), de forma general para no repetir el trabajo pantalla por pantalla.
**Notes:** Se recomendó correr `/gsd:ui-phase 1` después de este discuss-phase para generar el contrato de diseño (UI-SPEC.md), dado que el roadmap ya marca esta fase con `UI hint: yes`.

---

## Claude's Discretion

- Mecanismo exacto del gesto oculto (cantidad de taps, ventana de tiempo)
- Texto exacto del aviso de recuperación de DB y formato del nombre del archivo renombrado
- Si los métodos `recreateForTesting()`/`importDatabase()` quedan como código muerto o se eliminan del todo — con preferencia fuerte hacia eliminarlos si no hay otro caller real

## Deferred Ideas

- Diseño visual completo del modo usuario — vía `/gsd:ui-phase 1`, no en esta discusión
- Reintroducir funciones destructivas de administración de DB — pospuesto hasta que sync/backup esté sólido (Fases 2-3)
