# Git workflow

```
feature/add-product-api ──PR──► develop ──PR──► main ──CI──► dev ──"Promote" PR──► prod
bugfix/fix-order-total  ──PR──┘
```

| Branch | Purpose | Deploys |
|---|---|---|
| `main` | always releasable; protected | dev, automatically (CI GitOps bump) |
| `develop` | integration branch for the next release; Dependabot targets it | nothing (CI only) |
| `feature/*`, `bugfix/*` | one change each, short-lived | nothing (CI only) |
| `promote/prod-*`, `rollback/prod-*` | created by workflows | prod, when merged |
| tags `vX.Y.Z` | releases | images additionally tagged `X.Y.Z` |

Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`,
`deploy(env):`, `revert:`), which keeps the deployment history readable:
`git log --oneline -- helm/cloudcart/values-prod.yaml` *is* the prod
release log.

## Branch protection for `main`

Settings -> Branches -> Add rule:

- Require a pull request before merging, with 1 approval, and dismiss stale approvals
- Require status checks: `Build & test (user-service)`, `Build & test (product-service)`, `Build & test (order-service)`, `Static analysis & repo security scan`, `Validate Terraform, Helm & Kubernetes manifests`, `Image (*)`
- Require branches to be up to date before merging
- Require conversation resolution; block force pushes and deletions
- **Allow `github-actions[bot]` to bypass** (or use a GitHub App token): the CI GitOps bump commits the new image tag straight to `main`. Without the bypass, change the `gitops-bump` job to open a PR instead.

## A change, end to end

```bash
git switch develop && git pull
git switch -c feature/add-product-api
# code + tests
mvn -f services/product-service/pom.xml verify
git commit -am "feat(product): search by name"
git push -u origin feature/add-product-api       # CI runs on the branch
# open PR -> develop, review, merge; later PR develop -> main
```
