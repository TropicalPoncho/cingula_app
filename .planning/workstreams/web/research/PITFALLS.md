# Pitfalls Research

**Domain:** `GET /sync/pull` paginado, `WEB_API_KEY`, storage de audio, web Vite+React+Leaflet en el mismo proyecto Vercel que `backend/`
**Researched:** 2026-09-23
**Confidence:** MEDIUM (patrones verificados contra código real del repo + docs oficiales 2026; algunos límites de proveedor son de fuentes agregadas, marcados abajo)

## Critical Pitfalls

### Pitfall 1: Paginación por `change_seq` que "salta" filas con commits concurrentes

**What goes wrong:**
El cliente pide `?cursor=100&limit=500`, recibe filas hasta `change_seq=600`, guarda `cursor=600`. Pero la fila `change_seq=550` fue asignada por `nextval('change_seq')` en un `UPDATE` que todavía no había hecho commit cuando la página se leyó (transacción más lenta que arrancó antes). Esa fila commitea *después* de que el cursor ya avanzó a 600 — el próximo pull pide `>600` y la fila 550 nunca se entrega. Es el clásico "gap" de secuencias con transacciones concurrentes: `nextval()` reserva el número en el momento de INSERT/UPDATE, no en el commit, así que el orden de *asignación* no es el orden de *visibilidad*.

**Why it happens:**
`schema.sql:129-134` (`bump_change_seq()`) asigna `change_seq` vía `nextval('change_seq')` en el trigger `BEFORE INSERT OR UPDATE` — es decir, en el momento en que la fila se toca, no cuando la transacción se hace visible. `push.js:40` corre `sql.transaction(outbox.map(...))`, y como cada item de un outbox es un statement separado dentro de la misma transacción de push, hay ventanas reales donde dos pushes concurrentes (poco probable con un solo editor, pero MUY probable cuando la web y el celular sincronizan en paralelo después de este milestone) generan secuencias entrelazadas.

**How to avoid:**
El pull nunca debe leer "todo lo mayor a cursor" con una sola condición ingenua contra `MAX(change_seq)` reciente. Dos estrategias estándar, elegir una explícitamente en el diseño de BE-01:
1. **Cursor con margen de seguridad (safe watermark):** no devolver filas con `change_seq` mayor a `now() - margen` (ej. últimos 2-3 segundos), dando tiempo a que transacciones en vuelo comiteen antes de que esa zona del rango se considere "cerrada". Simple, no requiere tocar el schema.
2. **`pg_current_snapshot()` / `txid` visible:** guardar en el cursor no solo el `change_seq` máximo sino el conjunto de transacciones en vuelo al momento de la lectura, y en el próximo pull re-consultar ese rango. Más correcto, más complejo — probablemente over-engineering para v0 de un solo editor (ver Technical Debt Patterns).
Para este milestone (`web` de solo lectura, sin escritura concurrente real todavía), la opción 1 con un margen conservador basta; documentarlo explícitamente como decisión consciente, no como "no lo pensamos".

**Warning signs:**
Un registro que aparece en `state.js` (`MAX(change_seq)`) pero nunca llega por `/sync/pull` aunque el cursor ya avanzó más allá de su `change_seq`. Difícil de reproducir en dev con un solo escritor — por eso es crítico decidirlo en diseño, no descubrirlo en producción cuando el celular (Fase 3 de `app`) dependa de este mismo contrato.

**Phase to address:**
Fase de implementación de `GET /sync/pull` (BE-01), en el diseño del contrato antes de escribir el handler — porque el celular (workstream `app`, Fase 3) va a consumir el mismo endpoint y no puede descubrir el problema tarde.

---

### Pitfall 2: `change_seq` BIGINT serializado como número JS pierde precisión

**What goes wrong:**
`change_seq` es `bigint` (`schema.sql:16` y en cada tabla), que en Postgres puede superar `Number.MAX_SAFE_INTEGER` (2^53-1) tras suficientes writes. Si el handler serializa `change_seq` como `number` en el JSON de respuesta (`response.status(200).json({ ...changes })` con el valor crudo de una columna bigint), a partir de ~9 mil billones de cambios el valor se corrompe silenciosamente al parsear en JS — típicamente el LSB se redondea, y el cliente compara `changeSeq > cursor` con un cursor que ya no corresponde al valor real en la DB.

**Why it happens:**
El driver `@neondatabase/serverless` devuelve columnas `bigint` como `string` por defecto en `sql.query()` a través de `pg`'s type parsers configurados para eso — pero es fácil pisarlo sin darse cuenta al construir el JSON de respuesta a mano, o al pasar el valor por un `Number(...)` "para limpiar el tipo" en el código del handler.

**How to avoid:**
`state.js:5` ya hace esto bien: `SELECT COALESCE(MAX(seq), 0)::text AS cursor` — castea a texto explícitamente en SQL, no confía en el tipo del driver. Replicar el mismo patrón en `/sync/pull`: el cursor de entrada y salida siempre viaja como `string` en el JSON, nunca como `number`. En el cliente (Dart/JS), el cursor se trata como string opaco, nunca se le hace aritmética — coincide con `SyncPullResult.serverCursor` ya tipado como `String` en `lib/data/sync/sync_api.dart:43`. Si el handler necesita comparar/ordenar `change_seq` de filas individuales dentro del payload (no solo el cursor), castear también esas columnas a texto en el SQL de selección, igual que el cursor.

