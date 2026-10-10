#!/usr/bin/env bash
# Port-forwards the UIs, reads credentials from cluster Secrets into
# environment variables (never to disk), and runs capture.mjs.
#   scripts/screenshots/capture.sh [diagram|grafana|argocd|rollouts|prometheus|loki ...]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

pf() { kubectl -n "$1" port-forward "svc/$2" "$3" >/dev/null 2>&1 & pids+=($!); }
pf monitoring kube-prometheus-stack-grafana 13000:80
pf monitoring kube-prometheus-stack-prometheus 19090:9090
pf argocd argocd-server 18080:80
kubectl argo rollouts dashboard --port 3100 >/dev/null 2>&1 & pids+=($!)
sleep 6

secret() { kubectl -n "$1" get secret "$2" -o jsonpath="{.data.$3}" | base64 -d; }
GRAFANA_USER="$(secret monitoring grafana-admin admin-user)"
GRAFANA_PASSWORD="$(secret monitoring grafana-admin admin-password)"
ARGOCD_PASSWORD="$(secret argocd argocd-initial-admin-secret password)"
export GRAFANA_USER GRAFANA_PASSWORD ARGOCD_PASSWORD

node "$ROOT/scripts/screenshots/capture.mjs" "$@"
