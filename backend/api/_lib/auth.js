import { timingSafeEqual } from 'node:crypto';

export const AUTH_ERROR = 'invalid or missing API key';

/**
 * Valida el bearer token del request. Devuelve null si es válido, o el mensaje de error.
 * Se elige Authorization: Bearer sobre X-API-Key por ser la convención REST más común;
 * el esfuerzo de implementación es idéntico (D-02 / discreción de Claude en CONTEXT.md).
 */
export function requireApiKey(request) {
  const expected = process.env.SYNC_API_KEY ?? '';
  if (expected.length === 0) return AUTH_ERROR; // config faltante = cerrado, nunca abierto

  const header = request?.headers?.authorization;
  const provided = typeof header === 'string' ? header.replace(/^Bearer\s+/i, '') : '';

  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  // timingSafeEqual exige mismo largo; el chequeo de largo filtra antes (no es secreto útil).
  if (a.length !== b.length || !timingSafeEqual(a, b)) return AUTH_ERROR;
  return null;
}