**Warning signs:**
Un test con `change_seq` pequeño (números de 1 a 3 dígitos en dev) nunca revela esto — la corrupción solo aparece cuando la secuencia real supera 2^53. Por eso es un pitfall de "se ve andando en dev, revienta en producción meses después"; la prevención tiene que ser una regla de código (nunca `Number(row.change_seq)`), no un test.

**Phase to address:**
Fase de implementación de `GET /sync/pull` (BE-01) — copiar literalmente el patrón `::text` de `state.js:5`, y agregarlo también a cualquier columna `change_seq` que viaje en el array de `changes`, no solo en el cursor top-level.

---

### Pitfall 3: Empates de `change_seq` entre tablas rompen el orden total esperado por el cliente

**What goes wrong:**
`change_seq` sale de una **única** secuencia compartida (`CREATE SEQUENCE change_seq` en `schema.sql:6`, usada por las 7 tablas vía el mismo trigger) — así que dentro de una tabla nunca hay empates, pero el pull cruza 7 tablas con un solo cursor global. Si el pull pagina con `ORDER BY change_seq LIMIT N` haciendo un `UNION ALL` de las 7 tablas (como ya hace `state.js:5-11` para el estado agregado), el orden es determinístico porque `change_seq` es único cross-tabla — **no hay empates reales**, a diferencia de un diseño con una secuencia por tabla. El riesgo real no es el empate sino que un `UNION ALL` sin `ORDER BY` explícito en la query externa puede devolver filas de las 7 sub-selects en cualquier orden dentro del mismo valor de `LIMIT`, y un `LIMIT` aplicado *antes* del `ORDER BY` global trunca mal el batch (corta a mitad de un rango que el cliente esperaba completo).

**Why it happens:**
Es tentador escribir la paginación de `/sync/pull` como "7 queries con su propio `LIMIT`, mezclar en la app" en vez de una sola query con `ORDER BY change_seq LIMIT N` sobre el `UNION ALL` — el primer enfoque es más simple de leer pero no da un orden total correcto ni un `LIMIT` que respete el cursor real.

**How to avoid:**
Una sola query: `SELECT * FROM (SELECT 'recorridos' t, *, change_seq FROM recorridos WHERE change_seq > $cursor UNION ALL ... ) s ORDER BY change_seq LIMIT $limit` — el `ORDER BY change_seq` externo al `UNION ALL` es lo que da orden total real (porque la secuencia es única y compartida, confirmado en `schema.sql:6`). Devolver como próximo cursor el `change_seq` de la última fila del batch, no `MAX(change_seq)` de la tabla (eso reintroduce el Pitfall 1 si se usa mal).

**Warning signs:**
Test con datos en solo 1-2 tablas nunca revela el problema de mezcla — hay que testear con cambios simultáneos en al menos 3 tablas distintas para confirmar que el batching cruza tablas en el orden correcto.

**Phase to address:**
Fase de implementación de `GET /sync/pull` (BE-01) — el `spec.js` ya tiene un `rank` por tabla (`spec.js:9,14,20,26,33,37,44`) pensado para orden de aplicación FK-safe en el push; verificar si el pull necesita ese mismo `rank` como *desempate secundario* documentado (aunque hoy no haya empates reales) para que el orden sea estable ante un futuro cambio de la secuencia compartida a secuencias por tabla.

---

### Pitfall 4: Vercel Function timeout + cold start de Neon combinados en el primer pull grande (backlog histórico)

**What goes wrong:**
El pull inicial de un cliente nuevo (la web recién configurada, o el celular después de este milestone) puede traer miles de filas de una vez — el propio `PROJECT.md:22` menciona un backlog real de 1186 filas históricas que tardó en sincronizarse por push; un pull equivalente sin límite de página puede tardar más que el timeout de la function. Sumado a esto, si la compute de Neon estaba en scale-to-zero (sin queries en 5 minutos, comportamiento default confirmado en docs de Neon), el cold start agrega 300-800ms extra antes de que la primera query corra.

**Why it happens:**
Vercel Hobby (el tier de este proyecto, `$0/mes`) tiene un timeout default de 30s con Fluid Compute (10s en proyectos legacy sin Fluid Compute) y un techo configurable de 60s como máximo — no hay forma de pedir más sin pasar a Pro. Un pull sin `LIMIT` explícito, o con un `LIMIT` demasiado alto (miles de filas con joins/formateo pesado), puede acercarse a ese techo, especialmente sumado al cold start de Neon.

