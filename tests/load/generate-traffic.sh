#!/usr/bin/env bash
# Realistic mixed traffic for dashboards, HPA and alert demos:
# browse catalog, register users, place orders, plus the occasional
# invalid request (4xx) a real client would send.
#
#   tests/load/generate-traffic.sh [base-url] [seconds] [parallel-workers]
#   default: http://localhost:8080 for 300s with 4 workers
set -uo pipefail

BASE="${1:-http://localhost:8080}"
DURATION="${2:-300}"
WORKERS="${3:-4}"
end=$(( $(date +%s) + DURATION ))

json() { curl -s -m 5 -H 'Content-Type: application/json' "$@"; }
id_of() { sed -nE 's/.*"id":([0-9]+).*/\1/p' | head -n1; }

worker() {
  local w="$1" i=0 uid pid
  while (( $(date +%s) < end )); do
    i=$((i + 1))
    uid="$(json -X POST -d "{\"name\":\"Load $w-$i\",\"email\":\"load-$w-$i-$RANDOM@example.com\"}" "$BASE/api/users" | id_of)"
    pid="$(json -X POST -d "{\"name\":\"Item $w-$i\",\"price\":$((RANDOM % 90 + 10)).99,\"stock\":$((RANDOM % 20 + 5))}" "$BASE/api/products" | id_of)"
    for _ in 1 2 3; do curl -s -m 5 -o /dev/null "$BASE/api/products"; done
    if [[ -n "$uid" && -n "$pid" ]]; then
      json -o /dev/null -X POST -d "{\"userId\":$uid,\"productId\":$pid,\"quantity\":$((RANDOM % 3 + 1))}" "$BASE/api/orders"
      curl -s -m 5 -o /dev/null "$BASE/api/orders/user/$uid"
      curl -s -m 5 -o /dev/null "$BASE/api/users/$uid"
    fi
    # Expected client errors: unknown user (404) and impossible order (422).
    (( i % 5 == 0 )) && curl -s -m 5 -o /dev/null "$BASE/api/users/999999999"
    (( i % 7 == 0 )) && json -o /dev/null -X POST -d '{"userId":999999999,"productId":1,"quantity":1}' "$BASE/api/orders"
    sleep 0.$((RANDOM % 5))
  done
}

echo "generating traffic against $BASE for ${DURATION}s with $WORKERS workers"
for w in $(seq 1 "$WORKERS"); do worker "$w" & done
wait
echo "done"
