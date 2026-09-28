// ponytail: Vercel solo descubre funciones en <Root Directory>/api; esto re-exporta el handler real de backend/ (ADR-005, backend/ no se mueve). Techo: una función nueva en backend/api/sync necesita su shim acá.
export { default } from '../../../backend/api/sync/state.js';
