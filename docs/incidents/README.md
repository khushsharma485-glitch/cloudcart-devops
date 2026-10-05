# Incident reports and drills

Every report here comes from a drill that was **actually run** on the local
kind cluster (3 nodes, Calico, Argo CD, Argo Rollouts, kube-prometheus-stack,
Loki) on 2026-10-05/06. Timelines, commands and outputs are copied from those
runs. User impact was measured with [`tests/load/traffic-probe.sh`](../../tests/load/traffic-probe.sh),
which sends steady traffic through the ingress and counts every status code.

Several drills found real defects, which were fixed in the same session.
Those findings are marked **Found by drill**.

| # | Incident | Detection | User impact | Recovery |
|---|---|---|---|---|
| [01](01-crashloopbackoff.md) | CrashLoopBackOff from an invalid environment variable | Rollout stuck, `CloudCartCrashLooping` alert | **0 of 569 requests failed** (blue kept serving) | Rollout guard aborted, then `git revert` |
| [02](02-high-cpu.md) | High CPU | HPA, Grafana CPU panel | none | HPA scaled 1 to 4 pods in about 30 s |
| [03](03-high-memory.md) | High memory / heap exhaustion | restart count, `lastState` | one pod restart (about 36 s) | automatic restart. **Found by drill:** kernel OOMKill instead of a clean JVM exit, fixed |
| [04](04-failed-deployment.md) | Failed deployment: v2 healthy at start, 50% errors under live traffic | post-promotion Prometheus analysis | 114 of 708 requests in a 2-minute window | **automatic rollback** to blue, then `git revert` |
| [05](05-database-connection-failure.md) | Database failure: hung connections, then full outage | readiness probes, 503s, alerts | 6 of 513 (hung), full outage while the DB was down | self-healing pool, then `git revert`. **Found by drill:** Argo CD sync deadlock, fixed |
| [06](06-incorrect-configuration.md) | Incorrect configuration (wrong dependency URL) | pre-promotion smoke test | **0 of 631 requests failed** | Rollout aborted before any traffic, then `git revert` |
| [07](07-pod-and-node-failure.md) | Pod crash, node drain, node NotReady | pod status, node conditions | 1 replica: 62 failed requests (about 35 s). 2 replicas: **0 failed**. Drain: **0 failed** | ReplicaSet, PDB-aware drain. **Found by drill:** node memory exhaustion, fixed |

## How incidents are handled

1. **Detect.** An alert fires (Prometheus to Alertmanager), Argo CD shows Degraded, or a Rollout analysis fails.
2. **Stabilise first.** Blue-green and the rollout guard usually do this on their own: bad versions never get, or quickly lose, live traffic.
3. **Investigate** with the commands below.
4. **Fix through Git.** `git revert` the bad change, or run the [Rollback workflow](../../.github/workflows/rollback.yml). Manual `kubectl` edits are reverted by Argo CD self-heal within seconds.
5. **Write the report**: detection, impact, timeline, root cause, resolution, prevention.

## First-five-minutes commands

```bash
kubectl -n cloudcart get pods -o wide                      # what is running, where, restarts
kubectl -n cloudcart describe pod <pod>                    # events: probe failures, OOMKilled, image pull
kubectl -n cloudcart logs <pod> --previous                 # logs of the crashed container
kubectl -n cloudcart get events --sort-by=.lastTimestamp
kubectl argo rollouts -n cloudcart get rollout order-service   # blue/green state + analysis runs
kubectl -n argocd get applications                         # sync / health of every app
kubectl top pods -n cloudcart                              # CPU / memory now
```

Grafana: dashboard **CloudCart - Service Overview**, plus Explore with Loki:
`{namespace="cloudcart", level=~"WARN|ERROR"}`.

## Reproducing the drills

The order-service chaos endpoints (`/internal/chaos/{cpu,memory,errors,latency}`)
are enabled only when `CHAOS_ENABLED=true` (local and dev, never prod). They
are not routed by the Ingress, so reach them with `kubectl port-forward`. Each
report lists the exact commands it used.
