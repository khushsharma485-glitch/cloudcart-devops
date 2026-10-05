# What has been verified, and what has not

This project follows one rule: **do not claim something works unless it was
run.** This page lists every claim and the evidence behind it.

Environment: Windows 11, Docker Desktop 29.2 (8 CPUs, 8 GB VM), Java 17
(Corretto), Maven 3.9.16, kind 0.33 (Kubernetes 1.37 nodes), Helm 4.3,
Terraform 1.16.5 (container), Trivy 0.75, 2026-10-05/06.

## Verified by running it

| Area | Evidence |
|---|---|
| Unit tests | 43 tests (user 10, product 7, order 26) pass: `mvn -f services/pom.xml verify` |
| Integration tests | 7 tests against real PostgreSQL 16 via Testcontainers (full HTTP stack, Flyway migrations, actuator, Prometheus output) |
| Containers | 3 images build; run as UID 10001 with a read-only FS in Compose; Docker healthchecks pass |
| Image security | Trivy: 0 HIGH / 0 CRITICAL fixable vulnerabilities in all images after dependency pins (initially 3 CRITICAL in Tomcat + 6 HIGH in Jackson and pgjdbc) |
| Compose stack | `tests/smoke/smoke-test.sh`: 16/16 checks (create/read/update/delete, order flow across services, 400/422 paths) |
| CI workflow syntax | actionlint (with shellcheck) clean on all 4 workflows; hadolint clean on 4 Dockerfiles |
| Terraform | `fmt -check`, `validate` (dev, prod, bootstrap); **7 `terraform test` runs with a mocked AWS provider** (VPC/NAT layout per environment, shared ECR, RDS hardening, API endpoint guard rails); Trivy misconfiguration scan clean apart from one documented accepted risk |
| Kubernetes manifests | kubeconform strict, Kubernetes 1.36 + CRD schemas: 232 resources (plain manifests, Helm for local/dev/prod, Argo CD apps, monitoring config) |
| Plain manifests on a cluster | deployed to kind, smoke test through the Traefik ingress |
| NetworkPolicies enforced | `tests/network-policy/netpol-test.sh` 9/9 on Calico |
| GitOps | Argo CD app-of-apps syncs 8 Applications from Git; self-heal restored a deleted NetworkPolicy and an edited ConfigMap in 7 s |
| Blue-green | real release 2.0.0: preview, pre-promotion smoke Job, cutover, 5-minute Prometheus error-rate analysis, promotion |
| Automated rollback | post-promotion analysis aborted a release at 52% errors and returned traffic to blue (incident 04); rollout guard aborted a crash-looping release (incident 01); pre-promotion check refused a misconfigured release (incident 06) |
| Zero-downtime claims | traffic probe: 0 failed requests during a failed release (569 req), a misconfigured release (631), a pod kill with 2 replicas (143) and a node drain (274) |
| HPA | scaled 1 to 4 under CPU load, back down afterwards |
| Observability | `tests/observability/verify-observability.sh` 15/15: Prometheus targets and metrics (HTTP, latency histogram, JVM, cAdvisor, kube-state-metrics, business), 14 CloudCart rules loaded (11 alerts, 3 recording rules), Alertmanager delivering to a webhook receiver (`POST /alerts 200`), Loki logs with a `level` label, Grafana datasources and dashboard |
| Screenshots | `docs/screenshots/*.png` captured from that running cluster |

## Not verified (needs an AWS account)

| Area | Status |
|---|---|
| `terraform apply` of VPC, EKS, RDS, ECR, IAM | **not run.** Code validates and passes mocked tests; first real apply may surface account-specific issues (quotas, AZ names, add-on versions). |
| ECR push from GitHub Actions via OIDC | workflow written and linted, not run (no GitHub remote or AWS role) |
| AWS Load Balancer Controller / ALB Ingress | values written; not deployed (Traefik used locally) |
| External Secrets with Secrets Manager / Pod Identity | manifests validated against CRD schemas; not run (local cluster uses a generated Secret) |
| SonarQube analysis | Maven plugin step configured; skipped without `SONAR_TOKEN` |
| Slack notifications | Alertmanager config validated; locally a webhook logger receiver was used |
| Promote / Rollback / Terraform workflows | linted (actionlint), yq expressions tested locally; not run on GitHub |
| Multi-AZ behaviour, RDS failover, Cluster Autoscaler | not testable locally |

To close these gaps: create the GitHub repository, follow
[deployment](deployment/README.md) section 3, run the CI pipeline once on `main`, and
repeat the drills in [incidents](incidents/README.md) against dev.
