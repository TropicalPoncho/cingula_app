# Research Summary — workstream `web`, milestone v1.0 (Web de gestión, lectura)

**Proyecto:** Cíngula App
**Dominio:** Backend Vercel Functions + Neon (extensión: `GET /sync/pull`, `WEB_API_KEY`, storage de audio) + web de administración de solo lectura (Vite+React+Leaflet)
**Investigado:** 2026-09-23
**Confianza general:** MEDIA — el diseño de datos (pull, watermark, serialización) está verificado contra el schema y código real del repo (confianza ALTA en esa parte); la integración de deploy (mismo proyecto Vercel sirviendo SPA + functions) y la elección de storage dependen de un spike no ejecutado todavía (confianza MEDIA-BAJA en esos puntos puntuales, señalados abajo).

## Decisiones abiertas para el usuario

Los tres research agents coinciden en el diagnóstico pero divergen en la solución concreta o dejan alternativas sin resolver. Ninguna de estas se asumió en este resumen — quedan explícitas para decidir antes o durante la Fase 12.

### 1. Destino del contenido nuevo: ¿reutilizar `web/` o usar otra carpeta?

- **Qué se decidió (research):** ninguna decisión — los tres documentos identifican el mismo problema pero proponen soluciones distintas. STACK.md dice "borrar los restos de Flutter Web en `web/` y reutilizar esa carpeta". ARCHITECTURE.md asume, como default de trabajo, "crear `admin/` nueva y dejar `web/` intacto" porque es "el cambio más chico". PITFALLS.md presenta ambas opciones sin inclinarse, y marca que la elección debe confirmarse explícitamente con el usuario antes de ejecutar.
- **Por qué importa:** `web/index.html`, `manifest.json`, `favicon.png`, `icons/` son output de `flutter build web` (`<base href="$FLUTTER_BASE_HREF">` sin reemplazar) — scaffold muerto, no la web nueva. Pero ADR-005 dice literalmente "app, `backend/` y `web/` en este repo", lo que sugiere que `web/` sí es el nombre pensado para la carpeta nueva.
- **Riesgo concreto de no decidir antes de la Fase 12:** si se scaffoldea Vite directo sobre `web/` sin borrar antes los archivos de Flutter, hay colisión de `index.html`/`manifest.json` y el build de producción puede servir una mezcla ambigua. Si en cambio se crea `admin/` sin decisión explícita, ADR-005 queda desalineado con el código real y hay que corregirlo.
- **Alternativas:** (a) borrar `web/` de Flutter (confirmado no usado: no hay `flutter: platforms:` restringiendo a web, ni workflow que corra `flutter build web`, constraint del proyecto fija solo Android/iOS) y reusar `web/` para la SPA — es el cambio que respeta ADR-005 tal cual está escrito. (b) crear `admin/` (o `webapp/`) y corregir ADR-005 para que diga esa carpeta — evita tocar nada de Flutter pero requiere actualizar el ADR.
- **Recomendación de este resumen (a validar con el usuario, no impuesta):** opción (a) — borrar y reutilizar `web/` — porque coincide con la letra de ADR-005, evita mantener dos ADRs desalineados, y Flutter Web está confirmado como código muerto por los tres documentos. Confirmar explícitamente antes de ejecutar Fase 12 (irreversible sin recuperar de git history).

### 2. Proveedor de storage de audio: Vercel Blob (privado o público) vs Cloudflare R2

**RESUELTO (2026-09-23, cross-workstream con `app`, ver ADR-011): Cloudflare R2, privado.** Motivo: 10x más free tier (10GB vs 1GB) y egress siempre gratis importan más que evitar una cuenta nueva, dado que Fase 2.2 de `app` va a subir grabaciones de campo por el mismo bucket y PROJECT.md ya anota una dirección futura de usuarios descargando audio (el egress gratis de R2 se vuelve el costo real ahí, no el storage). `storage_key` sigue siendo texto opaco (ADR-002/003) — la elección no toca el esquema. Objetos privados por default en R2 (sin modo público que activar por error). La sección original de STACK.md queda abajo como registro histórico de la investigación, no como la decisión vigente.

