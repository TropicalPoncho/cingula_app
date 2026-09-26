#!/usr/bin/env bash
# Uso: bash backend/scripts/smoke-preview.sh <base-url>
# Chequea GET /sync/state: sin key debe dar 401 JSON (prueba el ruteo, ningún secreto).
# SMOKE_API_KEY (opcional): WEB_API_KEY/SYNC_API_KEY -> chequea 200 con serverCursor.
# VERCEL_BYPASS (opcional): secreto de Protection Bypass -> header x-vercel-protection-bypass.
# Solo GET, nunca POST: es seguro correrlo contra producción.
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "uso: smoke-preview.sh <base-url>" >&2
  exit 2
fi

base="${1%/}"

body="$(mktemp)"
trap 'rm -f "$body"' EXIT

hdr=()
if [ -n "${VERCEL_BYPASS:-}" ]; then
  hdr+=(-H "x-vercel-protection-bypass: ${VERCEL_BYPASS}")
fi

fail() {
  echo "SMOKE FAIL: $1" >&2
  exit 1
}

# Chequeo 1: ruteo, sin Authorization.
result="$(curl -sS -o "$body" -w '%{http_code} %{content_type}' "${hdr[@]+"${hdr[@]}"}" "$base/sync/state" || echo "000 ")"
status="${result%% *}"
ctype="${result#* }"

if [ "$status" != "401" ] || [[ "$ctype" != *application/json* ]]; then
  if [[ "$ctype" == *text/html* ]]; then
    fail "recibí HTML: la request no llegó a la función (rewrite/Root Directory mal, SPA fallback, o Deployment Protection -> setear VERCEL_BYPASS) (status=$status content-type=$ctype)"
  fi
  fail "chequeo 1 (ruteo): esperaba 401 application/json, recibí status=$status content-type=$ctype"
fi

grep -q "invalid or missing API key" "$body" || fail "chequeo 1 (ruteo): body no contiene 'invalid or missing API key' (status=$status content-type=$ctype)"

# Chequeo 2: con key, solo si SMOKE_API_KEY no está vacía.
if [ -n "${SMOKE_API_KEY:-}" ]; then
  result="$(curl -sS -o "$body" -w '%{http_code} %{content_type}' "${hdr[@]+"${hdr[@]}"}" -H "Authorization: Bearer ${SMOKE_API_KEY}" "$base/sync/state" || echo "000 ")"
  status="${result%% *}"
  ctype="${result#* }"

  if [ "$status" != "200" ] || [[ "$ctype" != *application/json* ]]; then
    fail "chequeo 2 (con key): esperaba 200 application/json, recibí status=$status content-type=$ctype"
  fi
  grep -q '"serverCursor"' "$body" || fail "chequeo 2 (con key): body no contiene serverCursor (status=$status content-type=$ctype)"
  echo "chequeo 2 OK, body: $(cat "$body")"
else
  echo "chequeo 2 salteado (SMOKE_API_KEY vacía): solo se verificó el ruteo"
fi

echo "SMOKE OK $base"
