# Phase 10: Pull cerrado + Auth dual-key - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-23
**Phase:** 10-pull-cerrado-auth-dual-key
**Areas discussed:** Mecanismo del watermark, Forma de la respuesta, Alcance de WEB_API_KEY

---

## Mecanismo del watermark

| Option | Description | Selected |
|--------|-------------|----------|
| Advisory lock | No cambia esquema ni agrega retraso; exacto. Techo: todo escritor tiene que tomar el lock | ✓ |
| Timestamp servidor + margen | Migra producción; cambios aparecen N segundos tarde | |
| xid / snapshot | Más correcto en teoría, obliga a paginar por xid; más complejo | |

**User's choice:** Advisory lock (push exclusivo, pull compartido).
**Notes:** El usuario pidió primero ver qué decían REQUIREMENTS.md/research y pros/contras de cada opción de registro antes de elegir cómo documentar el cambio (contradice `research/SUMMARY.md` §5, que proponía margen sobre `updated_at` — inválido porque `updated_at` lo pone el cliente). También preguntó si "push" se refería a la app: se aclaró que push es el endpoint del servidor y que el lock vive enteramente ahí, sin cambios en el cliente Flutter.

**Registro del cambio:**

| Option | Description | Selected |
|--------|-------------|----------|
| ADR + corregir docs | ADR nuevo en Notion (con el techo del lock) + corregir REQUIREMENTS.md:14 + nota de reemplazo en research | ✓ |
| Solo docs locales | Corregir REQUIREMENTS.md y research, sin ADR | |
| Solo CONTEXT.md | No tocar otros docs | |

**User's choice:** ADR + corregir docs.

**Lock modo (push exclusivo / pull compartido):**

| Option | Description | Selected |
|--------|-------------|----------|
| Sí, así | Pushes se serializan entre sí; pull espera lo que dura un push en curso | ✓ |
| Otra cosa | — | |

**User's choice:** Sí, así.

---

## Forma de la respuesta

### Estructura

| Option | Description | Selected |
|--------|-------------|----------|
| Lista plana por seq | `{changes:[{table,change_seq,payload}], nextCursor, hasMore}`, orden global | ✓ |
| Agrupada por tabla | `{recorridos:[...], obras:[...]}`, pierde orden global | |

### Filas borradas

| Option | Description | Selected |
|--------|-------------|----------|
| Fila completa | Mismo payload, con `deleted_at` seteado; sin caso especial en query | ✓ |
| Tombstone mínimo | `{table,uuid,deleted_at,logical_version}`; caso aparte | |

### Límite de página

| Option | Description | Selected |
|--------|-------------|----------|
| Default 500, máx 1000 | Celular en blanco (~1200 filas) en 2-3 páginas, lejos del límite de 4.5MB de Vercel | ✓ |
| Default 200, máx 500 | Páginas más chicas, más ida y vuelta | |
| Discreción de Claude | — | |

### Ruta

| Option | Description | Selected |
|--------|-------------|----------|
| `/sync/pull` | Coincide con ERS y roadmap; app corrige el stub | ✓ |
| `/sync/changes` | Coincide con el stub actual de la app; requiere corregir roadmap/REQUIREMENTS/ERS | |

**Notes:** Se detectó la inconsistencia entre el roadmap (`/sync/pull`) y `lib/core/config/api_config.dart:36` (`/sync/changes`, stub sin implementar). Se resolvió a favor del roadmap/ERS.

---

## Alcance de WEB_API_KEY

### Permisos

| Option | Description | Selected |
|--------|-------------|----------|
| Solo lectura | Acepta pull/state, rechaza push. Protege integridad si la key se filtra desde el navegador | ✓ |
| Igual que SYNC_API_KEY | Acepta todo incluido push | |

### Código de rechazo del push con WEB_API_KEY

| Option | Description | Selected |
|--------|-------------|----------|
| 403 Forbidden | Distingue key válida sin permiso de key inválida (401) | ✓ |
| 401 igual que key inválida | Más opaco para diagnosticar | |

---

## Claude's Discretion

- Forma exacta de la query SQL (UNION ALL + LIMIT interno/externo, o equivalente).
- Construcción del payload por tabla desde `TABLE_SPEC` (SQL vs JS).
- Cálculo de `hasMore`.
- Forma de la API de `auth.js` para exponer qué key/rol matcheó.
- Valor de la constante del advisory lock.
- Mensajes de error de los 400.
- Estructura exacta del ADR y del texto del contrato en Notion.

## Deferred Ideas

- Ampliar `WEB_API_KEY` a escritura — cuando llegue ADR-006.
- Exigir que la escritura futura de la web y scripts de datos tomen el advisory lock (queda como requisito registrado en el ADR).