- **Qué se decidió (research, histórico — ver resolución arriba):** STACK.md y ARCHITECTURE.md coinciden en recomendar **Vercel Blob** como proveedor (mismo proyecto, sin cuenta nueva, flujo de upload autorizado ya construido). Pero divergen en visibilidad: STACK.md dice explícitamente "modo `private`"; ARCHITECTURE.md asume URLs **públicas** estables (`https://<store-id>.public.blob.vercel-storage.com/...`) para evitar un endpoint de download-url. PITFALLS.md marca como "Security Mistake" servir audio con blobs públicos por default, recomendando URLs firmadas con expiración corta.
- **Por qué importa:** la elección determina si hace falta un endpoint nuevo `GET /storage/download-url` (si es privado) o si la web arma la URL directo con una constante de build (si es público) — no es un detalle de implementación, cambia el contrato de BE-04.
- **Riesgo concreto:** si se implementa como público (más simple, camino de ARCHITECTURE.md) y después se decide que el audio no debería ser descargable por cualquiera con la URL, hay que agregar un endpoint nuevo y migrar objetos ya subidos. Si se implementa como privado desde el día uno, hay más trabajo ahora (endpoint de firma) para un riesgo que hoy es bajo (contenido de un solo artista, no PII, ADR-008 dice la web es solo-online).
- **Además, sin resolver:** límite de storage. Vercel Blob Hobby da **1GB** gratis; con ~77 audios actuales y archivos `.wav` de campo "de decenas de MB" (contexto del milestone), el free tier se agota rápido si el celular empieza a subir grabaciones crudas por el mismo bucket (Fase 2.2 de `app`). Cloudflare R2 da 10GB gratis + egress siempre gratis, pero exige cuenta nueva + librería de firmado S3 nueva — descartado por STACK.md como "más infraestructura de la que hace falta hoy", pero queda documentado como camino de migración de bajo costo (`storage_key` es un `text` opaco, cambiar de proveedor no toca el esquema).
- **Recomendación de este resumen:** usar Vercel Blob privado desde el día uno (alinea con PITFALLS.md, que es la única fuente que evalúa el riesgo de seguridad explícitamente) — el costo de agregar el endpoint de descarga firmada ahora es bajo comparado con migrar objetos públicos después. Monitorear uso real de storage antes de que el celular empiece a subir por el mismo bucket; tener R2 documentado como plan B si se acerca a 1GB.

### 3. Flujo de upload: `handleUpload`/client token (legacy) vs `presignUrl`/`handleUploadPresigned`

