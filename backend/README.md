# cingula-sync-backend

Vercel Functions (`/sync/push`, `/sync/state`, `/sync/pull`) sobre Neon Postgres. Implementa el
contrato HTTP documentado en `.planning/workstreams/app/phases/02-backend-real-push-sync/02-02-PLAN.md`.

## Setup

```bash
cd backend
npm install
cp .env.example .env   # completar DATABASE_URL y SYNC_API_KEY
```

`WEB_API_KEY` (opcional): clave de solo lectura para la web (pull/state; el push la rechaza con
403). Contrato de pull: Notion, ERS · Backend — protocolo de sync.

## Test

```bash
npm test
```

Los tests de integración (`api/sync/push.test.js`) requieren `DATABASE_URL` apuntando
a una branch de Neon; sin esa env var se saltean (verde igual).

## Dev local

```bash
vercel dev
```

Necesita `vercel link` primero (ver `user_setup` en el plan).
