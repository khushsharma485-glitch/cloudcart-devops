#!/usr/bin/env bash
# Hands the Oracle Cloud k3s server over to GitOps.
#
#   scripts/oci/bootstrap.sh <public-ip>     # after `terraform apply` in terraform/oci
#   scripts/oci/bootstrap.sh <public-ip> tunnel   # only open the API tunnel (for kubectl)
#
# 1. waits for k3s (installed by cloud-init) to be ready
# 2. copies the kubeconfig and opens an SSH tunnel to the Kubernetes API
#    (the API port is not exposed to the Internet)
# 3. installs Argo CD from the pinned chart
# 4. creates the database and Grafana passwords on the cluster only
# 5. applies the root app-of-apps -> Argo CD deploys everything from GitHub
set -euo pipefail

IP="${1:?usage: $0 <public-ip> [tunnel]}"
MODE="${2:-bootstrap}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KUBECONFIG_FILE="$HOME/.kube/cloudcart-oci.yaml"
LOCAL_PORT=16443
ARGOCD_CHART=10.9.6
SSH="ssh -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 ubuntu@$IP"

log() { printf '\n==> %s\n' "$*"; }
random_secret() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-32}"; }

log "waiting for k3s on $IP (first boot takes 3-6 minutes)"
for i in $(seq 1 60); do
  if $SSH 'sudo k3s kubectl get --raw=/readyz' >/dev/null 2>&1; then break; fi
  [[ $i -eq 60 ]] && { echo "k3s did not become ready; check: $SSH 'sudo cloud-init status --long'" >&2; exit 1; }
  sleep 10
done

log "fetching kubeconfig to $KUBECONFIG_FILE"
mkdir -p "$(dirname "$KUBECONFIG_FILE")"
$SSH 'sudo cat /etc/rancher/k3s/k3s.yaml' \
  | sed "s#https://127.0.0.1:6443#https://127.0.0.1:$LOCAL_PORT#; s#: default\$#: cloudcart-oci#" > "$KUBECONFIG_FILE"
chmod 600 "$KUBECONFIG_FILE"
export KUBECONFIG="$KUBECONFIG_FILE"

if ! (echo > "/dev/tcp/127.0.0.1/$LOCAL_PORT") 2>/dev/null; then
  log "opening SSH tunnel 127.0.0.1:$LOCAL_PORT -> k3s API"
  ssh -f -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
    -L "$LOCAL_PORT:127.0.0.1:6443" "ubuntu@$IP"
fi
kubectl get nodes -o wide

if [[ "$MODE" == tunnel ]]; then
  echo "export KUBECONFIG=$KUBECONFIG_FILE"
  exit 0
fi

log "installing Argo CD"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd --version "$ARGOCD_CHART" -n argocd --create-namespace \
  -f "$ROOT/argocd/bootstrap/argocd-values.yaml" --wait --timeout 15m

log "creating secrets (generated here, stored only in the cluster)"
kubectl create namespace cloudcart --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n cloudcart get secret cloudcart-db >/dev/null 2>&1 || \
  kubectl -n cloudcart create secret generic cloudcart-db \
    --from-literal=username=cloudcart --from-literal=password="$(random_secret 32)"
kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1 || \
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin --from-literal=admin-password="$(random_secret 24)"

log "applying the root app-of-apps (argocd/environments/root-oci.yaml)"
kubectl apply -f "$ROOT/argocd/environments/root-oci.yaml"

cat <<EOF

Argo CD is now deploying CloudCart from GitHub (5-10 minutes on first run).
  watch:      KUBECONFIG=$KUBECONFIG_FILE kubectl -n argocd get applications -w
  API:        http://$IP/api/products
  smoke test: BASE_URL=http://$IP HEALTH_URLS="" tests/smoke/smoke-test.sh
  Argo CD UI: kubectl -n argocd port-forward svc/argocd-server 18080:80
              (user admin, password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
EOF
