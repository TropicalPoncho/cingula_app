# Phase 3: Sync Bidireccional (Pull) - Context

**Gathered:** 2026-09-19
**Status:** BORRADOR — depende de la Fase 2.1 (modelo de datos objetivo). Revisar y completar con `/gsd:discuss-phase 3` cuando 2.1 esté cerrada. No planificar desde este archivo tal cual.

<domain>
## Phase Boundary

El celular recibe cambios hechos fuera de él vía pull (SYNC-04) y el primer sync de un celular con datos previos drena el push por completo antes del primer pull (SYNC-05). El pull es el **mecanismo de distribución**: el celular de cualquier usuario, incluso uno en blanco, baja el contenido que genera el artista. No es una función para usar solo con el celular del editor.

Se construye sobre el modelo de la Fase 2.1 (uuid como identidad y referencia, tablas tipadas en el servidor). Los archivos de audio siguen fuera de esta fase (Fase 5): un celular nuevo recibe la metadata pero no los .wav.

</domain>

<decisions>
## Implementation Decisions

### Disparo del pull
- **D-01:** un ciclo de sync es **push completo y después pull**, con los mismos disparadores de Fase 2 (escritura local, reconexión) más al abrir la app. Reusa `SyncTrigger`, cero timers nuevos, y SYNC-05 queda garantizado por construcción (el pull nunca corre con el outbox sin drenar).
- **D-02:** el pull ocurre **solo con la app abierta**. Sin notificaciones push (FCM) no hay forma de despertar el celular ante un cambio remoto sin polling periódico, que es lo que este milestone quiere eliminar.

### Alcance
- **D-03:** el pull aplica **inserts, updates y deletes**, no solo edición de filas ya conocidas: un celular en blanco debe poder reconstruir el contenido de su biblioteca.
- **D-04:** el pull replica la **biblioteca** del celular (lo propio + lo agregado por QR/Explorar), no todo el catálogo público. Explorar consulta el catálogo online. (Ver D-15 de `02.1-CONTEXT.md`.)

### Deletes remotos
- **D-05:** un delete remoto se aplica como **borrado lógico** en el celular (se marca `deleted_at` y las consultas de lectura lo ocultan); nada se borra físicamente. Alineado con "cero pérdida de datos". A revisar en el nuevo modelo: hoy los deletes locales son físicos y ninguna consulta filtra `deleted_at`.

### Claude's Discretion
- Forma exacta del endpoint de pull (cursor, paginación, tombstones), orden de aplicación (padres antes que hijos), y cómo se muestra el resultado del pull en el panel de debug (mismo criterio de estado honesto de Fase 2).

</decisions>

<pending>
## Sin discutir todavía

- **Conflicto entre un cambio local pendiente y un pull entrante de la misma fila.** El roadmap fija el principio (el pull no pisa una fila con cambio pendiente en el outbox hasta que se suba), pero falta definir qué pasa con esa fila: ¿se saltea y se reintenta en el próximo ciclo, se loguea, bloquea el resto del pull?
- Si el primer push falla o tarda mucho (ej. un backlog grande, como las 1186 filas de Fase 2), ¿cuánto espera el primer pull y qué ve el usuario?
- Cómo se prueba el pull sin la web: editando el servidor a mano, y en qué dispositivo (regla dura de 2.1: nunca contra el celular real; emulador o Windows).

</pending>

<canonical_refs>
## Canonical References

- `.planning/phases/02.1-modelo-de-datos-objetivo/02.1-CONTEXT.md` — modelo objetivo del que depende esta fase
- `lib/data/sync/sync_api.dart` — contrato `SyncApi.pullChanges({cursor})`, hoy sin implementar (`SyncApiHttp.pullChanges` lanza `UnimplementedError`)
- `lib/data/sync/sync_trigger.dart`, `lib/domain/usecases/run_sync_usecase.dart` — ciclo de push existente donde se engancha el pull
- `backend/api/sync/` — hoy solo `push.js` y `state.js`; no existe endpoint de pull
- `.planning/ROADMAP.md` — Fase 3, criterios de éxito 1 a 3
- `.planning/REQUIREMENTS.md` — SYNC-04, SYNC-05

</canonical_refs>

<deferred>
## Deferred Ideas

- Clave de solo lectura para celulares de usuarios (requisito previo a distribuir la app), ver `02.1-CONTEXT.md`.
- Explorar, QR/link, visibilidad draft/private/public: etapa multiusuario.

</deferred>

---

*Phase: 03-sync-bidireccional-pull*
*Context gathered: 2026-09-19 (borrador)*