**How to avoid:**
`/sync/pull` SIEMPRE pagina con un `LIMIT` conservador fijo en el servidor (no confiar en que el cliente lo pida corto) — un valor como 200-500 filas por página es razonable para este volumen de datos (recorridos/obras/paths/triggers de un solo artista, no miles de usuarios). El cliente (web y luego celular) hace múltiples requests hasta que `changes.length < limit`. Verificar en `vercel.json` de `backend/` (o el nuevo root si cambia con la web) si hace falta declarar `maxDuration` explícito para la function de pull. No hace falta pre-calentar Neon manualmente para v0 — el margen de 300-800ms es aceptable para una web administrativa, pero si se vuelve perceptible, evaluar el auto-suspend delay configurable de Neon (5min/30min/indefinido en planes pagos) — no aplicable en el free tier actual, así que no hay mucho margen de ajuste sin pasar a un tier pago.

**Warning signs:**
Pull que funciona en dev/staging con pocos datos y falla (504/timeout) solo contra el backlog real de producción — mismo patrón que ya pasó con el push en Fase 2 (`PROJECT.md:22`). Probar explícitamente contra el volumen real de datos existentes, no solo contra fixtures chicas.

**Phase to address:**
Fase de implementación de `GET /sync/pull` (BE-01) — el `LIMIT` de paginación es parte del contrato, no un detalle de implementación; documentarlo en la misma página ERS donde vive el resto del protocolo (referenciada en `PROJECT.md:109`) para que el celular (Fase 3 de `app`) programe el loop de paginación desde el día uno.

---

### Pitfall 5: Asimetría entre el payload de push y el de pull rompe el contrato que la Fase 3 del celular va a asumir

**What goes wrong:**
El push (`push.js`, `outbox.js`) tiene un formato de entrada muy específico: `logical_version` sale de `payload.logical_version` (`outbox.js:7-9`), timestamps `epoch` (segundos desde SQLite, `spec.js:3,6`) convertidos con `to_timestamp($n)` (`outbox.js:59`), deletes son un `op: 'delete'` separado sin payload completo (`outbox.js:47-53`). Si `/sync/pull` devuelve un formato distinto — por ejemplo, `updated_at`/`deleted_at` como ISO string en vez de epoch, o filas borradas representadas con un campo `deleted: true` en vez de `deleted_at` no-nulo, o `logical_version` en el nivel raíz de la fila en vez de dentro de un objeto `payload` — el celular (que reutiliza el mismo modelo de datos para push y pull) tiene que escribir dos parsers distintos, y cualquier divergencia sutil (null vs ausente, epoch vs ISO) es el tipo de bug que aparece semanas después cuando la Fase 3 de `app` ya está construida sobre un contrato asumido.

**Why it happens:**
El pull se implementa en un momento distinto que el push (workstream `web`, meses después de Fase 2), potencialmente por otra sesión de trabajo sin el mismo contexto fresco de las convenciones de `outbox.js`/`spec.js`. Es fácil "inventar" un formato de respuesta que parezca razonable en aislamiento (ISO timestamps son más legibles que epoch) sin notar que rompe la simetría con lo que el push ya estableció.

**How to avoid:**
Antes de escribir el handler de pull, escribir la definición del payload de respuesta lado a lado con `TABLE_SPEC`/`REQUIRED` de `spec.js` y decidir explícitamente: ¿las filas borradas se devuelven con todas sus columnas + `deleted_at` no-nulo (recomendado — permite al cliente decidir qué hacer con metadata residual) o solo `{uuid, table_name, deleted_at}` (payload mínimo)? ¿Los timestamps salen en el mismo formato `epoch` que espera `to_timestamp` en el push, o en ISO (formato nativo de Postgres/JS)? Como el pull es *lectura* y el push es *escritura*, no hay obligación de que el formato sea idéntico — pero si difiere, la diferencia tiene que ser una decisión documentada en el ERS (subpágina "Backend — protocolo de sync", `PROJECT.md:109`), no un accidente de implementación. Dado que ADR-004 dice que la web es "otro participante del mismo protocolo", el default correcto es reusar el mismo `TABLE_SPEC` para servir el pull, incluyendo el mismo tratamiento de `epoch` para consistencia — aunque el JS de la web no necesita `to_timestamp`, si el celular sí, es más simple tener un solo formato de wire para las dos direcciones.

**Warning signs:**
El equipo escribe el parser de pull en la web y "funciona a simple vista" porque JS es laxo con nulls/undefined — el bug real aparece cuando el celular (Dart, tipado, con modelos `sqflite` estrictos) intenta parsear el mismo payload y falla en un campo que la web silenciosamente ignoraba.

**Phase to address:**
Fase de implementación de `GET /sync/pull` (BE-01) para el diseño; pero la **verificación real** de que el contrato es usable por el celular no puede cerrarse hasta la Fase 3 de `app` — dejarlo explícito en el `STATE.md` del workstream `web` como "contrato provisional hasta que `app` lo consuma", igual que ya dice `PROJECT.md:109` ("El workstream `app` no programa contra un endpoint hasta que ese contrato esté cerrado").

---

### Pitfall 6: `WEB_API_KEY` en el browser — no hay forma de que sea un secreto real

