#!/usr/bin/env bash
# Verifies that the cloudcart NetworkPolicies are actually ENFORCED, not just
# accepted by the API server. Each case starts a throwaway pod (with or
# without CloudCart labels) and checks one connection against the expected
# outcome. Exits non-zero if any case differs.
#
#   tests/network-policy/netpol-test.sh            # namespace cloudcart
#   NS=cloudcart DB_HOST=postgres tests/network-policy/netpol-test.sh
set -uo pipefail

NS="${NS:-cloudcart}"
DB_HOST="${DB_HOST:-postgres}"
failures=0

probe() {
  local name="$1" labels="$2" target="$3" port="$4" expected="$5"
  kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: $NS
  labels: {netpol-test: "true"${labels:+, $labels}}
spec:
  restartPolicy: Never
  securityContext: {runAsNonRoot: true, runAsUser: 1000, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: probe
      image: busybox:1.37
      command: ["sh", "-c", "if nc -z -w 3 $target $port; then echo REACHABLE; else echo BLOCKED; fi"]
      resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 32Mi}}
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
YAML
  kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$name" --timeout=90s >/dev/null 2>&1
  local got
  got="$(kubectl -n "$NS" logs "$name" 2>/dev/null | tail -1)"
  kubectl -n "$NS" delete pod "$name" --wait=false >/dev/null 2>&1
  if [[ "$got" == "$expected" ]]; then
    printf 'PASS  %-45s %s:%s -> %s\n' "$name" "$target" "$port" "$got"
  else
    printf 'FAIL  %-45s %s:%s -> got %s, expected %s\n' "$name" "$target" "$port" "${got:-nothing}" "$expected"
    failures=$((failures + 1))
  fi
}

ORDER='app.kubernetes.io/name: order-service, cloudcart.io/tier: backend'
PRODUCT='app.kubernetes.io/name: product-service, cloudcart.io/tier: backend'
BACKEND='cloudcart.io/tier: backend'

probe random-to-user-service     ""         user-service    80   BLOCKED
probe random-to-order-service    ""         order-service   80   BLOCKED
probe order-to-user-service      "$ORDER"   user-service    80   REACHABLE
probe order-to-product-service   "$ORDER"   product-service 80   REACHABLE
probe product-to-user-service    "$PRODUCT" user-service    80   BLOCKED
probe backend-to-database        "$BACKEND" "$DB_HOST"      5432 REACHABLE
probe random-to-database         ""         "$DB_HOST"      5432 BLOCKED
probe random-to-internet         ""         1.1.1.1         443  BLOCKED
probe backend-to-internet        "$BACKEND" 1.1.1.1         443  BLOCKED

if (( failures > 0 )); then
  echo "$failures network policy check(s) failed"
  exit 1
fi
echo "all network policy checks passed"
