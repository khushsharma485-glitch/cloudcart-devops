# CloudCart - common tasks. Run `make help` for the list.
# Works on Linux/macOS and on Windows with Git Bash + GNU make.
SHELL := bash
.DEFAULT_GOAL := help

SERVICES := user-service product-service order-service

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# --- Build & test ------------------------------------------------------------
.PHONY: test
test: ## Unit tests for all services (no Docker needed)
	mvn -B -f services/pom.xml test

.PHONY: verify
verify: ## Unit + integration tests (Testcontainers needs Docker)
	mvn -B -f services/pom.xml verify

.PHONY: images
images: ## Build all container images
	docker compose build

.PHONY: scan
scan: images ## Trivy scan of every image (fails on HIGH/CRITICAL with a fix available)
	@for s in $(SERVICES); do \
	  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.75.0 image \
	    --quiet --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed --scanners vuln cloudcart/$$s:local || exit 1; \
	done

.PHONY: lint
lint: ## hadolint + actionlint
	@for f in services/*/Dockerfile frontend/Dockerfile; do docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.config/hadolint.yaml:ro" hadolint/hadolint:v2.15.1 < $$f || exit 1; done
	docker run --rm -v "$(CURDIR):/repo" -w /repo rhysd/actionlint:1.7.12

.PHONY: validate
validate: ## Terraform fmt/validate/tests, Helm lint, kubeconform
	./scripts/validate-iac.sh

# --- Local stack (docker compose) -------------------------------------------
.PHONY: up
up: ## Start the stack (UI http://localhost:3000, APIs :8081-8083)
	docker compose up -d --build

.PHONY: down
down: ## Stop the stack (keeps the database volume)
	docker compose down

.PHONY: logs
logs: ## Follow all logs
	docker compose logs -f

.PHONY: smoke
smoke: ## End-to-end smoke test against docker compose
	./tests/smoke/smoke-test.sh

# --- Local Kubernetes (kind) ------------------------------------------------
.PHONY: kind-up
kind-up: ## kind cluster + plain manifests
	./scripts/local-cluster/local-cluster.sh up

.PHONY: kind-gitops
kind-gitops: ## Switch the kind cluster to GitOps (Argo CD + full platform)
	./scripts/local-cluster/local-cluster.sh gitops

.PHONY: kind-push
kind-push: ## Publish the current commit to the local GitOps mirror
	./scripts/local-cluster/local-cluster.sh push

.PHONY: kind-test
kind-test: ## Smoke + network policy + observability checks on kind
	./scripts/local-cluster/local-cluster.sh smoke
	./tests/network-policy/netpol-test.sh
	./tests/observability/verify-observability.sh

.PHONY: kind-down
kind-down: ## Delete the kind cluster
	./scripts/local-cluster/local-cluster.sh down
