# Phase 2: Backend Real + Push Sync - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-29
**Phase:** 02-backend-real-push-sync
**Areas discussed:** Autenticación mínima, Disparo automático de sync

---

## Áreas ofrecidas (no todas seleccionadas)

| Área | Descripción | Seleccionada |
|------|-------------|--------------|
| Hosting del backend | Neon+Vercel ya investigado en CLAUDE.md, PROJECT.md aún dice "Pending" | No — se confirma por defecto sin discusión, ver CONTEXT.md D-01 |
| Autenticación mínima (SYNC-07) | Mecanismo de API key/bearer | Sí |
| Disparo automático de sync (SYNC-01/03) | Cuándo dispara el push, qué pasa con el botón manual | Sí |
| Nada más — vos decidí | Opción de cerrar sin discutir nada | No |

---

## Autenticación mínima

### Pregunta 1: Forma de la API key

| Option | Description | Selected |
|--------|-------------|----------|
| API key estática vía --dart-define | Secreto fijo en compilación, mismo patrón que ApiConfig.baseUrl | ✓ |
| API key editable desde el panel de debug | Igual pero editable en runtime sin recompilar | |
| Login con usuario/contraseña | Flujo de autenticación real | |

**User's choice:** API key estática vía --dart-define (Recomendado)
**Notes:** Encaja con v0 de un solo editor/dispositivo, sin necesidad de rotación.

### Pregunta 2: Comportamiento ante 401

| Option | Description | Selected |
|--------|-------------|----------|
| Tratar como error terminal, no reintentar | Es un problema de configuración, no algo transitorio | ✓ |
| Reintentar igual que un error de red | Mismo backoff exponencial que fallos de conectividad | |

**User's choice:** Tratar como error terminal, no reintentar (Recomendado)
**Notes:** Evita drenar batería reintentando algo que nunca se va a resolver solo.

---

## Disparo automático de sync

### Pregunta 1: Cuándo dispara el push automático

| Option | Description | Selected |
|--------|-------------|----------|
| Inmediato tras cada escritura + al recuperar conexión | Push apenas se graba algo; retry al volver la conectividad | ✓ |
| Periódico en background (cada N minutos) | Job de workmanager con intervalo fijo | |
| Solo al abrir/volver a primer plano la app | Push disparado en foreground, no en background continuo | |

**User's choice:** Inmediato tras cada escritura + al recuperar conexión (Recomendado)
**Notes:** Minimiza la ventana entre grabar en campo y tener el dato respaldado, alineado con el Core Value del proyecto.

### Pregunta 2: Destino del botón manual "Push outbox (stub)"

| Option | Description | Selected |
|--------|-------------|----------|
| Queda como respaldo de debug | Útil para forzar push puntual, no es acción destructiva | ✓ |
| Se elimina, todo es automático | Simplifica el panel | |

**User's choice:** Queda como respaldo de debug (Recomendado)
**Notes:** No aplica el precedente de eliminación de acciones destructivas de Fase 1 (D-03/D-04) porque forzar un push no es destructivo.

---

## Claude's Discretion

- Backoff exponencial + jitter exacto (curva, límites de reintentos)
- Mecanismo exacto de dedupe idempotente server-side por uuid+logical_version (SYNC-02)
- Formato exacto del header de auth (Authorization: Bearer vs X-API-Key)
- Punto exacto de enganche del disparo automático sobre los data sources locales

## Deferred Ideas

- Pull sync (SYNC-04/SYNC-05) — Fase 3
- Reconsiderar funciones destructivas de debug ahora que sync existe — mencionado en Fase 1, revisar al cierre de esta fase o después, no ahora
- Visibilidad de estado de sync en modo usuario final — no discutido, se asume debug-only por ahora