**What goes wrong:**
A diferencia de `SYNC_API_KEY` (vive solo en el celular compilado + backend, nunca en un contexto donde JS arbitrario de terceros pueda leerlo), `WEB_API_KEY` tiene que llegar al browser para que el `fetch()` a `/sync/pull` incluya el header `Authorization: Bearer`. Cualquier valor que el JS del cliente pueda leer para adjuntarlo a un request, un atacante con XSS (o simplemente alguien que abra DevTools → Network) también puede leer. Guardarlo en `localStorage` lo hace persistente y accesible por cualquier script que corra en el origen (incluyendo dependencias de terceros comprometidas) — es leíble por cualquier XSS, sin siquiera necesitar acceso a Network.

**Why it happens:**
El patrón "pantalla de acceso con un password que se guarda para no pedirlo cada vez" (mencionado en `PROJECT.md:119`, "pantalla de acceso de la web") empuja naturalmente a `localStorage` porque es la forma más simple de persistir client-side. Pero eso convierte una clave pensada como secreto compartido servidor-servidor en un token expuesto en un contexto browser sin ninguna de las protecciones de un secreto real.

**How to avoid:**
Aceptar explícitamente que `WEB_API_KEY` en un browser es, en el mejor caso, una barrera de acceso débil (impide navegación casual, no un atacante dirigido) — no un secreto criptográfico. Dado que ADR-008 dice "la web funciona solo online" y este milestone es de solo lectura sin escritura, el radio de daño de una filtración es acotado (lectura de datos que de todos modos son de un solo artista, no PII sensible). Mitigaciones baratas y proporcionales al riesgo real (no sobre-ingeniería para v0 de un solo editor):
- Guardar en `sessionStorage` en vez de `localStorage` si se quiere reducir la ventana de exposición (se borra al cerrar la pestaña) — trade-off aceptable de UX vs. superficie de ataque.
- Nunca loguear el header `Authorization` en ningún lado (logs de Vercel Functions capturan headers por default en algunos setups — verificar).
- Si en un milestone futuro la web soporta escritura o múltiples usuarios, esto deja de ser aceptable y hay que pasar a un mecanismo real (sesión con cookie httpOnly + backend que valida, no un bearer token que el JS del cliente puede leer).

**Warning signs:**
Cualquier código que haga `localStorage.setItem('apiKey', ...)` o pase el key como query param (aparece en logs de acceso, en el historial del browser, en Referer headers) — un query param es estrictamente peor que un header, evitarlo siempre.

**Phase to address:**
Fase de implementación de `WEB_API_KEY` + pantalla de acceso (parte de BE-03 según `PROJECT.md:119`) — documentar la limitación como riesgo aceptado explícito en `PROJECT.md`/ADR, no dejarlo implícito.

---

### Pitfall 7: `VITE_`-prefixed env vars filtran secretos al bundle de producción

**What goes wrong:**
Vite solo expone al código cliente las variables de entorno prefijadas `VITE_` (todo lo demás queda server-side-only) — pero es un mecanismo de "opt-in por nombre", no una barrera técnica robusta: si alguien nombra la variable `VITE_SYNC_API_KEY` "para probar algo rápido" o copia-pega el patrón de `WEB_API_KEY` sin darse cuenta de que también expone `SYNC_API_KEY`, ese valor queda literal en el JS bundle servido a cualquier visitante — inspeccionable con "ver código fuente", sin necesitar ni siquiera DevTools avanzado.

**Why it happens:**
Es fácil, durante desarrollo rápido, definir todas las env vars necesarias con el prefijo `VITE_` "por las dudas" en el mismo `.env` que usa el backend, sin auditar cuál de esas variables es realmente para el cliente. `backend/.env.example:4` ya tiene `SYNC_API_KEY` como variable compartida con la app Flutter — si el `.env` de la nueva web copia ese archivo como base y alguien agrega `VITE_` al `SYNC_API_KEY` existente por costumbre de "prefijar todo lo que la web usa", el resultado es el secreto compartido con el celular expuesto en el bundle público.

**How to avoid:**
`SYNC_API_KEY` NUNCA debe tener una variable `VITE_*` equivalente — es exclusivamente server-to-server (celular ↔ backend). La web solo necesita `WEB_API_KEY` (que de todos modos, por Pitfall 6, ya es asumido como débil) del lado cliente. Regla operativa: antes de cada deploy, `grep -r "VITE_" web/` y confirmar que la lista coincide exactamente con lo esperado (solo `WEB_API_KEY` o su equivalente, nunca `SYNC_API_KEY`, `DATABASE_URL`, ni tokens de storage). Verificar además el `vercel.json` / configuración del proyecto para no compartir el mismo `.env` de Vercel entre el scope de `backend/` (Node runtime) y `web/` (Vite build) si Vercel los trata como un solo "Environment Variables" pool por proyecto — que es el comportamiento default y el riesgo real aquí.

**Warning signs:**
Buscar `SYNC_API_KEY` o `DATABASE_URL` en el output de `vite build` (carpeta `dist/`) antes de cada deploy — si aparece ahí, ya está filtrado y hay que rotar la clave inmediatamente (no solo borrar el bundle, porque ya pudo haber sido servido).

