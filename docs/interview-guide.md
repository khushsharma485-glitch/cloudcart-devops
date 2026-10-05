# Interview guide: CloudCart

Short answers to the questions this project should prepare you for. Each one
points at the file or drill that proves it, so you can show rather than tell.
Rewrite them in your own words before an interview.

## Containers

**Why Docker?** The same artifact runs on a laptop, in CI and in EKS. Dependencies and the JRE ship inside the image, so "works on my machine" problems disappear. Everything after CI promotes that one image.

**Why multi-stage builds?** The build stage has a JDK and Maven; the runtime stage has only a JRE and the app, as Spring Boot layers. The image is smaller with fewer CVEs (no compiler or build tools), and layering means a code change ships only the application layer. See `services/*/Dockerfile` and `docker/README.md`.

**How do you secure containers?** Non-root UID 10001, read-only root filesystem, all Linux capabilities dropped, seccomp RuntimeDefault, no service-account token, resource limits, PSA `restricted`, Trivy gate, and patched base packages via `apk upgrade`.

## CI/CD and GitOps

**CI vs CD?** CI proves a change is good: build, unit and integration tests, static analysis, security scans, image build. CD gets a proven artifact into an environment. Here CI ends by pushing an immutable image and committing its tag to Git; Argo CD (CD) deploys it.

**How does the pipeline work?** `.github/workflows/ci.yml`: build-test per service (compile, unit, Testcontainers ITs, Sonar), static analysis (hadolint, actionlint, Trivy fs), IaC validation, then the image job (build, Trivy gate, push to ECR via OIDC on `main` only), then the GitOps bump of `values-dev.yaml`. It fails on any test failure or a CRITICAL CVE.

**How does an image reach ECR?** `aws-actions/configure-aws-credentials` exchanges the GitHub OIDC token for a short-lived session on an IAM role. The role trusts only this repository's `main` branch and `v*` tags and may push only to the three CloudCart repositories. `amazon-ecr-login` gets a Docker token and the job pushes `<git-sha>`. There are no stored AWS keys.

**How does EKS pull the image?** The node IAM role has `AmazonEC2ContainerRegistryReadOnly`, so the kubelet authenticates to ECR itself. Layers come from S3 through the VPC gateway endpoint, not the NAT gateway.

**Why Argo CD / GitOps?** Git is the single source of truth and the audit log. CI never needs cluster credentials. Drift is reverted automatically: a deleted NetworkPolicy came back in 7 s. Rollback is `git revert`. Prod promotion is a reviewed PR.

**Why Helm?** One chart, three value files (local, dev, prod) instead of three copies of YAML. Strategy (rolling or blue-green), replicas, resources, network peers and smoke checks are all values. `kubernetes/` keeps the plain manifests as a readable reference.

## Kubernetes

**Why Kubernetes / EKS?** Self-healing, rolling updates, autoscaling and declarative config for multiple services. EKS removes control-plane operations, integrates IAM (access entries, Pod Identity) and the ALB.

**How does a rolling deployment work?** `maxSurge: 1, maxUnavailable: 0`: start one new pod, wait for readiness, add it to the Service, terminate one old pod (after the preStop sleep and graceful shutdown), repeat. Capacity never drops.

**What happens when a pod crashes?** The kubelet restarts the container (with exponential backoff if it keeps failing, which is CrashLoopBackOff), or the ReplicaSet replaces a deleted pod. Readiness keeps traffic away until it is ready. Drill: 1 replica gave about 35 s of 503s; 2 replicas gave zero failed requests.

**What is CrashLoopBackOff?** The container keeps exiting and the kubelet waits longer between restarts (10 s, 20 s, 40 s... up to 5 min). Debug with `kubectl logs --previous` and `describe pod`. [Incident 01](incidents/01-crashloopbackoff.md): `JDBC URL invalid port number: 5432x`.

