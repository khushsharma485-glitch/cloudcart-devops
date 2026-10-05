#!/usr/bin/env bash
# End-to-end check of the observability stack on a running cluster:
#   Prometheus  - CloudCart targets are up, app + JVM + business metrics exist,
#                 CloudCart alert rules are loaded
#   Alertmanager- is running and has the CloudCart receiver configured
#   Loki        - CloudCart logs are searchable, with the level label
#   Grafana     - Prometheus + Loki datasources and the CloudCart dashboard exist
#
# Requires kubectl access, curl and Python 3. Uses temporary port-forwards.
set -uo pipefail

PY="$(command -v python3 || command -v python)"
NS_MON="${NS_MON:-monitoring}"
NS_APP="${NS_APP:-cloudcart}"
failures=0
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT

forward() { # service local-port remote-port
  kubectl -n "$NS_MON" port-forward "svc/$1" "$2:$3" >/dev/null 2>&1 &
  pids+=($!)
}
forward kube-prometheus-stack-prometheus 19090 9090
forward kube-prometheus-stack-alertmanager 19093 9093
forward loki 13100 3100
forward kube-prometheus-stack-grafana 13000 80
for port in 19090 19093 13100 13000; do
  for _ in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$port" && break; sleep 1; done
done

check() { # description, python expression over `d` (parsed JSON) -> truthy
  local desc="$1" url="$2" expr="$3" auth="${4:-}"
  local body
  body="$(curl -s -m 15 ${auth:+-u "$auth"} "$url")"
  if printf '%s' "$body" | "$PY" -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if ($expr) else 1)" 2>/dev/null; then
    printf 'PASS  %s\n' "$desc"
  else
    printf 'FAIL  %s\n      %s\n' "$desc" "$(printf '%s' "$body" | head -c 300)"
    failures=$((failures + 1))
  fi
}

prom() { "$PY" -c "import urllib.parse,sys; print('http://127.0.0.1:19090/api/v1/query?query=' + urllib.parse.quote(sys.argv[1]))" "$1"; }

for svc in user-service product-service order-service; do
  check "Prometheus scrapes $svc" "$(prom "up{namespace=\"$NS_APP\",job=\"$svc\"}")" \
    "len(d['data']['result']) > 0 and all(r['value'][1] == '1' for r in d['data']['result'])"
done
check "HTTP request metrics present" "$(prom "sum(http_server_requests_seconds_count{namespace=\"$NS_APP\"})")" \
  "len(d['data']['result']) == 1 and float(d['data']['result'][0]['value'][1]) > 0"
check "Latency histogram present (P95 computable)" \
  "$(prom "histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{namespace=\"$NS_APP\"}[10m])))")" \
  "len(d['data']['result']) == 1"
check "JVM heap metrics present" "$(prom "sum(jvm_memory_used_bytes{namespace=\"$NS_APP\",area=\"heap\"})")" \
  "len(d['data']['result']) == 1"
check "Container CPU metrics present (cAdvisor)" "$(prom "sum(rate(container_cpu_usage_seconds_total{namespace=\"$NS_APP\",container=\"app\"}[5m]))")" \
  "len(d['data']['result']) == 1"
check "Pod state metrics present (kube-state-metrics)" "$(prom "count(kube_pod_status_ready{namespace=\"$NS_APP\"})")" \
  "len(d['data']['result']) == 1"
check "Business metric cloudcart_orders_placed_total present" "$(prom "sum(cloudcart_orders_placed_total)")" \
  "len(d['data']['result']) == 1"
check "CloudCart alert rules loaded" "http://127.0.0.1:19090/api/v1/rules" \
  "sum(len(g['rules']) for g in d['data']['groups'] if g['name'].startswith('cloudcart')) >= 10"

check "Alertmanager ready with a webhook/slack receiver" "http://127.0.0.1:19093/api/v2/status" \
  "('webhook_configs' in d['config']['original']) or ('slack_configs' in d['config']['original'])"

loki_q="$("$PY" -c "import urllib.parse; print(urllib.parse.quote('{namespace=\"$NS_APP\"}'))")"
check "Loki has CloudCart logs" "http://127.0.0.1:13100/loki/api/v1/query_range?query=${loki_q}&limit=5&since=1h" \
  "len(d['data']['result']) > 0"
check "Loki indexes the log level label" "http://127.0.0.1:13100/loki/api/v1/label/level/values?since=1h" \
  "'INFO' in d.get('data', [])"

GRAFANA_AUTH="$(kubectl -n "$NS_MON" get secret grafana-admin -o jsonpath='{.data.admin-user}' | base64 -d):$(kubectl -n "$NS_MON" get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
check "Grafana has Prometheus and Loki datasources" "http://127.0.0.1:13000/api/datasources" \
  "{'prometheus','loki'} <= {x['type'] for x in d}" "$GRAFANA_AUTH"
check "Grafana has the CloudCart dashboard" "http://127.0.0.1:13000/api/search?query=CloudCart" \
  "any(x.get('uid') == 'cloudcart-overview' for x in d)" "$GRAFANA_AUTH"

if (( failures > 0 )); then echo "$failures observability check(s) failed"; exit 1; fi
echo "all observability checks passed"
