# Incident 01: order-service 2.1.0 in CrashLoopBackOff (invalid environment variable)

| | |
|---|---|
| **Severity** | SEV-3. A release failed, but users were unaffected. |
| **Duration** | 23:59:54 release to 00:11:48 fully reverted. Zero minutes of user impact. |
| **Detection** | Rollout stuck in `Progressing`, preview pod in CrashLoopBackOff, alert `CloudCartCrashLooping` (fires after 2 minutes) |
| **User impact** | **None.** 569 of 569 probe requests returned HTTP 200 during the release. 266 of 266 during the abort. |

## Summary

Release 2.1.0 of order-service added `DB_PORT: "5432x"` to the service's
environment. Every new pod crashed at startup while building the JDBC URL. The
blue-green strategy kept 100% of traffic on the healthy 2.0.0 version. The
release was then aborted automatically and reverted in Git.

## Timeline (local cluster, IST)

| Time | Event |
|---|---|
| 23:59:54 | Commit `deploy(local): order-service 2.1.0` pushed. Argo CD syncs and Argo Rollouts creates the green ReplicaSet `5776b77b7d`. |
| 00:00:05 | Green pod starts. Blue `677d888b8b` still receives all traffic (`active=677d888b8b`). |
| 00:00:37 | Green pod `CrashLoopBackOff (1)`. Kubernetes backs off: 10 s, 20 s, 40 s, 80 s... |
| 00:04:38 | `CrashLoopBackOff (5)`. Rollout still `Progressing`: **it never aborted on its own** (see root cause 2). |
| 00:09:18 | Rollout guard (added during this incident) aborts the Rollout: `RolloutAborted: ReplicaSet "order-service-5776b77b7d" has timed out progressing`. Green is scaled to 0 and the Rollout is `Degraded`. |
| 00:11:48 | `git revert` of the release commit is synced. Rollout `Healthy` on 2.0.0. |

## Investigation

```console
$ kubectl -n cloudcart get pods -l app.kubernetes.io/name=order-service
order-service-5776b77b7d-7mvdm   0/1   CrashLoopBackOff   5    ...
order-service-677d888b8b-rn9r7   1/1   Running            0    ...

$ kubectl -n cloudcart logs order-service-5776b77b7d-7mvdm --previous | grep -o '"message":"[^"]*'
"message":"Tomcat initialized with port 8080 (http)
"message":"JDBC URL invalid port number: 5432x
"message":"Exception encountered during context initialization - cancelling refresh attempt: ...
"message":"Error starting ApplicationContext. ...

$ kubectl -n cloudcart get pod order-service-5776b77b7d-7mvdm -o jsonpath='{.spec.containers[0].env}'
[... {"name":"DB_PORT","value":"5432x"} ...]
```

(The log lines above were re-captured afterwards by running the same 2.1.0
image with the same environment, because the crashed pod was gone by the time
this report was written.)

`kubectl argo rollouts get rollout order-service` showed the stable/active
ReplicaSet healthy and the preview ReplicaSet progressing, so users were safe
and there was no reason to rush.

## Root cause

1. **Trigger:** the release set `DB_PORT=5432x`. The JDBC URL becomes
   `jdbc:postgresql://postgres:5432x/cloudcart`, the PostgreSQL driver rejects
   it ("JDBC URL invalid port number"), the application context fails, and Spring
   Boot exits. That repeats on every restart.
2. **Why it was not rolled back automatically (Found by drill):** Argo Rollouts
   v1.10 evaluates `progressDeadlineSeconds` for blue-green only after the
   preview ReplicaSet becomes available. In `rollout/sync.go` the progress and
   timeout conditions are not reached while the Rollout waits for the
   preview. `progressDeadlineAbort: true` therefore never fired for a preview
   that never gets ready. Blue stays safe, but nothing rolls back.

## Resolution

- Immediate: [`argocd/platform/rollout-guard`](../../argocd/platform/rollout-guard/rollout-guard.yaml),
  a CronJob with narrowly scoped RBAC (`rollouts` get/list, `rollouts/status`
  patch). Every minute it aborts blue-green updates whose preview has been
  unready for longer than the Rollout's own `progressDeadlineSeconds`.
- Final: `git revert 758ef89`, synced by Argo CD.

## Prevention

- Pre-promotion analysis and the rollout guard mean a crash-looping release can
  never take traffic and is aborted within `progressDeadlineSeconds` plus about 1 minute.
- Configuration is validated at startup: Spring fails fast rather than running half-configured.
- Follow-up: add schema validation for `extraEnv` values in the Helm chart (`values.schema.json`).

## Reproduce

```yaml
# helm/cloudcart/values-local.yaml
services:
  order-service:
    image: { tag: "2.1.0" }
    extraEnv:
      DB_PORT: "5432x"
```

Commit, run `scripts/local-cluster/local-cluster.sh push`, and watch with
`kubectl argo rollouts -n cloudcart get rollout order-service -w`.
