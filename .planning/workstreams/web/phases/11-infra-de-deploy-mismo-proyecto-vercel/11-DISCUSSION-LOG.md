# Phase 11: Infra de deploy (mismo proyecto Vercel) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-26
**Phase:** 11-infra-de-deploy-mismo-proyecto-vercel
**Areas discussed:** Riesgo del cutover a producción, Rama Neon dev para Preview, Preferencia sobre mover archivos, Alcance de la limpieza de web/

---

## Áreas presentadas

| Área | Descripción | Selección |
|------|-------------|-----------|
| Riesgo del cutover a producción | ¿Aplicar el cambio apenas pase el smoke test, o esperar una ventana sin grabación de campo activa? ¿Plan de rollback explícito? | No preference |
| Rama Neon dev para Preview | ¿Ya existe una rama Neon dev, o esta fase la crea? | No preference |
| Preferencia sobre mover archivos | El spike decide el mecanismo de ruteo; ¿preferencia previa no técnica sobre mover `backend/api/`? | No preference |
| Alcance de la limpieza de web/ | ¿Borrado total de los restos de Flutter web, o conservar el favicon como placeholder? | No preference |

**Respuesta del usuario:** "No preference" para las 4 áreas — delegó a criterio de Claude.

**Confirmación:** se le preguntó si quería revisar alguna área puntual antes de cerrar el contexto; eligió "Seguir a research/planning (recomendado)".

---

## Claude's Discretion

Las 4 áreas quedaron a discreción de Claude, con defaults registrados en CONTEXT.md:
- Cutover: aplicar apenas el smoke test (ya exigido por ROADMAP) pase; sin ventana especial ni rollback formal adicional — el diseño ya tolera conectividad intermitente.
- Rama Neon dev: verificar si ya existe antes de crear una nueva.
- Mecanismo de ruteo: decide el spike técnico; preferir mover menos archivos si hay empate.
- Limpieza de `web/`: borrado total, sin conservar nada de Flutter.

## Deferred Ideas

None — la discusión se mantuvo dentro del alcance de la fase.
