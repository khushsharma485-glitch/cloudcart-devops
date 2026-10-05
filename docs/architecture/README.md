# Architecture

![CloudCart architecture](cloudcart-architecture.png)

(The PNG is rendered from [`cloudcart-architecture.html`](cloudcart-architecture.html)
by `scripts/screenshots/capture.mjs diagram`.)

## Services

| Service | Owns | API | Calls |
|---|---|---|---|
| user-service | `user_service` schema | `POST/GET /api/users`, `GET/DELETE /api/users/{id}` | none |
| product-service | `product_service` schema | `POST/GET /api/products`, `GET/PUT/DELETE /api/products/{id}` | none |
| order-service | `order_service` schema | `POST /api/orders`, `GET /api/orders/{id}`, `GET /api/orders/user/{userId}`, `PUT /api/orders/{id}/status` | user-service, product-service |

- **Database per service, one PostgreSQL instance.** Each service has its own schema, created and migrated by Flyway at startup (`ddl-auto: validate` means Hibernate never changes the schema). There are no cross-schema foreign keys, so services can be split onto separate databases later without code changes.
- **Order creation** validates the user and product synchronously over HTTP, captures the price at order time, and checks stock. A 404 from a dependency becomes **422** (business error). A timeout, refused connection or 5xx becomes **503** with `"dependency": "<name>"`. Remote calls happen *outside* the database transaction so a slow dependency never holds a DB connection.
- **Order status** is a state machine: `PENDING -> CONFIRMED -> SHIPPED -> DELIVERED`, with `CANCELLED` allowed from PENDING and CONFIRMED. Illegal moves return **409**.
- **Errors** use RFC 9457 `application/problem+json` everywhere. Validation errors list each field. Unexpected exceptions return a generic 500 and never leak details (a test asserts this).

## Operational endpoints (every service)

| Endpoint | Used by |
|---|---|
| `/actuator/health/liveness` | Kubernetes `startupProbe` and `livenessProbe`, Docker `HEALTHCHECK` |
| `/actuator/health/readiness` | Kubernetes `readinessProbe` (includes the database check), ALB health check |
| `/actuator/prometheus` | Prometheus (ServiceMonitor), every 15 s |
| `/actuator/info`, `/actuator/metrics` | humans and debugging |

Metrics include `http_server_requests_seconds` (a histogram, so p95 and p99 can be computed), JVM, HikariCP, `http_client_requests_seconds`
(order-service's outbound calls) and business counters
`cloudcart_orders_placed_total` and `cloudcart_orders_rejected_total{reason}`.
Logs are ECS JSON on stdout.

## Delivery flow

```
developer -> PR -> CI (tests, Sonar, Trivy, lint, IaC validation)
                -> merge to main -> CI builds image, Trivy gate, pushes <sha> to ECR
                -> CI commits <sha> to helm/cloudcart/values-dev.yaml   (the only thing CI changes)
Argo CD (dev cluster) sees the commit -> syncs the Helm chart
   -> Deployments: RollingUpdate maxSurge 1 / maxUnavailable 0
   -> Rollouts:    blue-green + pre/post-promotion analysis, automatic abort
   -> PostSync hook: end-to-end smoke test across all three services
Promote: "Promote to prod" workflow opens a PR that copies the tag to values-prod.yaml.
         Review + merge = deploy. Prod gets the exact image dev ran.
```

Why pull-based (GitOps) instead of `kubectl apply` from CI:

- CI never holds cluster credentials. The CI IAM role can push to ECR and nothing else (no `eks:*`, no access entry).
- Git is the audit log and the rollback mechanism (`git revert`).
- Argo CD self-heal reverts manual drift. This was tested: a deleted NetworkPolicy and an edited ConfigMap were restored within 7 s.

## Kubernetes design

| Concern | How |
|---|---|
| Health | startup probe (up to 150 s for JVM boot), readiness (app + DB), liveness (app only, so DB outages do not cause restart storms) |
| Resources | requests and limits on every container. JVM heap = 65% of the memory limit |
| Scaling | HPA on CPU (70% of request), fast up and slow down, min 2 (dev) / 3 (prod) |
| Disruptions | PDB, topology spread across zones and nodes, `preStop` sleep 5 s plus graceful shutdown 20 s |
| Security | PSA `restricted`, non-root UID 10001, read-only root FS, all capabilities dropped, seccomp RuntimeDefault, no service account token mounted |
| Network | default-deny ingress and egress; explicit allows for ALB to services, order to user/product, services to DB:5432, DNS, Prometheus scrape |
| Secrets | External Secrets syncs the RDS password from Secrets Manager; Reloader restarts pods when it rotates |

## AWS design

| Layer | Choice | Why |
|---|---|---|
| Network | /16 VPC, 3 tiers of /20 subnets across 2 AZs (dev) or 3 (prod) | DB subnets have no Internet route at all |
| NAT | 1 shared (dev), 1 per AZ (prod) | cost vs. AZ-failure tolerance |
| S3 gateway endpoint | yes | image layer pulls bypass NAT data charges |
| EKS | managed node group on AL2023, API authentication mode with access entries, Pod Identity, KMS-encrypted Secrets, control-plane logs to CloudWatch, IMDSv2 hop limit 1 | no aws-auth ConfigMap, no node-role credential theft from pods |
| RDS | PostgreSQL 16, gp3 with autoscaling, Multi-AZ + deletion protection + 14-day backups in prod, `rds.force_ssl=1`, password managed by Secrets Manager | the password never exists in Terraform state or Git |
| ECR | immutable tags, scan on push, lifecycle policy | a tag always means the same image |
| IAM | GitHub OIDC (no access keys), CI role limited to ECR push from `main` / `v*` tags; Pod Identity roles for the LB controller and External Secrets | least privilege |
| Alerts | SNS topic with a customer-managed KMS key (CloudWatch cannot publish to a topic encrypted with `aws/sns`) | found by the Trivy misconfiguration scan |
