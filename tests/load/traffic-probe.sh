#!/usr/bin/env bash
# Sends a steady stream of requests and records every status code, so a
# deployment or incident drill can prove (or disprove) zero downtime.
#
#   tests/load/traffic-probe.sh [url] [seconds] [requests-per-second]
#   default: http://localhost:8080/api/orders/user/1 for 120s at 5 rps
#
# Prints a per-status summary at the end; exits 1 if any request failed.
set -uo pipefail

URL="${1:-http://localhost:8080/api/orders/user/1}"
DURATION="${2:-120}"
RPS="${3:-5}"
interval=$(awk "BEGIN {print 1/$RPS}")
end=$(( $(date +%s) + DURATION ))
declare -A counts=()
first_error=""

while (( $(date +%s) < end )); do
  code="$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$URL" || true)"
  counts[$code]=$(( ${counts[$code]:-0} + 1 ))
  if [[ "$code" != 2* && -z "$first_error" ]]; then first_error="$(date +%T) HTTP $code"; fi
  sleep "$interval"
done

total=0; failed=0
for c in "${!counts[@]}"; do
  total=$(( total + counts[$c] ))
  [[ "$c" == 2* ]] || failed=$(( failed + counts[$c] ))
done
printf 'traffic probe: %s requests to %s over %ss\n' "$total" "$URL" "$DURATION"
for c in "${!counts[@]}"; do printf '  HTTP %s: %s\n' "$c" "${counts[$c]}"; done
if (( failed > 0 )); then
  printf '  %s failed request(s), first at %s\n' "$failed" "$first_error"
  exit 1
fi
echo "  zero failed requests"
