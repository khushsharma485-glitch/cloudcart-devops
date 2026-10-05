#!/usr/bin/env bash
# Run the whole CloudCart platform on a local kind cluster.
#
#   scripts/local-cluster/local-cluster.sh up         cluster + add-ons + app (kustomize)
#   scripts/local-cluster/local-cluster.sh images     rebuild images and load them into kind
#   scripts/local-cluster/local-cluster.sh app        (re)apply the plain manifests
#   scripts/local-cluster/local-cluster.sh smoke      run the smoke test through the ingress
#   scripts/local-cluster/local-cluster.sh gitops     switch to GitOps: Git mirror + Argo CD + app-of-apps
#   scripts/local-cluster/local-cluster.sh push       publish the current commit to the Git mirror (= git push)
#   scripts/local-cluster/local-cluster.sh down       delete the cluster and the Git mirror
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
ARGOCD_CHART=10.9.6

# Local stand-in for GitHub: a bare clone served by `git daemon` (git://)
# on the kind Docker network. Argo CD reads
# git://cloudcart-git/cloudcart-devops.git exactly as it would read GitHub.
# (Argo CD uses go-git, which does not support git's "dumb HTTP", so a
# static web server is not enough.)
GIT_MIRROR_DIR="$ROOT/.local/gitops"
GIT_MIRROR_REPO="$GIT_MIRROR_DIR/cloudcart-devops.git"
GIT_SERVER=cloudcart-git

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
      --from-literal=password="$(random_secret 32)"
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

host_path() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }

random_secret() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-32}"; }

git_push_mirror() {
  if [[ ! -d "$GIT_MIRROR_REPO" ]]; then
    log "creating bare Git mirror at $GIT_MIRROR_REPO"
    mkdir -p "$GIT_MIRROR_DIR"
    git init -q --bare "$GIT_MIRROR_REPO"
  fi
  log "pushing $(git -C "$ROOT" rev-parse --short HEAD) ($(git -C "$ROOT" branch --show-current)) to the mirror as main"
  git -C "$ROOT" push -q --force "$GIT_MIRROR_REPO" HEAD:refs/heads/main
}

git_server() {
  if docker ps --format '{{.Names}}' | grep -qx "$GIT_SERVER"; then return; fi
  docker rm -f "$GIT_SERVER" >/dev/null 2>&1 || true
  log "starting Git server container '$GIT_SERVER' on the kind network"
  MSYS_NO_PATHCONV=1 docker run -d --name "$GIT_SERVER" --network kind --restart unless-stopped     -v "$(host_path "$GIT_MIRROR_DIR"):/srv/git:ro" alpine:3.22     sh -c 'apk add --no-cache git-daemon >/dev/null && exec git daemon --reuseaddr --base-path=/srv/git --export-all --verbose /srv/git' >/dev/null
}

gitops() {
  git_push_mirror
  git_server

  if kubectl -n "$NS" get deployment user-service -o jsonpath='{.metadata.annotations}' 2>/dev/null | grep -q kubectl.kubernetes.io/last-applied-configuration; then
    log "removing the kubectl-applied workload; Argo CD takes over from here"
    kubectl delete -k "$ROOT/scripts/local-cluster/overlay" --ignore-not-found --wait=true >/dev/null
  fi

  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm repo update argo >/dev/null
  log "installing Argo CD"
  helm upgrade --install argocd argo/argo-cd --version "$ARGOCD_CHART" -n argocd --create-namespace     -f "$ROOT/argocd/bootstrap/argocd-values.yaml" --wait --timeout 10m

  # Credentials that exist only in the cluster (on EKS these come from
  # AWS Secrets Manager through External Secrets).
  db_secret
  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
    log "creating secret grafana-admin with a random password"
    kubectl -n monitoring create secret generic grafana-admin       --from-literal=admin-user=admin --from-literal=admin-password="$(random_secret 24)" >/dev/null
  fi

  log "applying the root app-of-apps"
  kubectl apply -f "$ROOT/argocd/environments/root-local.yaml"
  log "Argo CD is syncing. Watch with: kubectl -n argocd get applications -w"
}

case "${1:-up}" in
  up)     need docker kind kubectl helm; cluster_up; addons; images; app ;;
  addons) need kubectl helm; addons ;;
  images) need docker kind; images ;;
  app)    need kubectl; app ;;
  smoke)  smoke ;;
  gitops) need docker git kubectl helm; gitops ;;
  push)   need git; git_push_mirror ;;
  down)   need kind; kind delete cluster --name "$CLUSTER"; docker rm -f "$GIT_SERVER" >/dev/null 2>&1 || true ;;
  *)      echo "usage: $0 {up|addons|images|app|smoke|gitops|push|down}" >&2; exit 2 ;;
esac
