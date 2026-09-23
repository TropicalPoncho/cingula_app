# Stack Research — workstream `web`, milestone v1.0 (Web de gestión, lectura)

**Dominio:** Web de administración de solo lectura (Vite+React+Leaflet) sobre un backend Vercel Functions + Neon ya validado (ADR-001), más storage de audio server-side nuevo (BE-04).
**Investigado:** 2026-09-23
**Confianza general:** MEDIA-ALTA (versiones y límites de free tier verificados contra docs oficiales via WebFetch el mismo día; el mecanismo exacto de "una sola app Vercel = frontend Vite + funciones en `backend/api`" queda en confianza MEDIA, ver sección de integración)

## Decisión de storage — arriba de todo (regla de oro)

**Decisión:** usar **Vercel Blob** (modo `private`) como proveedor de storage para BE-04, con **Cloudflare R2** documentado como alternativa de reemplazo directo si el volumen de audio crece.

**Por qué:** Vercel Blob se crea y conecta al mismo proyecto Vercel que ya aloja `backend/` con un click — cero cuenta nueva, cero credencial nueva que gestionar (usa OIDC automático), lo que es coherente con "mantenerlo mínimo" (constraint del milestone + ponytail). Soporta exactamente lo que pide BE-04: subida autorizada directa cliente→storage vía URL firmada real tipo S3 (`presignUrl`/`handleUploadPresigned`, ver abajo) que cualquier cliente HTTP puede usar — sin esto, el celular (Flutter/Dart) habría quedado atado a instalar el SDK JS de Vercel, que no existe para Dart.

**Alternativas descartadas:**
- **Cloudflare R2** — técnicamente superior en capacidad (10GB storage gratis vs 1GB de Blob, egress siempre gratis) y en semántica de storage (API S3 real: soporta `If-None-Match` condicional nativo y checksums `x-amz-checksum-sha256`), pero exige una cuenta Cloudflare nueva, un token API nuevo para guardar como env var de Vercel, y una librería de firmado S3 (`aws4fetch` o similar) como dependencia nueva del backend. Para el volumen actual (~77 audios) es más infraestructura de la que hace falta hoy.
- **Backblaze B2** — mismo problema (cuenta nueva) más un modelo de egress gratis "3x lo almacenado" más difícil de razonar que el de R2; sin ganancia clara sobre R2 para este caso. Descartado sin research más profundo por no aportar nada que R2 no dé mejor.

**Riesgo concreto mientras no se resuelva (o si se ignora):** el free tier Hobby de Vercel Blob da **1GB de storage** (ver tabla de pricing abajo). Si los audios "finales" subidos desde la web son similares en tamaño a grabaciones de campo (`.wav`, "decenas de MB" según el contexto del milestone), ~100 archivos de 10MB ya agotan el free tier. Esto es manejable en este milestone (v1.0 solo habilita el mecanismo, no migra el backlog completo), pero **hay que monitorear el uso real** antes de que el celular (fase 2.2 de `app`) empiece a subir grabaciones de campo por el mismo bucket.