**Liveness vs readiness vs startup?** Startup gives the JVM up to 150 s before other probes count. Readiness (app plus database) decides whether the pod receives traffic. Liveness (app only) decides whether to restart it. Keeping the database out of liveness meant a database outage caused zero restarts ([incident 05](incidents/05-database-connection-failure.md)).

**How does the HPA work?** Every 15 s it reads CPU from metrics-server, compares the average to 70% of the request and computes `desired = ceil(current x usage/target)`. Scale-up is immediate, scale-down waits 5 minutes. Drill: 1 to 4 pods in about 30 s.

**What happens when CPU reaches 90%?** The HPA adds pods up to `maxReplicas`. `CloudCartHighCPU` fires if a pod is above 80% of its *limit* for 10 minutes. `CloudCartAutoscalerMaxedOut` fires if the HPA sits at max for 15 minutes, which means more capacity or a code fix.

## Releases and incidents

**How do you troubleshoot a failed deployment?** `kubectl argo rollouts get rollout`, then the analysis run and Job logs, `describe pod` and logs, then Grafana and Loki for the time window. Users are usually unaffected because blue keeps serving. Fix forward or `git revert`.

**How do you roll back?** Automatically during a release: pre-promotion analysis failure, post-promotion Prometheus analysis failure (traffic back to blue in about 2 minutes, [incident 04](incidents/04-failed-deployment.md)), or the rollout guard for a preview that never gets ready. Afterwards, `git revert` or the Rollback workflow so Git matches reality.

**Blue-green vs rolling?** Rolling is cheaper and good for low-risk services. Blue-green costs 2x capacity during the release but tests the new version before it takes traffic and rolls back instantly, because the old pods are still running.

**How do you monitor the application?** Prometheus scrapes `/actuator/prometheus` (HTTP histograms, JVM, Hikari, business counters) plus cAdvisor and kube-state-metrics. Grafana shows the golden signals. 11 alert rules go to Alertmanager. Logs are ECS JSON, shipped by Alloy to Loki, searchable by service and level.

## AWS and Terraform

**Why Terraform? Terraform vs CloudFormation?** Declarative, reviewable infrastructure with plans, modules and state. Terraform is multi-provider (GitHub, Kubernetes, Datadog...), has a larger module ecosystem and `terraform test`. CloudFormation is AWS-native with no state to manage and has drift detection built in, but it is AWS-only and more verbose.

**Why modules and environments?** `modules/{vpc,eks,rds,ecr,iam}` are reusable. `terraform/` composes them. `environments/dev|prod` set sizes and keep separate state. Dev and prod differ only in inputs: NAT per AZ, Multi-AZ RDS, node size, deletion protection.

**Where are your secrets stored?** The RDS password is generated by RDS into Secrets Manager, never in Terraform code or state. External Secrets syncs it into a Kubernetes Secret (KMS-encrypted in etcd), and Reloader restarts pods on rotation. CI uses OIDC with no keys.

**What happens if RDS goes down?** In prod, Multi-AZ fails over to the standby (about 1 to 2 minutes, same DNS name). Pods fail readiness, the ALB stops sending traffic to them, nothing restarts, and Hikari reconnects when the database is back. The drill showed services Ready 8 s after PostgreSQL returned, with zero restarts. Backups (14 days, point-in-time recovery) cover data loss.

**How would you reduce AWS cost?** Spot nodes in dev, a single NAT in dev, the S3 gateway endpoint (no NAT charges for image pulls), gp3, RDS storage autoscaling, ECR lifecycle policies, log retention limits, right-sized requests (HPA and VPA recommendations), scheduled scale-to-zero of dev at night, Savings Plans or Graviton for prod.

**How did you detect vulnerabilities?** Trivy in CI on the repository (dependencies, secrets, IaC misconfiguration) and on every image. It found 3 CRITICAL Tomcat CVEs and 6 HIGH CVEs in Jackson and pgjdbc, fixed by version pins, and a CRITICAL EKS endpoint misconfiguration, fixed with validation. Dependabot keeps everything current.
