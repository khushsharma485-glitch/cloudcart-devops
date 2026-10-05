# Incident 04: failed deployment, automatic rollback after cutover

| | |
|---|---|
| **Severity** | SEV-2 (drill): live traffic was affected for about 2 minutes |
| **Detection** | Post-promotion analysis (Prometheus 5xx ratio), Grafana error-rate panel |
| **User impact** | 114 of 708 probe requests failed (HTTP 500), **all between 00:30:04 and 00:32:00** |
| **Recovery** | **Automatic.** Traffic was back on the previous version 116 s after the failure began, with no human action. |

## Scenario

"v2 passes its smoke test but fails under real traffic." Release 2.4.0 of
order-service went through the normal blue-green flow. Right after it took
live traffic, a 50% error rate was injected into the new (green) pods, which
simulates a bug that only real request patterns trigger.

## Timeline (traffic probe running throughout)

| Time | Event |
|---|---|
| 00:29:12 | Traffic probe started (5 requests per second through the ingress). Baseline: 0 errors. |
| ~00:29:20 | Commit `deploy(local): order-service 2.4.0` pushed. Argo CD syncs. |
| 00:29:xx | Green ReplicaSet `6999659cf4` created. **Pre-promotion analysis** (smoke test against the preview Service) passed. |
| 00:30:00 | **Cutover:** the active Service now selects green. Blue `787dc96b6` keeps running (`scaleDownDelaySeconds`). |
| 00:30:04 | 50% error injection on green. Post-promotion analysis measurement #1: error rate **0.9%** (pre-injection traffic). |
| 00:31:02 | Measurement #2: **26.9%**. Over the 5% threshold, failure 1 of `failureLimit: 1`. |
| 00:32:00 | Measurement #3: **51.6%**. Failure 2 > limit. `RolloutAborted: Blue/green post-promotion analysis phase error/failed: Metric "error-rate" assessed Failed`. **The active Service switches back to blue `787dc96b6`.** |
| 00:32:00+ | Probe sees only HTTP 200 again. |
| ~00:33 | `git revert` of the 2.4.0 commit pushed, so Git matches reality again. Rollout `Healthy` on 2.2.0. |

```console
00:30:04 Progressing|active=6999659cf4|... post=Running[[0.0093]]
00:31:02 Progressing|active=6999659cf4|... post=Running[[0.0093] [0.2694]]
00:32:00 Degraded|active=787dc96b6|abort=true|RolloutAborted: ... Metric "error-rate" assessed Failed due to failed (2) > failureLimit (1)

traffic probe: 708 requests to http://localhost:8080/api/orders/user/1 over 360s
  HTTP 200: 594
  HTTP 500: 114
  114 failed request(s), first at 00:30:04 HTTP 500
```

## How the rollback works

```
Git commit -> Argo CD sync -> Rollout creates GREEN (preview Service only)
   -> prePromotionAnalysis  (Job: readiness + functional check on preview)   fail -> abort, BLUE untouched
   -> switch active Service to GREEN, keep BLUE running for scaleDownDelaySeconds
   -> postPromotionAnalysis (Prometheus: 5xx ratio <= 5%, 5 x 1 min, failureLimit 1)
                                                                          fail -> abort, active back to BLUE
```

The query (from `helm/cloudcart/templates/analysis.yaml`):

```promql
(sum(rate(http_server_requests_seconds_count{namespace="cloudcart", job="order-service", uri!~"/actuator.*", status=~"5.."}[2m])) or vector(0))
/
clamp_min((sum(rate(http_server_requests_seconds_count{namespace="cloudcart", job="order-service", uri!~"/actuator.*"}[2m])) or vector(0)), 0.000001)
```

## Findings

1. **Blast radius = detection time.** With 1-minute measurements and `failureLimit: 1`, a full failure is visible for about 2 minutes. Prod can tighten this with 30 s intervals or a canary step at 10% traffic before the full switch.
2. **Found by drill: no traffic means no signal.** An earlier attempt passed analysis with error rate `0` because nothing was sending requests to green (the probe script had been deleted by an unrelated revert). The `or vector(0)` makes "no traffic" count as "no errors". Low-traffic services need synthetic traffic during analysis, or a second metric that fails when the request rate is zero.
3. **Rollback state must also go to Git.** After the automatic abort, Git still says 2.4.0, so Argo CD keeps the Rollout in `Degraded/Aborted`. The incident is closed with a `git revert` or the [Rollback workflow](../../.github/workflows/rollback.yml).

## Reproduce

```bash
# 1. steady traffic
tests/load/traffic-probe.sh http://localhost:8080/api/orders/user/1 360 5 &
# 2. release: bump services.order-service.image.tag in values-local.yaml, commit, push
scripts/local-cluster/local-cluster.sh push
# 3. after cutover, break green
G=$(kubectl -n cloudcart get rollout order-service -o jsonpath='{.status.blueGreen.activeSelector}')
kubectl -n cloudcart port-forward $(kubectl -n cloudcart get pod -l rollouts-pod-template-hash=$G -o name | head -1) 18083:8080 &
curl -X POST 'localhost:18083/internal/chaos/errors?rate=0.5'
kubectl argo rollouts -n cloudcart get rollout order-service -w
```