**Phase to address:**
Fase de storage/API keys (BE-03/BE-04) — agregar un check automatizado (grep en CI o script de pre-deploy) que falle el build si `dist/` contiene el valor de `SYNC_API_KEY`, no confiar en revisión manual.

---

### Pitfall 8: Vercel Preview usando la `DATABASE_URL` de Production — riesgo ya identificado pero no verificado

**What goes wrong:**
Este es el riesgo que el propio milestone marca como abierto (`PROJECT.md:122`, ADR-005): "Verificar que Preview no use la `DATABASE_URL` de Production". Si un PR de la web (o del backend) despliega a un Preview de Vercel y ese Preview termina apuntando a la misma `DATABASE_URL` que Production (porque la env var se configuró con scope "All Environments" en vez de solo "Production"), cualquier query de prueba en el Preview — incluyendo pulls masivos para debuggear paginación, o un push accidental si algún test de integración corre contra el Preview — toca los datos reales de producción, que son la única copia de los datos de campo del usuario (constraint más alto del proyecto, `PROJECT.md:64`).

**Why it happens:**
Vercel permite configurar env vars con scope granular (Production / Preview / Development) pero el default al agregar una variable desde el dashboard es aplicarla a los tres scopes a la vez si no se desmarca explícitamente — un error de un click, no de lógica de código.

**How to avoid:**
Verificación directa y barata: en el dashboard de Vercel (Settings → Environment Variables), confirmar que `DATABASE_URL` tiene un valor *distinto* para Preview (la Neon dev branch, como ya dice ADR-005) vs Production, y que el scope de cada valor está correctamente marcado. Una segunda verificación más robusta: en el handler o en un script de smoke test, loguear (sin exponer el valor completo) un hash corto de qué branch de Neon respondió, y confirmar en un deploy de Preview real que ese hash no coincide con el de Production. No asumir que "está bien" porque nunca se vio un problema — verificarlo activamente una vez, documentar el resultado.

**Warning signs:**
Cualquier dato de prueba/debug apareciendo en la web de producción o en el celular real después de probar algo en una Preview branch — señal tardía y costosa; mejor detectarlo antes con la verificación activa de arriba.

**Phase to address:**
Explícitamente marcado en el milestone (`PROJECT.md:122`) como algo a verificar en este mismo milestone — antes de dar por cerrado el trabajo de `backend/`, no como nice-to-have.

---

### Pitfall 9: `web/` en la raíz del repo ya existe y son artefactos de build de Flutter — colisión directa con la nueva web Vite+React

**What goes wrong:**
El directorio `web/` en la raíz del repo (confirmado: contiene `favicon.png`, `icons/`, `index.html`, `manifest.json` — el soporte de Flutter Web, generado por `flutter create`/`flutter build web`) ya existe y probablemente está trackeado en git (no aparece en `.gitignore`). ADR-010 asigna la propiedad de `web/` al workstream `web` para la nueva app Vite+React — si el scaffold de Vite (`npm create vite@latest`) se corre apuntando a ese mismo directorio, o si el `index.html`/`manifest.json` de Flutter Web quedan mezclados con los de Vite, el build de producción puede terminar sirviendo una mezcla de ambos (ej. el `index.html` de Flutter Web pisado a medias, o el manifest incorrecto siendo indexado por buscadores/PWA).

**Why it happens:**
El nombre `web/` ya estaba tomado por una feature de Flutter que probablemente nunca se usó en serio (esta es una app 100% Flutter mobile-first, per `PROJECT.md`) pero quedó del scaffold inicial del proyecto. Nadie limpió ese directorio porque hasta ahora no competía con nada.

**How to avoid:**
Antes de scaffoldear la nueva web, decidir explícitamente: (a) borrar el `web/` de Flutter por completo si Flutter Web nunca se va a usar (confirmar con el usuario — no asumir), y usarlo limpio para Vite; o (b) poner la nueva web en un directorio distinto (ej. `webapp/` o `admin/`) para no pisar nada, dejando `web/` intacto para Flutter. Dado que el proyecto es explícitamente mobile-only (Android/iOS, `PROJECT.md:68`) y no hay mención de Flutter Web en ningún requisito, la opción (a) es la más simple (ver ladder de ponytail: si Flutter Web no se usa, ese directorio es código muerto) — pero es una decisión que toca borrar archivos existentes y debe confirmarse explícitamente con el usuario antes de ejecutar, no asumirse en un plan de fase.

**Warning signs:**
`git status` mostrando conflictos o archivos duplicados (`index.html`, `manifest.json`) al iniciar el scaffold de Vite; un `vercel.json` de root ambiguo sobre qué `web/index.html` servir.

**Phase to address:**
Debe resolverse en la primera fase de este milestone (setup de la web), antes de cualquier código de UI — es un bloqueante de scaffold, no algo que se pueda posponer.

---

### Pitfall 10: Rewrites de un solo `vercel.json` para SPA + functions pisan las rutas de `/sync/*`

