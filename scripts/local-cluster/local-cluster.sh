#!/usr/bin/env bash
# Run the whole CloudCart platform on a local kind cluster.
#
#   scripts/local-cluster/local-cluster.sh up         cluster + add-ons + app (kustomize)
#   scripts/local-cluster/local-cluster.sh images     rebuild images and load them into kind
#   scripts/local-cluster/local-cluster.sh app        (re)apply the plain manifests
#   scripts/local-cluster/local-cluster.sh smoke      run the smoke test through the ingress
#   scripts/local-cluster/local-cluster.sh down       delete the cluster
#
# Requires: docker, kind, kubectl, helm.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLUSTER=cloudcart
NS=cloudcart
SERVICES=(user-service product-service order-service)

# Chart versions are pinned so a local cluster is reproducible.
METRICS_SERVER_CHART=3.14.0
TRAEFIK_CHART=41.6.1
CALICO_VERSION=v3.33.0

log() { printf '\n==> %s\n' "$*"; }

need() {
  for bin in "$@"; do
    command -v "$bin" >/dev/null || { echo "missing required tool: $bin" >&2; exit 1; }
  done
}

cluster_up() {
  if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    log "kind cluster '$CLUSTER' already exists"
  else
    log "creating kind cluster '$CLUSTER'"
    # No --wait: nodes stay NotReady until the CNI (Calico) is installed.
    kind create cluster --config "$ROOT/scripts/local-cluster/kind-config.yaml"
  fi
  kubectl config use-context "kind-$CLUSTER" >/dev/null

  log "Calico CNI (enforces NetworkPolicy ingress and egress)"
  # Plain manifest instead of the tigera-operator chart: the chart's custom
  # resources are applied before its CRDs exist under Helm 4.
  kubectl apply --server-side -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" >/dev/null
  kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s
  kubectl wait --for=condition=Ready nodes --all --timeout=300s
}

addons() {
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
  helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
  helm repo update metrics-server traefik >/dev/null

  log "metrics-server (needed by the HPA)"
  # kind kubelets use self-signed certs; EKS installs metrics-server as a managed add-on instead.
  helm upgrade --install metrics-server metrics-server/metrics-server \
    --version "$METRICS_SERVER_CHART" -n kube-system \
    --set 'args={--kubelet-insecure-tls}' --wait

  log "Traefik ingress controller (stands in for the AWS Load Balancer Controller)"
  helm upgrade --install traefik traefik/traefik \
    --version "$TRAEFIK_CHART" -n traefik --create-namespace \
    --set service.type=NodePort \
    --set ports.web.nodePort=30080 \
    --set 'nodeSelector.kubernetes\.io/hostname=cloudcart-control-plane' \
    --set 'tolerations[0].key=node-role.kubernetes.io/control-plane' \
    --set 'tolerations[0].effect=NoSchedule' \
    --set ingressClass.enabled=true \
    --set ingressClass.isDefaultClass=false \
    --wait
}

images() {
  log "building images"
  docker compose -f "$ROOT/docker-compose.yml" build
  for s in "${SERVICES[@]}"; do
    log "loading cloudcart/$s:local into kind"
    kind load docker-image "cloudcart/$s:local" --name "$CLUSTER"
  done
}

db_secret() {
  kubectl apply -f "$ROOT/kubernetes/namespace.yaml" >/dev/null
  if kubectl -n "$NS" get secret cloudcart-db >/dev/null 2>&1; then
    log "secret cloudcart-db already exists"
  else
    log "creating secret cloudcart-db with a random password (never written to disk)"
    kubectl -n "$NS" create secret generic cloudcart-db \
      --from-literal=username=cloudcart \
      --from-literal=password="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
  fi
}

app() {
  db_secret
  log "applying plain manifests (kustomize local overlay)"
  kubectl apply -k "$ROOT/scripts/local-cluster/overlay"
  kubectl -n "$NS" rollout status statefulset/postgres --timeout=180s
  for s in "${SERVICES[@]}"; do
    kubectl -n "$NS" rollout status "deployment/$s" --timeout=300s
  done
  kubectl -n "$NS" get pods -o wide
}

smoke() {
  # Only /api/* is exposed through the ingress, so health is checked via
  # port-forward and the business flow via the ingress.
  BASE_URL=http://localhost:8080 HEALTH_URLS="" "$ROOT/tests/smoke/smoke-test.sh"
}

case "${1:-up}" in
  up)     need docker kind kubectl helm; cluster_up; addons; images; app ;;
  addons) need kubectl helm; addons ;;
  images) need docker kind; images ;;
  app)    need kubectl; app ;;
  smoke)  smoke ;;
  down)   need kind; kind delete cluster --name "$CLUSTER" ;;
  *)      echo "usage: $0 {up|addons|images|app|smoke|down}" >&2; exit 2 ;;
esac
