import { neon } from '@neondatabase/serverless';

let _sql;

export function getSql() {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error('DATABASE_URL is not set');
  _sql ??= neon(url);
  return _sql;
}