**What goes wrong:**
`backend/vercel.json:2-4` hoy tiene un único rewrite: `/sync/:path*` → `/api/sync/:path*`. Cuando se agregue el SPA de React al mismo proyecto Vercel, el patrón típico para servir una SPA es un catch-all rewrite `"source": "/(.*)", "destination": "/index.html"` para que el client-side routing de React Router funcione en refresh/deep-link. Si ese catch-all se agrega *antes* del rewrite de `/sync/*` en el array de `rewrites` (Vercel evalúa en orden, primer match gana), **todas** las requests a `/sync/pull`, `/sync/push`, `/sync/state` — incluyendo las del celular en producción — devuelven el `index.html` de la SPA en vez de llegar a las functions. Esto rompe el backend que ya está en producción sirviendo al celular real, no solo la web nueva.

**Why it happens:**
Es fácil concatenar reglas nuevas al final o al principio de la lista de `rewrites` sin pensar en el orden de evaluación, especialmente si se genera el `vercel.json` combinado desde un ejemplo de "SPA en Vercel" copiado de la documentación, que típicamente pone el catch-all como única regla.

**How to avoid:**
El catch-all de la SPA va **después** de las reglas específicas de `/sync/*` (y de cualquier `/api/*` que se agregue para la web, si la web necesita endpoints propios de backend). Regla operativa: escribir un test/smoke-check post-deploy que haga `curl` real a `/sync/state` en producción y confirme que responde JSON (no HTML) antes de considerar cerrado cualquier deploy que toque `vercel.json`. Considerar también si `backend/` y `web/` deben vivir bajo un único `vercel.json` de raíz de repo (en vez de que `backend/vercel.json` sea el único) — si Vercel usa `backend/` como Root Directory del proyecto hoy, agregar la web puede requerir mover la config a la raíz del repo, lo cual es un cambio de "Root Directory" en la config del proyecto Vercel, no solo un archivo — verificar esto explícitamente contra la configuración real del proyecto en el dashboard antes de asumir cuál `vercel.json` manda.

**Warning signs:**
El celular deja de sincronizar en producción justo después de un deploy que agregó la web — sin ningún cambio en `backend/api/`. Sería un incidente en producción con datos reales de por medio (aunque de solo lectura del lado servidor, un `/sync/push` roto sí bloquea al celular).

