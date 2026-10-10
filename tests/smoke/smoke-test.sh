#!/usr/bin/env bash
# End-to-end smoke test for a running CloudCart environment.
#
# Exercises every service and the order -> user/product call path, then
# exits non-zero on the first failure so it can gate a deployment.
#
# Usage:
#   Against docker compose (default ports):
#     tests/smoke/smoke-test.sh
#   Against a single ingress / load balancer:
#     BASE_URL=https://cloudcart.example.com tests/smoke/smoke-test.sh
#   Against individual services (e.g. kubectl port-forward):
#     USER_URL=http://localhost:9001 PRODUCT_URL=... ORDER_URL=... tests/smoke/smoke-test.sh
#
# Optional:
#   HEALTH_URLS  space-separated list of actuator base URLs to check.
#                Defaults to the three service URLs. Set to "" when the
#                actuator is not exposed through the ingress.
#   RETRIES      attempts for the initial health check (default 30, 5s apart)

set -euo pipefail

if [[ -n "${BASE_URL:-}" ]]; then
  USER_URL="${USER_URL:-$BASE_URL}"
  PRODUCT_URL="${PRODUCT_URL:-$BASE_URL}"
  ORDER_URL="${ORDER_URL:-$BASE_URL}"
fi
USER_URL="${USER_URL:-http://localhost:8081}"
PRODUCT_URL="${PRODUCT_URL:-http://localhost:8082}"
ORDER_URL="${ORDER_URL:-http://localhost:8083}"
HEALTH_URLS="${HEALTH_URLS-$USER_URL $PRODUCT_URL $ORDER_URL}"
RETRIES="${RETRIES:-30}"

pass=0
RUN_ID="$(date +%s)-$RANDOM"

log()  { printf '[smoke] %s\n' "$*"; }
fail() { printf '[smoke] FAIL: %s\n' "$*" >&2; exit 1; }
ok()   { pass=$((pass + 1)); printf '[smoke] ok   %s\n' "$*"; }

# request METHOD URL [JSON_BODY] -> sets STATUS and BODY
request() {
  local method="$1" url="$2" data="${3:-}" out
  if [[ -n "$data" ]]; then
    out="$(curl -sS -m 10 -X "$method" -H 'Content-Type: application/json' -d "$data" -w '\n%{http_code}' "$url")" || fail "$method $url unreachable"
  else
    out="$(curl -sS -m 10 -X "$method" -w '\n%{http_code}' "$url")" || fail "$method $url unreachable"
  fi
  STATUS="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}

expect() {
  local want="$1" what="$2"
  [[ "$STATUS" == "$want" ]] || fail "$what: expected HTTP $want, got $STATUS. Body: $BODY"
  ok "$what -> $STATUS"
}

# json_field NAME  (top-level scalar from $BODY; avoids a jq dependency)
json_field() {
  printf '%s' "$BODY" | sed -nE "s/.*\"$1\":\"?([^\",}]*)\"?.*/\1/p" | head -n1
}

wait_healthy() {
  local base="$1" i
  for ((i = 1; i <= RETRIES; i++)); do
    if curl -fsS -m 5 "$base/actuator/health/readiness" >/dev/null 2>&1; then
      ok "readiness $base"
      return 0
    fi
    log "waiting for $base ($i/$RETRIES)"
    sleep 5
  done
  fail "$base never became ready"
}

log "user=$USER_URL product=$PRODUCT_URL order=$ORDER_URL"

for base in $HEALTH_URLS; do
  wait_healthy "$base"
done

# --- user-service -----------------------------------------------------------
request POST "$USER_URL/api/users" "{\"name\":\"Smoke Test\",\"email\":\"smoke-$RUN_ID@example.com\"}"
expect 201 "create user"
USER_ID="$(json_field id)"
[[ -n "$USER_ID" ]] || fail "no user id in response: $BODY"

request GET "$USER_URL/api/users/$USER_ID"
expect 200 "get user $USER_ID"

request POST "$USER_URL/api/users" '{"name":"","email":"bad"}'
expect 400 "reject invalid user"

# --- product-service --------------------------------------------------------
request POST "$PRODUCT_URL/api/products" '{"name":"Smoke Widget","description":"smoke","price":12.50,"stock":10}'
expect 201 "create product"
PRODUCT_ID="$(json_field id)"
[[ -n "$PRODUCT_ID" ]] || fail "no product id in response: $BODY"

request PUT "$PRODUCT_URL/api/products/$PRODUCT_ID" '{"name":"Smoke Widget v2","price":10.00,"stock":10}'
expect 200 "update product $PRODUCT_ID"

# --- order-service (calls user + product services) --------------------------
request POST "$ORDER_URL/api/orders" "{\"userId\":$USER_ID,\"productId\":$PRODUCT_ID,\"quantity\":2}"
expect 201 "create order"
ORDER_ID="$(json_field id)"
TOTAL="$(json_field totalPrice)"
[[ "$TOTAL" == "20.00" || "$TOTAL" == "20.0" || "$TOTAL" == "20" ]] || fail "unexpected order total '$TOTAL'"
ok "order total uses current product price ($TOTAL)"

request PUT "$ORDER_URL/api/orders/$ORDER_ID/status" '{"status":"CONFIRMED"}'
expect 200 "confirm order $ORDER_ID"

request GET "$ORDER_URL/api/orders/user/$USER_ID"
expect 200 "list orders for user $USER_ID"

request POST "$ORDER_URL/api/orders" "{\"userId\":$USER_ID,\"productId\":$PRODUCT_ID,\"quantity\":999}"
expect 422 "reject order exceeding stock"

request POST "$ORDER_URL/api/orders" '{"userId":999999999,"productId":1,"quantity":1}'
expect 422 "reject order for unknown user"

# --- cleanup (orders are kept as an audit trail) ----------------------------
request DELETE "$PRODUCT_URL/api/products/$PRODUCT_ID"
expect 204 "delete product $PRODUCT_ID"
request DELETE "$USER_URL/api/users/$USER_ID"
expect 204 "delete user $USER_ID"

log "PASSED ($pass checks)"