**Qué cambiaría la decisión:** si el storage se acerca o supera 1GB, o si se decide que las subidas de campo (.wav crudos, potencialmente más pesados) van al mismo store — migrar a R2. El costo de ese cambio es bajo: `storage_key` en la tabla `audios` (`backend/api/_lib/spec.js:16`) es un `text` opaco por diseño (ADR-002/ADR-003), no un URL de un proveedor específico, así que cambiar de proveedor no toca el esquema, solo la implementación de los dos endpoints nuevos de autorización/descarga.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Vite | 8.3.0 | Build tool / dev server del frontend | Verificado en npm registry (2026-09-23). Estándar de facto para SPAs React que no necesitan SSR — la web es de solo lectura, sin necesidad de Next.js/SSR (agregarlo sería sobre-ingeniería para este milestone). |
| React | 19.3.0 | UI library | Verificado en npm registry. Elegido en el ERS; no hay razón para desviarse — Preact ahorraría ~30KB gzip pero suma fricción de compatibilidad con `react-leaflet` (que depende de la API de React real) sin beneficio medible para una web admin de un solo usuario. |
| Leaflet | 1.9.4 | Motor de mapa (raster tiles, WebGL no necesario) | Verificado en npm registry. Confirma la propuesta del ERS. Para un mapa admin de baja frecuencia con tiles raster (OSM), markers y overlays vectoriales simples (paths, círculos de trigger), Leaflet es la opción más liviana y madura — MapLibre GL JS (WebGL, vector tiles) es la alternativa 2026 "de punta" pero apunta a mapas con miles de features/animaciones/3D, que no es el caso de esta web. Fuente: comparativa 2026 (ver Sources). |
| `react-leaflet` | 5.0.0 | Bindings de React para Leaflet | Verificado en npm registry. Capa fina sobre Leaflet, sin lógica propia de mapa — evita manejar el ciclo de vida imperativo de Leaflet a mano dentro de componentes React. |
| `@vercel/blob` | 2.8.0 | SDK de storage (autorización de subida + `presignUrl`) | Verificado en npm registry. Ya cubre el flujo completo que pide BE-04: `issueSignedToken` + `presignUrl` para emitir URLs de subida/descarga firmadas tipo S3, sin exponer ningún token de larga vida al cliente. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Ninguna adicional para el mapa | — | — | No sumar `leaflet.markercluster`, `leaflet-draw`, etc. — la web es de solo lectura (sin edición de geometría) y el volumen de obras/triggers de un solo artista no justifica clustering todavía. Agregar si/cuando el mapa general se vuelva ilegible con muchas obras simultáneas. |
| Ninguna librería de routing adicional | — | — | Para una web pequeña de listados+detalle+mapa, `react-router` es razonable si hace falta más de 3-4 vistas, pero no se investigó a fondo por no ser una decisión que afecte arquitectura — evaluar en fase de planning con el conteo real de pantallas del ERS. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Vercel CLI (`vercel dev`) | Emulación local de build + functions juntos | Usar temprano en la fase de integración (ver abajo) para validar que el rewrite `/sync/*` sigue llegando a `backend/api` una vez que `web/` se agrega al mismo proyecto — esto es lo más frágil de esta integración y conviene probarlo con un smoke test antes de construir features. |

## Installation

```bash
# web/ (nuevo)
cd web
npm create vite@latest . -- --template react
npm install leaflet react-leaflet

# backend/ (agrega SDK de storage a lo ya existente)
cd backend
npm install @vercel/blob
```

## Integración en el mismo proyecto Vercel — cómo servir `web/` y `backend/` juntos

**Contexto actual:** el proyecto Vercel hoy tiene Root Directory = `backend/` (así es como `backend/vercel.json` con su `rewrites` funciona: Vercel busca funciones en `<RootDirectory>/api/**`, o sea `backend/api/**`, por convención fija — esto **no** es configurable vía la propiedad `functions` de `vercel.json`, que solo ajusta runtime/memoria/duración de funciones que ya están bajo `api/`, no dónde viven).

**Consecuencia práctica:** para que el mismo proyecto sirva también el build de `web/`, el Root Directory tiene que pasar a ser la raíz del repo (no `backend/`), y el `vercel.json` (movido a la raíz del repo) necesita decirle a Vercel dónde construir el frontend y dónde siguen viviendo las funciones:

```json
{
  "buildCommand": "npm install --prefix web && npm run build --prefix web",
  "outputDirectory": "web/dist",
  "installCommand": "npm install --prefix backend",
  "rewrites": [
    { "source": "/sync/:path*", "destination": "/api/sync/:path*" }
  ]
}
```

El punto que **no** se puede resolver solo con configuración: las funciones de Vercel tienen que estar físicamente bajo `<raíz-del-repo>/api/`, no bajo `backend/api/`. La forma de no reestructurar `backend/` (que ADR-005/ADR-010 declaran dueño de todo el backend) es un **shim fino de re-export** en `<raíz>/api/sync/push.js`:

```js
export { default } from '../backend/api/sync/push.js';
```

Un archivo así por endpoint (`push.js`, `state.js`, y los nuevos `pull.js`/storage). Es el mínimo diff que respeta la convención dura de Vercel sin mover la lógica real de `backend/`.

**Confianza: MEDIA.** La regla "las funciones deben vivir bajo `<RootDirectory>/api/`" es comportamiento estable de Vercel documentado hace años y no contradicho por ninguna página oficial revisada hoy, pero no se validó con un deploy real dentro de esta investigación. **Antes de construir features en la fase de integración, correr `vercel dev` desde la raíz del repo y confirmar en vivo que `GET /sync/state` sigue respondiendo** — es la validación más barata posible y evita descubrir un problema de ruteo después de escribir la web entera.

