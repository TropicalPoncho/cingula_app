// Formatos de la UI (es-AR). Separador de miles: espacio.
export const plural = (n, uno, varios) => `${n} ${n === 1 ? uno : varios}`;

// Tiempo relativo: `12 s`, `3 min`, `2 h`.
export function rel(ms) {
  const s = Math.max(0, Math.floor(ms / 1000));
  if (s < 60) return `${s} s`;
  if (s < 3600) return `${Math.floor(s / 60)} min`;
  return `${Math.floor(s / 3600)} h`;
}
