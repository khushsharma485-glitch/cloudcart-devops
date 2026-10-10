#!/usr/bin/env bash
# Validates all infrastructure code without touching any cloud account:
#   1. Terraform  - fmt, validate (dev, prod, bootstrap) and offline tests
#   2. Helm       - lint + render the CloudCart chart for every environment
#   3. Argo CD    - lint + render the app-of-apps for every environment
#   4. Kubernetes - build the plain kustomize manifests
#   5. Schemas    - kubeconform strict validation of everything rendered
#
# Uses local terraform/helm/kubectl/kubeconform when installed, otherwise
# the pinned container images below (only Docker is required).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

TERRAFORM_IMAGE=hashicorp/terraform:1.16.5
HELM_IMAGE=alpine/helm:4.3.0
KUBECONFORM_IMAGE=ghcr.io/yannh/kubeconform:v0.8.0
K8S_VERSION=1.36.0
ENVS=(local dev prod)

# Docker on Windows (Git Bash) needs native paths and no MSYS path rewriting.
host_path() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
export MSYS_NO_PATHCONV=1

if ! command -v terraform >/dev/null; then
  terraform() {
    local wd; wd="${PWD#"$ROOT"}"
    docker run --rm -v "$(host_path "$ROOT"):/repo" -v cloudcart-tf-plugins:/plugins \
      -e TF_PLUGIN_CACHE_DIR=/plugins -w "/repo$wd" "$TERRAFORM_IMAGE" "$@"
  }
fi
if ! command -v helm >/dev/null; then
  helm() { docker run --rm -v "$(host_path "$ROOT"):/apps" -w /apps "$HELM_IMAGE" "$@"; }
fi
if ! command -v kubeconform >/dev/null; then
  kubeconform() { docker run --rm -v "$(host_path "$OUT"):/out" -w /out "$KUBECONFORM_IMAGE" "$@"; }
  KC_DIR=/out
else
  KC_DIR="$OUT"
fi

step() { printf '\n=== %s\n' "$*"; }

step "Terraform: format"
terraform -chdir=terraform fmt -check -recursive -diff

for d in terraform/environments/dev terraform/environments/prod terraform/bootstrap; do
  step "Terraform: validate $d"
  (cd "$d" && terraform init -backend=false -input=false -no-color >/dev/null && terraform validate -no-color)
done

for d in terraform terraform/modules/rds terraform/modules/ecr; do
  step "Terraform: offline tests in $d (mocked AWS provider)"
  (cd "$d" && terraform init -backend=false -input=false -no-color >/dev/null && terraform test -no-color)
done

for e in "${ENVS[@]}"; do
  step "Helm: cloudcart chart ($e)"
  helm lint helm/cloudcart -f "helm/cloudcart/values-$e.yaml" --strict
  helm template cloudcart helm/cloudcart -n cloudcart -f "helm/cloudcart/values-$e.yaml" > "$OUT/cloudcart-$e.yaml"

  step "Helm: Argo CD app-of-apps ($e)"
  helm lint argocd/apps -f "argocd/apps/values-$e.yaml" --strict
  helm template root argocd/apps -f "argocd/apps/values-$e.yaml" > "$OUT/argocd-apps-$e.yaml"
done

step "Helm: secret-stores chart"
helm lint argocd/platform/secret-stores --strict
helm template secret-stores argocd/platform/secret-stores > "$OUT/secret-stores.yaml"

step "Kustomize: plain manifests (EKS base + local overlay) and monitoring config"
kubectl kustomize kubernetes > "$OUT/kubernetes-base.yaml"
kubectl kustomize scripts/local-cluster/overlay > "$OUT/kubernetes-local.yaml"
for e in "${ENVS[@]}"; do
  kubectl kustomize "monitoring/overlays/$e" > "$OUT/monitoring-$e.yaml"
done

step "kubeconform: strict schema validation (Kubernetes $K8S_VERSION + CRDs)"
files=()
for f in "$OUT"/*.yaml; do files+=("$KC_DIR/$(basename "$f")"); done
kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "${files[@]}"

step "All infrastructure validation passed"