## Política de tiles OSM

`tile.openstreetmap.org` (el tile server público de OSM) prohíbe **bulk downloading** (prefetch de zoom levels/áreas no visibles, cache offline) pero permite explícitamente el uso normal de "pedir solo los tiles del viewport actual, cacheados localmente respetando headers de cache (mínimo 7 días)". Esto encaja exacto con esta web: es de un solo usuario, de baja frecuencia, **online-only por diseño (ADR-008)** — no hay necesidad de pre-cachear regiones ni de soporte offline, así que no hay riesgo de violar la política. Requisito no negociable: atribución visible "© OpenStreetMap contributors" en el mapa, sin ocultarla detrás de un toggle. Confianza: ALTA (leído directo de la página de política oficial de OSMF).

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| Vercel Blob (storage) | Cloudflare R2 | Si el storage se acerca a 1GB o el celular empieza a subir `.wav` de campo por el mismo bucket — ver sección de decisión arriba. R2 da 10GB gratis + egress siempre gratis + soporta `If-None-Match` condicional nativo y checksums S3 reales, a cambio de una cuenta y un SDK de firmado S3 nuevos. |
| Vercel Blob | Backblaze B2 | Solo si por algún motivo R2 dejara de ser viable — B2 es S3-compatible también pero su modelo de egress ("3x lo almacenado gratis por mes") es más difícil de auditar contra el patrón de uso real que el de R2 (egress siempre gratis). No se investigó a fondo por no aportar nada que R2 no cubra mejor. |
| Leaflet + react-leaflet | MapLibre GL JS (+ `maplibre-react-components` o `@maplibre/maplibre-gl-leaflet`) | Si el mapa necesita tiles vectoriales, estilos dinámicos, o miles de features con buen rendimiento (no es el caso de un solo artista/recorrido). Migrar más adelante es viable vía `@maplibre/maplibre-gl-leaflet` (binding que expone la API de Leaflet sobre un renderer MapLibre) si hiciera falta sin reescribir toda la capa de mapa. |
| Vite + React | Next.js | Si la web necesitara SSR, rutas API propias del frontend, o SEO — ninguna aplica a una web admin de un solo usuario detrás de `WEB_API_KEY`. Agregar Next.js hoy sería sobre-ingeniería (duplicaría además la capa de "funciones" que ya existe en `backend/`). |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|--------------|
| SDK `@vercel/blob` legacy `handleUpload` (token de cliente, no presignado) | Funciona, pero está pensado para clientes que ya usan el SDK JS del lado navegador (`upload()`); un cliente Dart/Flutter tendría que reimplementar el protocolo de token interno de Vercel a mano. | `handleUploadPresigned` + `presignUrl` — genera URLs `PUT` firmadas estándar que se consumen con un `fetch`/`http.put` genérico, sin SDK, iguales para browser y para Flutter. |
| `allowOverwrite: true` como default en la subida de audio | Rompe la garantía de inmutabilidad de `storage_key` que pide ADR-003 ("archivos de audio inmutables en storage"); el default real de Vercel Blob (rechazar si el pathname ya existe) es justamente la protección correcta. | Dejar el default (rechazo en colisión) o `addRandomSuffix: true` si se necesita reintentar con el mismo nombre base. |
| MapLibre GL JS para este milestone | Motor WebGL pensado para tiles vectoriales/miles de features/estilos dinámicos — ninguna de esas necesidades existe en un mapa admin de un artista. Suma peso de bundle y una curva de aprendizaje distinta a Leaflet sin beneficio medible hoy. | Leaflet + react-leaflet (recomendado arriba). |
| Cache/prefetch de tiles OSM fuera del viewport actual | Viola la política de uso de OSM (bulk downloading), que puede resultar en bloqueo sin aviso — y de todos modos ADR-008 dice que la web es online-only, no hay caso de uso real para esto. | Dejar el comportamiento estándar de Leaflet (pedir solo lo visible, respetar cache-control). |

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `react-leaflet@5.0.0` | `react@19.x` | react-leaflet 5.x es la primera major con soporte oficial para React 19 (peer dependency); no mezclar con react-leaflet 4.x si se usa React 19. |
| `@vercel/blob@2.8.0` (`handleUploadPresigned`/`presignUrl`) | Node >=22 (ya fijado en `backend/package.json:5`) | Sin conflicto — mismo runtime que ya usan `push.js`/`state.js`. Requiere agregar `BLOB_WEBHOOK_PUBLIC_KEY` como env var nueva para verificar el callback `onUploadCompleted` cuando se usa el flujo presignado. |
| Root Directory del proyecto Vercel | `web/` + `backend/` en el mismo repo | Cambiar Root Directory de `backend/` a la raíz del repo es un cambio de configuración del proyecto Vercel (dashboard), no solo de código — coordinarlo con el ADR-005 (aislamiento de prod por rama+preview+rama de Neon) para no romper el deploy de Production existente durante la transición. |