**Phase to address:**
Fase de deploy de la SPA en el mismo proyecto Vercel — antes de mergear a `main` (que dispara deploy de producción, per ADR-005), validar con un deploy a Preview primero y correr el smoke-check de `/sync/state` ahí.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Cursor de pull con margen fijo de tiempo (Pitfall 1, opción 1) en vez de snapshot transaccional | Simple, cero cambios de schema | Puede perder filas en una ventana de concurrencia real si el margen es muy corto, o agregar latencia perceptible de sync si es muy largo | Aceptable para v0 (un editor, luego web+celular de baja frecuencia); revisar si en el futuro hay múltiples escritores concurrentes de verdad |
| `WEB_API_KEY` compartida entre todos los accesos a la web (sin usuarios individuales) | No hay que construir auth de usuarios para una web de un solo editor | No hay auditoría de quién hizo qué, ni forma de revocar acceso a una sola persona sin romper a todos | Aceptable mientras la web sea de solo lectura y de un solo operador (este milestone); nunca aceptable si la web soporta escritura multi-usuario |
| Servir SPA + backend del mismo proyecto Vercel con un solo `vercel.json` | Un solo deploy, una sola configuración de dominio | Los rewrites de ambos compiten por orden de precedencia (Pitfall 10); cualquier cambio futuro a rutas de la SPA es un riesgo latente para `/sync/*` en producción | Aceptable para v0 dado el research ya hecho (mismo proyecto Vercel, `PROJECT.md:120`); si el volumen de tráfico de la web crece mucho, separar en dos proyectos Vercel elimina el riesgo de raíz |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|-------------------|
| Neon (`@neondatabase/serverless`) | Comparar/loguear `change_seq` como `number` de JS en vez de `string` | Castear a `::text` en SQL siempre que el valor viaje al cliente, replicando `state.js:5` |
| Vercel Functions | Asumir timeout de 60s siempre disponible sin declarar `maxDuration` | Confirmar el tier (Hobby: 30s default con Fluid Compute, 10s sin — MEDIUM confidence, verificar contra el proyecto real) y declarar `maxDuration` explícito si el pull puede acercarse al límite |
| Vercel env vars | Configurar `DATABASE_URL`/secretos con scope "All Environments" por default del dashboard | Marcar explícitamente Production vs Preview vs Development por variable, y verificar (Pitfall 8) |
| Vite build | Prefijar cualquier variable con `VITE_` sin auditar qué se expone al bundle | Grep de `dist/` buscando secretos server-only antes de cada deploy (Pitfall 7) |
| Storage (Vercel Blob candidato) | Subida directa cliente→storage sin URL firmada de un solo uso ni validación server-side de tipo/tamaño | Generar URL de subida autorizada server-side con expiración corta; validar `checksum`/tamaño en el callback o al leer, no confiar en el cliente |
| Leaflet + OSM tiles | Usar `tile.openstreetmap.org` directamente para tiles en producción sin evaluar el Tile Usage Policy | Confirmar la política de uso (atribución visible + caching, sin prefetch/descarga masiva — MEDIUM confidence vía docs oficiales de OSMF) antes de decidir si alcanza el tile server público o si hace falta un proveedor con SLA (ej. MapTiler/Maptiler free tier, Stadia Maps) dado que es un producto en producción, no solo un prototipo |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Pull sin `LIMIT` server-side | Timeout de Vercel Function (504) solo contra el backlog real de producción | `LIMIT` fijo conservador (200-500 filas) siempre en servidor, loop de paginación en el cliente | Ya con el backlog actual (1186 filas históricas mencionadas en `PROJECT.md:22`), no hace falta escala futura para que aparezca |
| Renderizar cientos de triggers como `L.circle` individuales en Leaflet sin agrupar | Mapa se pone lento/laggy al hacer pan/zoom con muchos recorridos cargados a la vez | Usar `L.circleMarker` (más liviano que `L.circle`, que dibuja en unidades geográficas reales) para radios visuales aproximados, o clustering (`Leaflet.markercluster`) si el conteo total supera unos cientos | Con pocas decenas de triggers por obra y pocas obras (proyecto de un solo artista, escala Lago Puelo) probablemente no se llega al punto de quiebre en este milestone — pero si el mapa general (`PROJECT.md:120`) carga TODOS los recorridos/triggers a la vez sin filtro, sí puede notarse |
| bbox con `cover_min_lat`/`cover_max_lat`/etc. NULL para obras sin paths todavía | El mapa general omite silenciosamente obras nuevas (sin cover calculado) sin ningún indicio visual de que existen | Filtrar explícitamente en la UI ("obra sin ubicación todavía") en vez de dejar que desaparezcan del mapa sin explicación — el índice `obras_cover_bbox_idx` (`schema.sql:127`) no ayuda si la query de mapa no maneja el caso NULL a propósito | Aparece apenas exista una obra creada sin paths/triggers aún (flujo normal de "creo la obra, grabo después") |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Confiar en `WEB_API_KEY` como control de acceso fuerte | Cualquiera con el token (filtrado por XSS, screenshot, o simplemente compartido) lee todos los datos de producción | Aceptar el riesgo explícitamente como "barrera débil" para v0 solo-lectura (Pitfall 6); no usar el mismo patrón si la web gana escritura o multi-usuario |
| Blob storage público por default para audio | Cualquiera con la URL (que puede filtrarse en logs, Referer, o ser adivinable si la key no es aleatoria) descarga el audio original sin autenticación | Usar blobs privados con URL de descarga firmada y expiración corta, generada server-side tras validar `WEB_API_KEY`/`SYNC_API_KEY`; nunca depender de que la URL sea "difícil de adivinar" como única protección |
| Checksums calculados con algoritmos distintos en Dart (celular), browser (web) y el proveedor de storage | Un archivo "corrupto" según un chequeo puede pasar el checksum de otro cálculo, dando falsa confianza de integridad | Definir un único algoritmo (ej. SHA-256) y una única codificación (hex vs base64) en el ERS del protocolo de sync, verificado contra vectores compartidos igual que ya hace `cover.js:1` ("El vector compartido lo vigila") para la fórmula de cover — mismo patrón, aplicado a checksums |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-------------------|
| Mapa general sin feedback de carga durante paginación de pull | El usuario ve un mapa vacío o incompleto y no sabe si terminó de cargar o si hay un error | Mostrar progreso explícito ("cargando recorridos... X de Y") mientras el loop de paginación de pull corre |
| Audios sin reproducir en la web porque el celular todavía no implementó la subida (2.2 de `app`) | El usuario ve una obra "completa" en la lista pero el audio no suena, sin explicación | Estado visual explícito de "audio pendiente de subida" cuando `storage_key` es NULL — ya está contemplado como riesgo conocido en `PROJECT.md:124`, asegurar que se refleje en la UI y no solo en el modelo de datos |

## "Looks Done But Isn't" Checklist

