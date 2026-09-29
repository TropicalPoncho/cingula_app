#!/usr/bin/env bash
# check-preview-db.sh — INFRA-02: verifica por HOST (nunca por valor completo) que Preview y
# Development de Vercel no resuelven la DATABASE_URL de Production.
#
# Uso: bash web/scripts/check-preview-db.sh [rama-git]
#   Corre desde un directorio ya linkeado con `npx vercel@latest link` (raíz del repo).
#   [rama-git] es la rama que se usa para pedir el env de Preview (default: rama git actual).
#
# Qué compara: el host de la línea DATABASE_URL= en el .env que devuelve
# `vercel env pull --environment=<production|preview|development>` para cada entorno.
# Por qué solo host: el host (ep-...) identifica la rama de Neon sin exponer usuario/clave/db.
# Nunca imprime la connection string completa ni hace `set -x` (evita filtrar secretos a logs de CI).
set -euo pipefail

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

npx vercel@latest env pull "$T/production.env" --environment=production --yes >/dev/null
npx vercel@latest env pull "$T/preview.env" --environment=preview --git-branch="$BRANCH" --yes >/dev/null
npx vercel@latest env pull "$T/development.env" --environment=development --yes >/dev/null

host() {
  local file="$1"
  [ -f "$file" ] || { echo ""; return; }
  grep -m1 '^DATABASE_URL=' "$file" 2>/dev/null \
    | sed -E 's#^DATABASE_URL="?[^@]*@([^/:?"]+).*#\1#' \
    || echo ""
}

PROD_HOST=$(host "$T/production.env")
PREVIEW_HOST=$(host "$T/preview.env")
DEV_HOST=$(host "$T/development.env")

fmt() { [ -n "$1" ] && echo "$1" || echo "VACÍO"; }

echo "production: $(fmt "$PROD_HOST")"
echo "preview(${BRANCH}): $(fmt "$PREVIEW_HOST")"
echo "development: $(fmt "$DEV_HOST")"

EMPTY_MSG="vacío: la variable falta en ese entorno o está marcada Sensitive (no se puede bajar) -> revisar 'vercel env ls'"

if [ -z "$PROD_HOST" ]; then
  echo "INFRA-02 FAIL: production $EMPTY_MSG"
  exit 1
fi

if [ -z "$PREVIEW_HOST" ]; then
  echo "INFRA-02 FAIL: preview $EMPTY_MSG"
  exit 1
fi

if [ "$PREVIEW_HOST" = "$PROD_HOST" ]; then
  echo "INFRA-02 FAIL: preview usa el mismo host que production"
  exit 1
fi

if [ -n "$DEV_HOST" ] && [ "$DEV_HOST" = "$PROD_HOST" ]; then
  echo "INFRA-02 FAIL: development usa el mismo host que production"
  exit 1
fi

echo "INFRA-02 OK: preview y development no usan el host de producción"
exit 0