## Nota: `web/` tiene restos de scaffolding de Flutter web

`web/index.html`, `manifest.json`, `favicon.png` e `icons/` son el output estándar de `flutter build web` (el `<base href="$FLUTTER_BASE_HREF">` sin reemplazar y `flutter_bootstrap.js` lo confirman) — no son parte de la web nueva de gestión. Hay que **borrarlos**, no reutilizarlos ni "adaptarlos": son de un build de Flutter Web que aparentemente nunca se usó, y dejarlos mezclados con el `index.html` real de Vite (que Vite también genera en la raíz de `web/`) va a generar colisión de archivo y confusión sobre cuál es la app real. Flag para la fase de ejecución, no una decisión de stack en sí.

## Sources

- https://vercel.com/docs/vercel-blob — free tier, overwrite/immutabilidad, multipart, storage por S3 (fetched 2026-09-23)
- https://vercel.com/docs/vercel-blob/usage-and-pricing — tabla de pricing Hobby (1GB storage / 10K simple ops / 2K advanced ops / 10GB data transfer) (fetched 2026-09-23)
- https://vercel.com/docs/vercel-blob/vercel-signed-urls — `issueSignedToken`/`presignUrl`/`handleUploadPresigned`, confirma URLs PUT firmadas consumibles con `fetch` genérico sin SDK (fetched 2026-09-23)
- https://vercel.com/docs/vercel-blob/client-upload — flujo de token de cliente legacy (`handleUpload`/`upload()`), confirma que requiere el SDK JS (fetched 2026-09-23)
- https://developers.cloudflare.com/r2/pricing/ — free tier R2: 10GB storage, 1M Class A ops, 10M Class B ops, egress siempre gratis (fetched 2026-09-23)
- https://www.backblaze.com/cloud-storage/pricing — free tier B2: 10GB storage, egress "3x lo almacenado" (fetched 2026-09-23) — confianza MEDIA, no se verificó soporte de presigned URLs en detalle
- https://operations.osmfoundation.org/policies/tiles/ — política de uso de tiles OSM, bulk downloading prohibido, uso normal de viewport permitido (fetched 2026-09-23)
- https://vercel.com/docs/monorepos y https://vercel.com/docs/project-configuration — confirman que Root Directory determina dónde Vercel busca `/api`; no se encontró una página que documente explícitamente mover `/api` de lugar vía `functions`, de ahí la confianza MEDIA en la sección de integración (fetched 2026-09-23)
- npm registry (`npm view <pkg> version`, 2026-09-23): `leaflet@1.9.4`, `react-leaflet@5.0.0`, `vite@8.3.0`, `react@19.3.0`, `@vercel/blob@2.8.0`
- WebSearch "react-leaflet 2026 version MapLibre GL JS vs Leaflet lightweight admin map current" — confirma Leaflet como opción liviana estándar para mapas raster/admin, MapLibre como alternativa 2026 para vector tiles/WebGL — confianza MEDIA (agregado de blogs, no doc oficial) — [MapLibre vs Leaflet (jawg.io)](https://blog.jawg.io/maplibre-gl-vs-leaflet-choosing-the-right-tool-for-your-interactive-map/), [React map library comparison (LogRocket)](https://blog.logrocket.com/react-map-library-comparison/), [@maplibre/maplibre-gl-leaflet (npm)](https://www.npmjs.com/package/@maplibre/maplibre-gl-leaflet)
- Código existente: `backend/package.json`, `backend/vercel.json`, `backend/api/_lib/spec.js` (columnas `storage_key`/`checksum` de `audios`), `web/index.html` — leídos directamente

---
*Stack research for: workstream `web`, milestone v1.0 (Web de gestión, lectura)*
*Researched: 2026-09-23*