**RESUELTO (2026-09-23, cross-workstream con `app`, ver ADR-011): URL presignada tipo S3 (PUT genérico), siempre — no aplica a Vercel Blob (proveedor descartado, ver decisión #2), sino a R2 vía firmado S3 estándar. El criterio decisivo se mantiene: tiene que ser consumible desde Flutter (celular, Fase 2.2 de `app`) con `http.put` genérico, sin SDK de plataforma.**

- **Qué se decidió (research, histórico — ver resolución arriba):** STACK.md recomienda explícitamente **`handleUploadPresigned` + `presignUrl`** (URLs `PUT` firmadas tipo S3, consumibles con `fetch`/`http.put` genérico) y pone el flujo legacy `handleUpload` en la tabla "What NOT to Use", razonando que un cliente Dart/Flutter no puede usar el SDK JS del navegador que el flujo legacy requiere. ARCHITECTURE.md describe en su lugar el flujo **legacy** (`handleUpload` + `generateClientTokenFromReadWriteToken`, del paquete `@vercel/blob/client`) como "ya construido específicamente para el caso cliente→storage directo", sin mencionar la limitación de que ese flujo asume el SDK JS.
- **Por qué importa:** el consumidor final de este endpoint no es solo la web (que sí puede usar el SDK JS) sino el celular Flutter (Fase 2.2 de `app`), que necesita un flujo agnóstico de plataforma. Si se construye sobre el flujo legacy asumiendo que "ya está listo", el celular puede quedar bloqueado más adelante al descubrir que necesita reimplementar el protocolo de token interno de Vercel a mano.
- **Riesgo concreto:** elegir mal esto en Fase 14 (BE-04) es rehacer el endpoint cuando la Fase 2.2 de `app` lo intente consumir desde Dart.
- **Recomendación de este resumen:** seguir STACK.md — `presignUrl`/`handleUploadPresigned`, porque el criterio decisivo (consumible sin SDK específico de plataforma) es el que de hecho tiene que cumplir un cliente Flutter, y STACK.md es el único documento que evaluó esa restricción explícitamente.

### 4. Ruteo Vercel monorepo: `functions` glob en `vercel.json` de raíz vs mover `backend/api/` a `<raíz>/api/` vs shims de re-export

- **Qué se decidió (research):** los tres documentos coinciden en el diagnóstico (Root Directory hoy es `backend/`; para servir la SPA hace falta que la raíz del repo sea el Root Directory del proyecto) pero proponen **tres mecanismos distintos**, todos marcados MEDIA/MEDIA-BAJA confianza: (a) STACK.md propone un `vercel.json` de raíz con `rewrites` hacia `/api/...` más **shims de re-export** por archivo (`<raíz>/api/sync/push.js` → `export { default } from '../backend/api/sync/push.js'`) — preserva `backend/` intacto. (b) ARCHITECTURE.md propone `"functions": { "backend/api/**/*.js": {} }` en el `vercel.json` de raíz, con la alternativa de bajo esfuerzo de **mover físicamente** `backend/api/` a `<raíz>/api/` si el glob no funciona. (c) PITFALLS.md no propone mecanismo, pero advierte sobre el orden de los `rewrites` (el catch-all de SPA nunca antes que `/sync/*`) sin importar cuál de los dos mecanismos se use.
- **Por qué importa:** los tres coinciden en que ninguno fue validado contra un deploy real — es el punto de mayor incertidumbre técnica de todo el research, y un error acá puede romper `/sync/push`/`/sync/state` en producción (el celular real depende de esos endpoints hoy).
- **Riesgo concreto:** elegir un mecanismo que no funcione descubre el problema recién en deploy, potencialmente en producción si no se prueba primero en Preview.
- **Recomendación de este resumen:** correr el spike de `vercel dev` (ya sugerido por los tres documentos) al arrancar la Fase 12, probando primero el mecanismo (a) de STACK.md (shims de re-export) por ser el que menos reestructura `backend/` (que ADR-005/ADR-010 declaran de su propiedad exclusiva) — si falla, caer al glob de `functions` (b), y como último recurso mover físicamente `backend/api/`. En cualquier caso, el catch-all de SPA va siempre después de `/sync/*` y `/storage/*` en el array de `rewrites`, y el smoke test de `GET /sync/state` respondiendo JSON (no HTML) en un deploy de Preview es la validación de cierre antes de mergear a `main`.

### 5. Mitigación del gap de paginación por concurrencia (Pitfall 1)

- **Qué se decidió (research):** ARCHITECTURE.md y PITFALLS.md coinciden en la solución (watermark de 2s: `safeUpperBound = MAX(change_seq) WHERE updated_at <= now() - interval '2s'`), así que esto **no** es una discrepancia real — se incluye acá solo porque es la pieza de diseño más importante del milestone y conviene que quede visible arriba, no enterrada en ARCHITECTURE.md. Alternativa descartada explícitamente por ambos: snapshot transaccional con `pg_current_snapshot()`/txid — más correcto pero over-engineering para v0 de un solo editor.
- **Riesgo concreto si no se implementa:** una fila con commit tardío queda salteada para siempre por el cursor del cliente (no es delay, es pérdida de sincronización de ese cambio específico — recuperable solo forzando un pull completo desde `cursor=0`).
- **Ceiling documentado (`ponytail`):** el margen de 2s asume que ninguna transacción de push tarda más que eso; si se prueba lo contrario, subir la constante es el único cambio necesario, no una reescritura.

## Key Findings

### Recommended Stack

Backend ya validado (Vercel Functions + Neon, ADR-001) se extiende sin cambiar de proveedor. La web nueva usa Vite + React 19 + Leaflet/react-leaflet — stack liviano, sin SSR, apropiado para una SPA admin de un solo usuario y baja frecuencia de uso. Storage de audio nuevo: Vercel Blob (ver decisión abierta #2 sobre público/privado).

**Core technologies:**
- Vite 8.3.0 — build tool del frontend — sin necesidad de SSR/Next.js para una web admin de solo lectura
- React 19.3.0 + react-leaflet 5.0.0 — primera versión de react-leaflet con soporte oficial de React 19 (peer dependency, no mezclar con react-leaflet 4.x)
- Leaflet 1.9.4 — motor de mapa raster; MapLibre GL JS (vector tiles/WebGL) descartado por ser over-engineering para un mapa de un solo artista
- `@vercel/blob` 2.8.0 — SDK de storage; usar `presignUrl`/`handleUploadPresigned`, no el flujo legacy `handleUpload` (ver decisión abierta #3)

### Expected Features (alcance del milestone, no un research de mercado)

**Must have (dentro de v1.0):**
- `GET /sync/pull` (BE-01) — mismo protocolo que push, mismo endpoint para web y celular (ADR-004)
- `WEB_API_KEY` (BE-03) + pantalla de acceso simple
- Web de solo lectura: mapa general, listados y detalle de recorridos/obras/artistas/paths/audios, estado de sync
- Storage de audio server-side (BE-04): autorización de subida + URL de descarga
- BE-05: agregar `recorridos` a `state.js` (falta hoy)
- Verificación activa de que Preview no usa `DATABASE_URL` de Production (ADR-005, ya marcado como pendiente en PROJECT.md)

**Explícitamente fuera de este milestone:**
- Toda escritura desde la web (ADR-006 etapas 1 y 2) y `staleIds` (BE-02) — milestone posterior
- Multi-usuario, resolución de conflictos — v1 del ERS, no v0

### Architecture Approach

El pull reutiliza el mismo `TABLE_SPEC`/serialización epoch que ya usa el push (`spec.js`), sobre una única secuencia global `change_seq` compartida por las 7 tablas — una query `UNION ALL` acotado por tabla con `ORDER BY change_seq LIMIT N` externo da orden total correcto usando los índices `*_change_seq_idx` ya existentes (no hace falta crear índices nuevos). El mayor riesgo de diseño (gap de paginación por concurrencia) se resuelve con un watermark de tiempo, no con infraestructura nueva (ver decisión abierta #5).

**Componentes principales:**
1. `backend/api/sync/pull.js` (nuevo) — endpoint de lectura paginada, mismo auth dual-key que push/state
2. `backend/api/_lib/auth.js` (modificado) — acepta `SYNC_API_KEY` o `WEB_API_KEY`, ambas con `timingSafeEqual`
3. `backend/api/storage/upload-url.js` (nuevo) — autorización de subida directa cliente→Blob
4. Web nueva (Vite+React+Leaflet, ubicación a resolver — decisión abierta #1) — consume `/sync/pull` con loop de paginación en memoria, sin modo especial de "snapshot"

### Critical Pitfalls

1. **Gap de paginación por commits concurrentes fuera de orden** — mitigar con watermark de 2s sobre `updated_at`, no con snapshot transaccional (decisión abierta #5)
2. **`change_seq` BIGINT serializado como `number` de JS pierde precisión** — castear siempre a `::text` en SQL, replicando el patrón ya usado en `state.js:5`
3. **Rewrites de `vercel.json` combinado (SPA + functions) pisan `/sync/*`** — el catch-all de la SPA siempre después de las reglas específicas; smoke test de `GET /sync/state` contra Preview antes de cualquier merge a `main`
4. **`web/` ya existe y son restos de build de Flutter Web** — resolver antes de escribir cualquier código de UI (decisión abierta #1)
5. **`WEB_API_KEY` en el browser no puede ser un secreto real** — aceptar como barrera débil documentada (proporcional al riesgo: solo lectura, sin PII), usar `sessionStorage` no `localStorage`, nunca loguear el header `Authorization`

## Implications for Roadmap

Numeración continua sobre la que ya usa el workstream `web` (arranca en Fase 10, per PROJECT.md).

### Fase 10: `GET /sync/pull` + BE-05
**Rationale:** cierra el contrato que el workstream `app` (Fase 3) necesita antes de programar el lado celular — no depende de nada nuevo, solo usa schema/spec ya existentes.
**Delivers:** endpoint de pull paginado con watermark de 2s, serialización epoch simétrica con push, `state.js` con `recorridos` agregado.
**Avoids:** Pitfalls 1, 2, 3, 4, 5 (todos los de diseño de la query).

### Fase 11: `WEB_API_KEY` dual-key (BE-03)
**Rationale:** sin dependencias, desbloquea cualquier endpoint que la web deba llamar (pull, storage). Puede ejecutarse en paralelo con Fase 10 (no comparten archivos salvo `auth.js`, que ninguna otra fase toca).
**Delivers:** `auth.js` modificado aceptando `SYNC_API_KEY` o `WEB_API_KEY`, ambas con `timingSafeEqual` por candidato.
**Avoids:** Pitfall 6 (documentar el riesgo aceptado de `WEB_API_KEY` como barrera débil, no "arreglarlo").

### Fase 12: Infra de ruteo + resolución de colisión `web/`
**Rationale:** hace falta poder deployar algo servible (SPA + functions en el mismo proyecto Vercel) antes de construir features de UI encima. Puede arrancar en paralelo con 10/11.
**Delivers:** decisión ejecutada sobre destino del código (decisión abierta #1), `vercel.json` de raíz con el mecanismo de ruteo validado por spike (decisión abierta #4), verificación activa de Preview vs Production `DATABASE_URL` (ADR-005, PROJECT.md:122).
**Avoids:** Pitfalls 8, 9, 10 — todos los de deploy/infraestructura.
**Nota:** esta es la fase de mayor incertidumbre técnica del milestone — requiere el spike de `vercel dev` antes de comprometerse a un mecanismo.

### Fase 13: Web de gestión (Vite+React+Leaflet)
**Rationale:** depende de que 10 (contrato de pull cerrado), 11 (auth) y 12 (deploy funcionando) estén resueltas.
**Delivers:** pantalla de acceso, loop de pull completo, mapa general (bbox/paths/triggers), listados y detalle de recorridos/obras/artistas/paths/audios, estado de sync.
**Addresses:** todo el alcance de "Web (solo lectura)" del milestone.
**Avoids:** Pitfall 7 (grep de `dist/` sin secretos server-only antes de deploy), UX pitfalls (feedback de carga durante paginación, estado visual de "audio pendiente").

### Fase 14: Storage de audio (BE-04)
**Rationale:** depende de 11 (dual-key). Desbloquea tanto la subida desde el celular (Fase 2.2 de `app`) como la reproducción de audio en la web de este milestone.
**Delivers:** decisión de proveedor ejecutada (decisión abierta #2), flujo de upload elegido (decisión abierta #3), `POST /api/storage/upload-url`, constante de build para armar URLs de audio en la web.
**Avoids:** Security Mistake de blob público sin protección (PITFALLS.md).

### Phase Ordering Rationale

- 10 y 11 no comparten archivos (pull.js nuevo vs auth.js modificado) → paralelizables.
- 12 es infraestructura de deploy pura, no de negocio → paralelizable con 10/11, pero bloquea 13.
- 13 y 14 son las únicas fases con dependencia dura hacia atrás — 13 necesita 10+11+12; 14 necesita solo 11 pero en la práctica conviene después de 13 para no bloquear la entrega visible de la web.

### Research Flags

Necesitan más investigación/spike durante planning:
- **Fase 12:** mecanismo de ruteo Vercel monorepo — confianza MEDIA-BAJA en los tres documentos, ninguno validado contra deploy real. Requiere spike de `vercel dev` de 30-60 min antes de comprometerse a una fase completa.
- **Fase 14:** confirmar en la práctica que `presignUrl`/`handleUploadPresigned` funciona igual de simple desde Flutter/Dart como se asume en STACK.md — no se probó contra un cliente Dart real en este research.

Fases con patrones bien establecidos (research-phase probablemente innecesario):
- **Fase 10:** el diseño de la query (UNION ALL acotado + watermark) está verificado contra el schema real y los índices ya existentes — implementación directa.
- **Fase 11:** modificación de `auth.js` es un patrón estándar (timing-safe multi-key), bajo riesgo.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIA-ALTA | Versiones verificadas contra npm registry y docs oficiales de Vercel/Cloudflare el mismo día; el mecanismo de integración monorepo queda en MEDIA |
| Features | ALTA | Alcance ya fijado en PROJECT.md/ADRs, no es un research de mercado abierto |
| Architecture | MEDIA | Diseño de pull verificado contra código real (ALTA); ruteo Vercel y necesidad de endpoint de download-url quedan como spikes no ejecutados (MEDIA-BAJA) |
| Pitfalls | MEDIA | Patrones verificados contra código real + docs oficiales 2026; algunos límites de proveedor (timeouts Vercel Hobby, cold start de Neon) son de fuentes agregadas, no fetch directo |

**Overall confidence:** MEDIA — el núcleo de diseño de datos (pull, watermark, auth) es sólido; el mayor riesgo no resuelto es de infraestructura de deploy (ruteo monorepo), no de lógica de negocio.

### Gaps to Address

- Mecanismo exacto de ruteo Vercel para servir SPA + functions del mismo proyecto — resolver con spike al arrancar Fase 12, no asumir ninguno de los tres mecanismos propuestos sin probarlo.
- Visibilidad de Vercel Blob (público vs privado) — decisión abierta #2, afecta si BE-04 necesita un endpoint de descarga firmada o no.
- Validación real de `presignUrl`/`handleUploadPresigned` desde un cliente Dart — no probado, solo argumentado por compatibilidad de protocolo HTTP genérico.
- Confirmación explícita del usuario sobre destino de `web/` (decisión abierta #1) antes de ejecutar cualquier borrado.

## Sources

### Primary (confianza ALTA)
- Código del repo leído directamente: `backend/schema.sql`, `backend/api/sync/{push,state}.js`, `backend/api/_lib/{auth,db,spec,outbox}.js`, `backend/vercel.json`, `backend/.env.example`, `lib/data/sync/sync_api.dart`, `web/index.html`, `.planning/PROJECT.md`, `.planning/ARCHITECTURE.md`
- npm registry (`npm view`, 2026-09-23): `leaflet@1.9.4`, `react-leaflet@5.0.0`, `vite@8.3.0`, `react@19.3.0`, `@vercel/blob@2.8.0`
- https://operations.osmfoundation.org/policies/tiles/ — política de tiles OSM

### Secondary (confianza MEDIA)
- https://vercel.com/docs/vercel-blob, /usage-and-pricing, /vercel-signed-urls, /client-upload, /using-blob-sdk
- https://developers.cloudflare.com/r2/pricing/
- https://vercel.com/docs/project-configuration/vercel-json, /monorepos, /monorepo-faq
- https://neon.com/docs/serverless/serverless-driver, /connect/connection-latency
- https://vercel.com/docs/functions/limitations; changelog de 60s en Hobby

### Tertiary (confianza BAJA-MEDIA, agregado de fuentes no oficiales)
- https://www.backblaze.com/cloud-storage/pricing
- Comparativas de blogs 2026 sobre pricing Neon vs Supabase y Fly.io free tier
- Comparativas Leaflet vs MapLibre GL JS (jawg.io, LogRocket)

---
*Research completed: 2026-09-23*
*Ready for roadmap: yes, con 5 decisiones abiertas a resolver antes/durante Fase 12*


> **Reemplazado (2026-09-23):** este margen sobre `updated_at` es inválido — esa columna la pone el cliente, no el servidor, así que no protege contra el commit tardío que describe. El mecanismo real se decidió en `phases/10-pull-cerrado-auth-dual-key/10-CONTEXT.md` D-01 (advisory lock de Postgres) y en el ADR correspondiente en Notion.