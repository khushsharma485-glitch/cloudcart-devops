# Incident 05: database connection failure (hung connections, then full outage)

Two drills against PostgreSQL. The second one found a GitOps deadlock.

## Part A: hung database connections

| | |
|---|---|
| **Detection** | Readiness probes failing (`/actuator/health/readiness` includes the `db` check) |
| **User impact** | 6 of 513 requests timed out (HTTP 000) in about 1 minute |
| **Recovery** | Automatic, with no pod restarts |

All PostgreSQL processes were frozen with `SIGSTOP` (`kill -STOP -1; kill -STOP 1`
inside the container).

```console
01:47:27 FREEZE all postgres processes
01:47:53 ready: order-service=1/1 order-service=0/1 product-service=0/1 user-service=1/1
01:48:03 ready: order-service=0/1 product-service=0/1 user-service=1/1
01:48:19 ready: order-service=1/1 product-service=0/1 user-service=1/1
01:48:35 ready: order-service=1/1 product-service=1/1 user-service=1/1   <- recovered while the backends were still frozen
traffic probe: 513 requests ... HTTP 200: 507, HTTP 000: 6
```

**Why it recovered on its own:** `ps` showed every backend in state `T`
(stopped) **except PID 1**, the postmaster. The kernel ignores signals sent
from inside a PID namespace to that namespace's init process, so the
postmaster kept accepting connections. HikariCP timed out the hung pooled
connections (`connection-timeout: 5000`), evicted them, and opened fresh ones
through the running postmaster. Readiness flipped back to UP without any
restart.

**Lesson:** "connections hang" and "database is down" are different
failures. Freezing only the postmaster has no effect at all, because pooled
connections are served by their own backend processes. A drill must state
which failure it simulates.

## Part B: full database outage (game day through Git)

| | |
|---|---|
| **Detection** | All services NotReady within about 30 s, ingress returns 503, `CloudCartPodNotReady` |
| **User impact** | Full outage of every API while the database was down (expected) |
| **Pod restarts** | **0**. Liveness does not depend on the database, so there was no restart storm. |
| **Recovery** | 8 s after PostgreSQL came back, once the revert could actually sync (see the deadlock below) |

Out-of-band changes do not survive here: `kubectl scale sts postgres --replicas=0`
is reverted by Argo CD self-heal in seconds. The outage was therefore
committed to Git (`postgres.replicas: 0`) and ended with `git revert`, which
is how a game day is run in a GitOps setup.

| Time | Event |
|---|---|
| 01:52:59 | Commit `gameday(local): take the database down` pushed |
| 01:53:10 | PostgreSQL StatefulSet scaled to 0 |
| 01:53:37 | All three services `0/1` (readiness `db: DOWN`). Ingress: `users=503 orders=503`. Restart counts unchanged. |
| 01:55:50 | `git revert` pushed: **but nothing happened for 6 minutes** |
| 02:01:42 | Stuck sync operation terminated (`argocd app terminate-op cloudcart-local`) |
| 02:01:50 | Revert synced. `postgres` replicas = 1. |
| 02:01:54 | PostgreSQL ready |
| 02:01:58 | All services Ready, APIs return 200. Restarts still unchanged. |

### Found by drill: the bad sync blocked its own revert

```console
$ kubectl -n argocd get application cloudcart-local -o jsonpath='{.status.operationState.phase} {.status.operationState.message}'
Running waiting for healthy state of apps/Deployment/product-service and 2 more resources
```

The chart has a PostSync smoke-test hook. Argo CD runs PostSync hooks only
after every resource is Healthy, so the sync that removed the database waited
for health that could never come back. While an operation is running, Argo CD
does not start a new one, so **the `git revert` could not sync**.

**Fixes:**

- Runbook step: if a fix in Git does not sync, check `operationState`, and if a sync is stuck waiting for health, run `argocd app terminate-op <app>`.
- Platform fix: `controller.sync.timeout.seconds: "600"` in [`argocd/bootstrap/argocd-values.yaml`](../../argocd/bootstrap/argocd-values.yaml). Argo CD now terminates any sync after 10 minutes, so this cannot block a recovery indefinitely.

## Prevention and design notes

- **Readiness includes the database, liveness does not.** During an outage, pods stop receiving traffic but are not killed and restarted in a loop. That keeps recovery fast (no JVM cold starts) and avoids hammering the database when it returns.
- **Flyway `connect-retries: 10`** (5 s apart): pods that start while the database is unavailable wait instead of crash-looping.
- **On AWS:** RDS Multi-AZ in prod fails over automatically (typically 60 to 120 s). The same readiness behaviour applies, and the Hikari pool reconnects to the new primary through the unchanged DNS name.

## Reproduce

```bash
# Part A (hung connections)
kubectl -n cloudcart exec postgres-0 -- sh -c 'kill -STOP -1; kill -STOP 1'
kubectl -n cloudcart exec postgres-0 -- sh -c 'kill -CONT 1; kill -CONT -1'   # thaw
# Part B (outage): set postgres.replicas: 0 in values-local.yaml, commit, push; then git revert
```