- [ ] **`GET /sync/pull` implementado:** ¿pagina de verdad con `LIMIT` server-side, o solo funciona porque el dataset de dev es chico? Verificar contra el backlog real (1186+ filas).
- [ ] **Paginación de pull probada:** ¿se probó con escrituras concurrentes reales durante la lectura (Pitfall 1), o solo con datos estáticos?
- [ ] **`vercel.json` combinado SPA+functions:** ¿se corrió un smoke test de `/sync/state` contra un deploy de Preview real después de agregar el catch-all de la SPA (Pitfall 10)?
- [ ] **Env vars de Vercel:** ¿se verificó activamente (no asumido) que Preview usa una `DATABASE_URL` distinta a Production (Pitfall 8, ya marcado como pendiente en `PROJECT.md:122`)?
- [ ] **Bundle de la web:** ¿se corrió un grep de `dist/` buscando `SYNC_API_KEY`/`DATABASE_URL` antes del primer deploy a producción (Pitfall 7)?
- [ ] **Directorio `web/`:** ¿se resolvió la colisión con los artefactos de Flutter Web existentes antes de scaffoldear Vite (Pitfall 9), o se está construyendo encima sin darse cuenta?
- [ ] **Storage de audio:** ¿las URLs de subida/descarga están firmadas con expiración, o son URLs públicas permanentes?

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|-----------------|
| Pull "salta" filas por concurrencia (Pitfall 1) | MEDIUM | Forzar un pull completo desde cursor=0 en el cliente afectado (el servidor sigue teniendo el dato completo, no hay pérdida real — es un problema de sincronización, no de integridad de datos) |
| Secreto filtrado en bundle de Vite (Pitfall 7) | HIGH | Rotar la clave filtrada inmediatamente (`SYNC_API_KEY` nueva, recompilar la app Flutter con el nuevo valor vía `--dart-define`, redeploy del backend con la nueva env var) — el bundle viejo puede seguir cacheado en CDNs/browsers de terceros, así que la clave vieja debe considerarse comprometida para siempre |
| Preview apuntó a `DATABASE_URL` de producción y corrió writes de prueba (Pitfall 8) | HIGH | Restaurar desde un point-in-time recovery de Neon (branching de Neon permite crear una branch desde un timestamp anterior) — verificar el punto exacto antes del incidente; el celular sigue teniendo la copia local como respaldo final si todo lo demás falla (constraint de integridad de datos del proyecto) |
| `vercel.json` rompe `/sync/*` en producción tras agregar la SPA (Pitfall 10) | LOW | Revert inmediato del `vercel.json` (o reordenar el rewrite de `/sync/*` antes del catch-all) y redeploy — el celular reintenta automáticamente vía el backoff ya existente (`RunSyncUseCase`), así que un downtime corto de minutos no pierde datos, solo los demora |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|--------------|
| Gaps de paginación por concurrencia (P1) | Fase BE-01 (`GET /sync/pull`) | Test de integración con escrituras concurrentes durante una lectura paginada |
| `change_seq` BIGINT como number (P2) | Fase BE-01 | Test con `change_seq` forzado por encima de `Number.MAX_SAFE_INTEGER` (mock o secuencia adelantada en dev) confirmando que sigue siendo string end-to-end |
| Orden cruzado entre tablas (P3) | Fase BE-01 | Test con cambios simultáneos en 3+ tablas distintas, verificar orden del batch resultante |
| Timeout/cold start en pull grande (P4) | Fase BE-01 | Test de carga contra el backlog real (o un fixture del mismo orden de magnitud) midiendo tiempo total de una página completa |
| Asimetría push/pull rompe contrato del celular (P5) | Fase BE-01 (diseño) + Fase 3 de `app` (verificación real) | El celular debe consumir el pull real contra el backend de staging antes de dar la Fase 3 por cerrada |
| `WEB_API_KEY` débil en browser (P6) | Fase BE-03 | Documentado como riesgo aceptado explícito en PROJECT.md/ADR, no un bug a "arreglar" en v0 |
| Secreto filtrado vía `VITE_*` (P7) | Fase BE-03/BE-04 (setup de env vars) | Check automatizado de `dist/` sin secretos server-only antes de cada deploy |
| Preview con `DATABASE_URL` de Production (P8) | Ya marcado en el milestone (`PROJECT.md:122`) | Verificación activa en el dashboard de Vercel + smoke test con hash de branch, antes de cerrar el milestone |
| Colisión de `web/` con Flutter Web (P9) | Primera fase del milestone (setup de la web) | Confirmación explícita del usuario sobre destino de `web/` antes de scaffoldear Vite |
| Rewrites de `vercel.json` pisan `/sync/*` (P10) | Fase de deploy de la SPA | Smoke test de `/sync/state` en Preview antes de merge a `main` |

## Sources

- Código del repo (fuente primaria, líneas citadas inline): `backend/schema.sql`, `backend/api/_lib/{auth,db,ids,cover,spec,outbox}.js`, `backend/api/sync/{push,state}.js`, `backend/vercel.json`, `backend/.env.example`, `lib/data/sync/sync_api.dart`, `.planning/PROJECT.md`
- https://vercel.com/docs/functions/limitations — timeouts de Vercel Functions por plan (MEDIUM confidence, agregado de varias fuentes 2026, no fetch directo de la página oficial)
- https://vercel.com/changelog/vercel-functions-for-hobby-can-now-run-up-to-60-seconds — techo de 60s en Hobby
- https://vercel.com/docs/vercel-blob/usage-and-pricing — límites de free tier de Vercel Blob (1GB storage, 10GB transfer/mes) — MEDIUM confidence
- https://operations.osmfoundation.org/policies/tiles/ — Tile Usage Policy de OSMF (atribución + caching, sin prefetch/offline) — MEDIUM confidence
- https://neon.com/docs/serverless/serverless-driver y https://neon.com/docs/connect/connection-latency — comportamiento del driver HTTP y cold starts de Neon (~300-800ms) — MEDIUM confidence

---
*Pitfalls research for: web workstream v1.0 (pull, WEB_API_KEY, storage, Vite+React+Leaflet)*
*Researched: 2026-09-23*
