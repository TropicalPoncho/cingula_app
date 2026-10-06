#!/usr/bin/env bash
# Uso: bash web/scripts/smoke-preview.sh <base-url>
# Gate de ruteo de la entrega SPA + funciones en un solo proyecto Vercel (Fase 12, INFRA-01).
# Chequeos (todos GET, sin POST: seguro correrlo contra producción):
#   1. GET /sync/state sin key -> 401 JSON (el rewrite /sync llega a la función, no a la SPA).
#   2. (opcional, SMOKE_API_KEY) con key -> 200 con serverCursor.
#   3. /api/sync/state y /api/sync/pull -> 401 JSON; /api/sync/push por GET -> 405 JSON
#      (las 3 funciones existen en el deploy).
#   4. /obras/smoke-deep-link -> 200 text/html con id="root" (fallback de la SPA).
#   5. /assets/no-existe-smoke.js -> no 200 y no text/html (el fallback no se traga assets).
#   6. Headers de /: CSP con frame-ancestors 'none', Referrer-Policy strict-origin-when-cross-origin,
#      X-Content-Type-Options nosniff.
# SMOKE_API_KEY (opcional): WEB_API_KEY/SYNC_API_KEY.
# VERCEL_BYPASS (opcional): secreto de Protection Bypass -> header x-vercel-protection-bypass.
#   Se pasa por el entorno de la sesión; nunca se escribe en un archivo.
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "uso: smoke-preview.sh <base-url>" >&2
  exit 2
fi

base="${1%/}"

body="$(mktemp)"
heads="$(mktemp)"
trap 'rm -f "$body" "$heads"' EXIT

hdr=()
if [ -n "${VERCEL_BYPASS:-}" ]; then
  hdr+=(-H "x-vercel-protection-bypass: ${VERCEL_BYPASS}")
fi

fail() {
  echo "SMOKE FAIL: $1" >&2
  exit 1
}

# get <path> [curl args...] -> deja status/ctype en variables globales y el body en $body.
get() {
  local path="$1"
  shift
  local result
  result="$(curl -sS -o "$body" -w '%{http_code} %{content_type}' "${hdr[@]+"${hdr[@]}"}" "$@" "$base$path" || echo "000 ")"
  status="${result%% *}"
  ctype="${result#* }"
}

# expect_json <path> <status> <chequeo>
expect_json() {
  get "$1"
  if [ "$status" != "$2" ] || [[ "$ctype" != *application/json* ]]; then
    if [[ "$ctype" == *text/html* ]]; then
      fail "$3: recibí HTML: la request no llegó a la función (rewrite/Root Directory mal, SPA fallback, o Deployment Protection -> setear VERCEL_BYPASS) (path=$1 status=$status content-type=$ctype)"
    fi
    fail "$3: esperaba $2 application/json en $1, recibí status=$status content-type=$ctype"
  fi
}

# Chequeo 1: ruteo, sin Authorization.
expect_json /sync/state 401 "chequeo 1 (ruteo)"
grep -q "invalid or missing API key" "$body" || fail "chequeo 1 (ruteo): body no contiene 'invalid or missing API key' (status=$status content-type=$ctype)"

# Chequeo 2: con key, solo si SMOKE_API_KEY no está vacía.
if [ -n "${SMOKE_API_KEY:-}" ]; then
  get /sync/state -H "Authorization: Bearer ${SMOKE_API_KEY}"
  if [ "$status" != "200" ] || [[ "$ctype" != *application/json* ]]; then
    fail "chequeo 2 (con key): esperaba 200 application/json, recibí status=$status content-type=$ctype"
  fi
  grep -q '"serverCursor"' "$body" || fail "chequeo 2 (con key): body no contiene serverCursor (status=$status content-type=$ctype)"
  echo "chequeo 2 OK, body: $(cat "$body")"
else
  echo "chequeo 2 salteado (SMOKE_API_KEY vacía): solo se verificó el ruteo"
fi

# Chequeo 3: las 3 funciones existen en el deploy (Pitfall 2).
expect_json /api/sync/state 401 "chequeo 3 (funciones)"
expect_json /api/sync/pull 401 "chequeo 3 (funciones)"
expect_json /api/sync/push 405 "chequeo 3 (funciones)"

# Chequeo 4: deep link de la SPA.
get /obras/smoke-deep-link
if [ "$status" != "200" ] || [[ "$ctype" != *text/html* ]]; then
  fail "chequeo 4 (deep link): esperaba 200 text/html en /obras/smoke-deep-link, recibí status=$status content-type=$ctype"
fi
grep -q 'id="root"' "$body" || fail "chequeo 4 (deep link): el HTML no contiene id=\"root\" (no es el index.html de la SPA)"

# Chequeo 5: un asset inexistente no devuelve el HTML de la SPA.
get /assets/no-existe-smoke.js
if [ "$status" = "200" ] || [[ "$ctype" == *text/html* ]]; then
  fail "chequeo 5 (assets): /assets/no-existe-smoke.js devolvió status=$status content-type=$ctype (el fallback se traga los assets)"
fi

# Chequeo 6: headers de seguridad en /.
curl -sS -o /dev/null -D "$heads" "${hdr[@]+"${hdr[@]}"}" "$base/" || fail "chequeo 6 (headers): no pude pedir $base/"
header_has() { tr -d '\r' < "$heads" | grep -iq "^$1:.*$2"; }
header_has content-security-policy "frame-ancestors 'none'" || fail "chequeo 6 (headers): la CSP no contiene frame-ancestors 'none'"
header_has referrer-policy "strict-origin-when-cross-origin" || fail "chequeo 6 (headers): Referrer-Policy no es strict-origin-when-cross-origin"
header_has x-content-type-options "nosniff" || fail "chequeo 6 (headers): X-Content-Type-Options no es nosniff"

echo "SMOKE OK $base"
