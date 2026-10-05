# Troubleshooting

Every entry below is a problem that actually occurred while building and
testing CloudCart, with its real symptom and fix.

## Build and test

| Symptom | Cause | Fix |
|---|---|---|
| `docker compose up`: `ports are not available: ... 127.0.0.1:5432 ... access permissions` | Another PostgreSQL already listens on 5432 on the host | `.env`: `POSTGRES_HOST_PORT=5433` (see `.env.example`) |
| Prometheus metric `cloudcart_orders_created_total` missing; `cloudcart_orders_total` appears instead | Prometheus client 1.x treats a `_created` suffix as an OpenMetrics created-timestamp | Counter renamed to `cloudcart.orders.placed` |
| `mvn package -DskipTests` still runs unit tests | Surefire `<skipTests>${skipUTs}</skipTests>` overrode the CLI flag | Bind the custom switch to surefire's `<skip>` instead; both `-DskipTests` and `-DskipUTs` now work |
| Trivy: `remote Maven repository returned 429 Too Many Requests` | `trivy fs` resolves every parent POM from Maven Central | Warm `~/.m2` (`mvn dependency:go-offline`), mount it read-only into Trivy, and use `--offline-scan` (as CI does) |
| Trivy image scan: `context deadline exceeded` on Docker Desktop | Exporting the image from the Docker daemon is slow | `docker save img -o img.tar` and `trivy image --input img.tar --timeout 15m` |

## Kubernetes

| Symptom | Cause | Fix |
|---|---|---|
| Pods restart 2-3 times on first deploy, `Connect timed out` to PostgreSQL | Services started before PostgreSQL was ready, Spring exited | Flyway `connect-retries: 10` / `connect-retries-interval: 5s` |
| NetworkPolicy default-deny egress has no effect on kind | kindnet enforced ingress but not egress in testing | Calico (`disableDefaultCNI: true`). On EKS enable `enableNetworkPolicy` on the vpc-cni add-on. |
| Container `OOMKilled`, exit 137, no Java error in logs | Heap (75% of limit) plus non-heap memory exceeded the cgroup limit | `MaxRAMPercentage=65`. Failures now exit with code 3 and `OutOfMemoryError` in the logs. [Incident 03](../incidents/03-high-memory.md) |
| Grafana pod `2/3`, restarts, dashboard panels never load | Grafana `OOMKilled` at 384 Mi rendering a 26-panel dashboard | Limit 768 Mi |
| `kubectl` hangs, `TLS handshake timeout`, a node `NotReady`, Calico probes time out | Docker VM out of memory (HPA at 4 plus a blue-green preview at 4) | Restart the node containers, cap the local HPA, size for 2x replicas during blue-green. [Incident 07](../incidents/07-pod-and-node-failure.md) |
| Ingress has no `ADDRESS`, Argo CD shows it `Progressing` forever | Traefik on a NodePort Service publishes no load-balancer address | Traefik `--providers.kubernetesingress.ingressendpoint.ip=127.0.0.1` |

## Argo CD / Argo Rollouts

| Symptom | Cause | Fix |
|---|---|---|
| `failed to list refs: unexpected EOF` | Argo CD uses go-git, which cannot read Git "dumb HTTP" (a static web server) | Serve the local mirror with `git daemon` (`git://`) |
| `git: 'daemon' is not a git command` | `alpine/git` does not include git-daemon | `alpine` + `apk add git-daemon` |
| Rollout or Services permanently `OutOfSync`; self-heal loops re-applying them | Legacy client-side diff misreads fields co-owned by the Rollouts controller and the HPA when syncing with ServerSideApply | `controller.diff.server.side: "true"` |
| `YAML parse error ... mapping values are not allowed` in the root app | One mis-indented label in a template (an earlier render was cached) | Fixed indentation; `scripts/validate-iac.sh` renders every environment |
| Blue-green preview crash-loops forever and the Rollout never aborts | Argo Rollouts 1.10 does not evaluate `progressDeadlineSeconds` while the preview waits to become available | Rollout guard CronJob. [Incident 01](../incidents/01-crashloopbackoff.md) |
| A `git revert` does not deploy; app shows `Running waiting for healthy state of ...` | The previous sync waits for health before PostSync hooks and can never finish; no new sync starts | `argocd app terminate-op <app>`; permanently `controller.sync.timeout.seconds: "600"`. [Incident 05](../incidents/05-database-connection-failure.md) |
| Manual `kubectl scale/edit/delete` is undone within seconds | Argo CD self-heal | Expected. Change Git instead, or run game days through Git commits. |
| Post-promotion analysis passes although the new version is broken | No traffic reached it; `or vector(0)` counts no traffic as no errors | Drive traffic during analysis (synthetic checks), or add a minimum-request-rate metric |

## Useful commands

```bash
kubectl -n cloudcart get pods -o wide
kubectl -n cloudcart describe pod <pod> | sed -n '/Events/,$p'
kubectl -n cloudcart logs <pod> --previous
kubectl argo rollouts -n cloudcart get rollout order-service
kubectl argo rollouts -n cloudcart abort|retry|undo rollout order-service
kubectl -n argocd get applications
kubectl -n argocd get application cloudcart-local -o jsonpath='{.status.operationState.message}'
kubectl -n argocd exec argocd-application-controller-0 -- argocd app diff cloudcart-local --core
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```
