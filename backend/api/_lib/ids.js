import { createHash } from 'node:crypto';

// Namespace fijo de Cingula: NUNCA cambiar (identidad de obras/portales, D-24).
export const CINGULA_NAMESPACE = '6f1a6c3e-9b54-4b2a-8f3d-1d0c9a7e5b21';

export function uuidV5(namespace, name) {
  const ns = Buffer.from(namespace.replace(/-/g, ''), 'hex');
  const bytes = createHash('sha1')
    .update(Buffer.concat([ns, Buffer.from(name, 'utf8')]))
    .digest()
    .subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const h = bytes.toString('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

export const obraUuidForPath = (pathUuid) => uuidV5(CINGULA_NAMESPACE, 'obra:' + pathUuid);
export const portalUuidForTrigger = (triggerUuid) => uuidV5(CINGULA_NAMESPACE, 'portal:' + triggerUuid);
