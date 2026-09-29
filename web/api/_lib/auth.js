import { timingSafeEqual } from 'node:crypto';

export const AUTH_ERROR = 'invalid or missing API key';
export const READ_ONLY_ERROR = 'API key is read-only';

// D-09: 'web' (WEB_API_KEY) es de solo lectura en este milestone; vive en el navegador.
const KEYS = [['sync', 'SYNC_API_KEY'], ['web', 'WEB_API_KEY']];

/**
 * Devuelve 'sync' | 'web' según qué variable de entorno coincide con el bearer token, o null.
 * Cada variable se compara por separado con timingSafeEqual; una variable ausente o vacía no da
 * acceso por esa clave (config faltante = cerrado, nunca abierto). Authorization: Bearer se
 * mantiene de la Fase 2 (prefijo opcional, case-insensitive).
 */
export function apiKeyRole(request) {
  const header = request?.headers?.authorization;
  const provided = Buffer.from(typeof header === 'string' ? header.replace(/^Bearer\s+/i, '') : '');
  for (const [role, env] of KEYS) {
    const expected = Buffer.from(process.env[env] ?? '');
    if (expected.length === 0) continue;
    // timingSafeEqual exige mismo largo; el chequeo de largo filtra antes (no es secreto útil).
    if (provided.length === expected.length && timingSafeEqual(provided, expected)) return role;
  }
  return null;
}
