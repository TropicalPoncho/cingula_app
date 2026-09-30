# Prompt para Claude Design — Phase 12: Web de lectura

> Guardado como referencia canónica. Pegar tal cual (o editar la sección de restricciones de diseño)
> en Claude Design (claude.ai, research preview de Anthropic Labs). El resultado (link o export) se
> vuelve una referencia para research/planning una vez que exista — actualizar este archivo o
> `12-CONTEXT.md` con el link cuando lo tengas.

```
Estoy diseñando la Fase 12 de "Cíngula" — una web de solo lectura para gestionar recorridos sonoros
geolocalizados (arte sonoro en espacios verdes de Lago Puelo, Comarca Andina). Es una herramienta
para un solo artista/editor, no un producto público — priorizá claridad y densidad de información
sobre "wow visual".

Contexto del dominio:
- Un RECORRIDO agrupa varias OBRAS (puede haber obras de distintos artistas); los créditos del
  recorrido son la unión de los artistas de sus obras.
- Una OBRA tiene: visibilidad, recorrido al que pertenece, artistas, un área de cobertura geográfica,
  y uno o más PATHS.
- Un PATH es un camino grabado en el territorio: tiene un `kind`, un audio asociado, la grabación de
  origen, un `tolerance_meters`, y una lista ordenada de TRIGGERS (posición, nombre, descripción,
  radio en metros, offset en milisegundos) — cada trigger es un círculo geolocalizado que dispara
  un audio cuando el celular entra en su radio.
- Un ARTISTA tiene nombre y aparece en una o más obras.
- Un AUDIO tiene título, descripción y `kind`, y vive dentro del path que lo usa (no se reutiliza
  entre paths en la práctica).
- Todo se lee vía pull de un backend Postgres — nunca se escribe desde esta web todavía.
- Ninguna vista debe mostrar filas borradas (soft-delete).

Pantallas a diseñar (solo lectura, sin edición):
1. Pantalla de acceso: ingresar una API key una sola vez por sesión (sin registro, sin "recordarme").
2. Mapa general (pantalla principal / home): todas las obras del servidor sobre un mapa (OSM/Leaflet),
   con capas activables (checkboxes) para cobertura de obra, paths, y triggers (círculos con radio
   real en metros) — todas prendidas por defecto. Zoom automático para encuadrar todas las obras.
   Selector fijo arriba del mapa para filtrar por recorrido (al elegir uno, el mapa muestra solo sus
   obras, y se puede ver la info del recorrido — créditos, lista de obras — en el mismo panel lateral
   descrito abajo).
3. Panel lateral IZQUIERDO, plegable/expandible (patrón clave de esta web): al tocar una obra, un
   path, un trigger, o seleccionar un recorrido, se abre un panel angosto a la izquierda con la info
   básica. Un botón permite expandirlo a pantalla completa (el mapa se achica proporcionalmente, NO
   desaparece ni navega a otra URL) mostrando el detalle COMPLETO de ese elemento. Mismo componente
   reusado para los 4 tipos (obra, path, trigger, recorrido).
4. Página propia (con su URL) de Artistas: listado + detalle, con las obras en las que aparece cada
   artista.
5. Página propia de Obras: listado filtrable por recorrido y visibilidad + detalle (visibilidad,
   recorrido, artistas, cobertura, paths) — el mismo contenido que se ve en el panel del mapa, pero
   accesible también por esta vía directa.
6. Dentro del detalle de un path (ya sea en el panel del mapa o llegando desde el detalle de obra):
   metadata, audio asociado (mostrado inline, sin listado propio de audios), mapa con sus triggers,
   y lista de triggers ordenada por posición. Navegar de obra → path mantiene un camino claro de
   vuelta (breadcrumb o botón "volver a la obra").
7. Indicador de "estado de sync" fijo en el header, visible en cualquier pantalla: último pull,
   cursor, y errores explícitos si los hay (sin ocultar fallas silenciosamente).

Restricciones de diseño:
- Es una app que solo funciona online (sin soporte offline).
- Tono: herramienta de trabajo para un artista/gestor cultural, no una app consumer. Clara, legible,
  sin relleno decorativo.
- Sin preferencia de colores/tipografía todavía — proponé algo apropiado para el dominio (arte
  sonoro, naturaleza, trabajo de campo), no necesariamente literal (nada de hojas ni íconos de
  árbol por default).

Dame prototipos interactivos navegables para estas pantallas, empezando por el mapa general con el
panel lateral (obra abierta) y su versión expandida a pantalla completa — son las más centrales y
las que más definen el resto.
```
