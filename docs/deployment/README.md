# Deployment guide

Three ways to run CloudCart, from fastest to most complete.

| Mode | What you get | Needs |
|---|---|---|
| [Docker Compose](#1-docker-compose) | 3 services + PostgreSQL + storefront | Docker |
| [Local Kubernetes (kind)](#2-local-kubernetes-kind) | the full platform: Calico, Argo CD, Argo Rollouts, Prometheus, Grafana, Loki, Alertmanager, network policies, blue-green | Docker (8 GB RAM), kind, kubectl, Helm |
| [AWS](#3-aws-eks) | EKS + RDS + ECR built by Terraform, deployed by Argo CD | AWS account, Terraform, a GitHub repository |
| [Oracle Cloud, free](oracle-cloud.md) | k3s on an Always Free ARM server, deployed by Argo CD, $0 | Oracle Cloud account, Terraform |

## 1. Docker Compose

```bash
docker compose up -d --build      # first build takes a few minutes
docker compose ps                 # wait for (healthy)
tests/smoke/smoke-test.sh         # 16 end-to-end checks
open http://localhost:3000        # storefront
docker compose logs -f order-service
docker compose down               # add -v to delete the database
```

APIs are on `localhost:8081` (users), `:8082` (products) and `:8083` (orders),
bound to 127.0.0.1 only. If port 5432 is taken on your machine, copy
`.env.example` to `.env` and set `POSTGRES_HOST_PORT`.

## 2. Local Kubernetes (kind)

```bash
scripts/local-cluster/local-cluster.sh up       # cluster + Calico + metrics-server + Traefik + app (plain manifests)
scripts/local-cluster/local-cluster.sh smoke    # smoke test through the ingress (localhost:8080)
tests/network-policy/netpol-test.sh             # proves the NetworkPolicies are enforced

scripts/local-cluster/local-cluster.sh gitops   # switch to GitOps: Git mirror + Argo CD + full platform
kubectl -n argocd get applications              # wait until all are Synced/Healthy (5-10 min)
tests/observability/verify-observability.sh     # Prometheus, Alertmanager, Loki, Grafana checks
```

GitOps mode serves a bare clone of this repository at
`git://cloudcart-git/cloudcart-devops.git` on the kind Docker network, so the
loop is the same as with GitHub:

```bash
# change something, e.g. helm/cloudcart/values-local.yaml
git commit -am "..."
scripts/local-cluster/local-cluster.sh push     # = git push
kubectl argo rollouts -n cloudcart get rollout order-service -w
```

UIs (port-forward):

```bash
kubectl -n argocd port-forward svc/argocd-server 18080:80                       # admin / argocd-initial-admin-secret
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 13000:80   # secret monitoring/grafana-admin
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 19090:9090
kubectl argo rollouts dashboard                                                  # http://localhost:3100
```

Local images: `docker compose build` then
`kind load docker-image cloudcart/<svc>:<tag> --name cloudcart`, and set
`services.<svc>.image.tag` in `values-local.yaml`.

## 3. AWS (EKS)

> Status: the Terraform is validated (`terraform validate`, 7 offline tests
> with a mocked provider, Trivy misconfiguration scan) but has **not been
> applied to a real AWS account** as part of this project. Expect to fix small
> account-specific issues on the first apply. Rough cost for dev, eu-west-1
> on-demand list prices: about $5 to $8 per day. That covers the EKS control
> plane (about $2.40), a NAT gateway (about $1.10 plus data), 2 spot
> t3.medium nodes, db.t4g.micro, an ALB, EBS and CloudWatch. Destroy it when
> not in use.

### 3.1 One-time bootstrap

```bash
aws sso login                                    # or any credential source; never put keys in files
cd terraform/bootstrap && terraform init && terraform apply
# note the state_bucket output
```

### 3.2 Infrastructure

```bash
cd terraform/environments/dev
cp backend.hcl.example backend.hcl               # bucket + region (git-ignored)
cp terraform.tfvars.example terraform.tfvars     # github_repository, eks_public_endpoint_cidrs (your IP)
terraform init -backend-config=backend.hcl
terraform plan -out tfplan && terraform apply tfplan
terraform output                                 # cluster_name, ecr_repository_urls, rds_address, rds_master_secret_arn, github_actions_role_arn
$(terraform output -raw kubeconfig_command)
```

### 3.3 Fill in the environment values from the outputs

| File | Key | Terraform output |
|---|---|---|
| `helm/cloudcart/values-dev.yaml` | `global.image.registry` | registry part of `ecr_repository_urls` |
| | `config.dbHost` | `rds_address` |
| | `database.externalSecret.remoteKey` | `rds_master_secret_arn` |
| `argocd/apps/values-dev.yaml` | `repoURL` | your GitHub repository |
| | `addons.awsLoadBalancerController.vpcId` | `vpc_id` (`terraform state show`) |
| `argocd/environments/root-dev.yaml` | `repoURL` | your GitHub repository |

Create the platform secrets once (the values never touch Git):

```bash
aws secretsmanager create-secret --name cloudcart/dev/grafana-admin \
  --secret-string "{\"admin-user\":\"admin\",\"admin-password\":\"$(openssl rand -base64 24)\"}"
aws secretsmanager create-secret --name cloudcart/dev/alertmanager-slack \
  --secret-string '{"webhook-url":"https://hooks.slack.com/services/..."}'
```

### 3.4 GitHub configuration

| Setting | Value |
|---|---|
| Variables | `AWS_REGION`, `AWS_CI_ROLE_ARN` (= `github_actions_role_arn`) |
| Optional | `SONAR_TOKEN` secret, `SONAR_ORGANIZATION` / `SONAR_HOST_URL` variables; `AWS_TERRAFORM_ROLE_ARN`, `TF_STATE_BUCKET`, `EKS_ADMIN_CIDRS` for the Terraform workflow |
| Branch protection on `main` | see [git-workflow.md](git-workflow.md) |
| Environments | `dev`, `prod` with required reviewers (Terraform apply) |

### 3.5 Install Argo CD and hand over to Git

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd --version 10.9.6 -n argocd --create-namespace \
  -f argocd/bootstrap/argocd-values.yaml --wait
kubectl apply -f argocd/environments/root-dev.yaml
kubectl -n argocd get applications -w
```

Argo CD then installs the AWS Load Balancer Controller, External Secrets,
Reloader, Argo Rollouts, the monitoring stack and CloudCart. The ALB hostname
appears on the Ingress: `kubectl -n cloudcart get ingress cloudcart`.

### 3.6 Day 2

| Task | How |
|---|---|
| Deploy to dev | merge to `main`. CI builds, scans, pushes and bumps `values-dev.yaml`. |
| Promote to prod | Actions -> **Promote to prod** -> review and merge the PR |
| Roll back | automatic during a release (blue-green analysis, rollout guard); afterwards `git revert` or Actions -> **Rollback** |
| Infrastructure change | PR touching `terraform/` -> validate and plan; Actions -> **Terraform** -> apply (approval) |
| Tear down | `terraform destroy` in `environments/dev` (prod has deletion protection on RDS) |
