# Incident 02: high CPU on order-service, absorbed by the HPA

| | |
|---|---|
| **Severity** | SEV-4 (drill). The system handled it with no human action. |
| **Detection** | HPA metrics (`cpu: x%/70%`), Grafana "CPU usage vs request" panel, alert `CloudCartHighCPU` (above 80% of limit for 10 minutes) |
| **User impact** | None observed |

## Summary

A CPU burn of 2 threads for 240 seconds was injected into the single
order-service pod. Average CPU went far above the HPA target of 70% of the
CPU *request*. The HPA added pods within about 30 seconds, then scaled back
down once the load ended.

## Timeline

| Time | Event |
|---|---|
| 00:38:05 | `POST /internal/chaos/cpu?seconds=240&threads=2` on one pod |
| 00:38:27 | 3 pods observed. HPA event: `New size: 3; reason: cpu resource utilization (percentage of request) above target` |
| 00:38:59 | 4 pods observed. HPA event: `New size: 4` (the local maximum at the time) |
| 00:39:36 | All 4 pods Ready. Load is spread over 4 pods. |
| ~00:42 | Burn ends. Average CPU around 7%. |
| +5 min | Scale-down begins: 300 s stabilisation window, then 1 pod per minute. Back to 1 replica. |

## Investigation

```console
$ kubectl -n cloudcart describe hpa order-service | sed -n '/Events:/,$p'
Normal  SuccessfulRescale  5m6s   horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
Normal  SuccessfulRescale  4m36s  horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target

$ kubectl top pods -n cloudcart
```

## How it works

- The HPA targets 70% of the **request** (250m in prod and dev defaults, 100m locally), not the limit.
- Scale-up has no stabilisation window and adds up to 2 pods every 30 s. Scale-down waits 300 s and removes 1 pod per minute, to avoid flapping.
- New pods get traffic only after their readiness probe passes, so a scale-up never sends requests to a JVM that is still booting.

## Follow-up (Found by drill, see [incident 07](07-pod-and-node-failure.md))

Scaling to 4 replicas and then starting a blue-green release, which created 4
more preview pods, put 8 JVMs on an 8 GB Docker VM and exhausted node memory.
The local HPA maximum is now 2. In EKS the node group (and Cluster
Autoscaler or Karpenter) must have headroom for `2 x maxReplicas` during a
blue-green release.

## Reproduce

```bash
POD=$(kubectl -n cloudcart get pods -l app.kubernetes.io/name=order-service -o name | head -1)
kubectl -n cloudcart port-forward $POD 18083:8080 &
curl -X POST 'localhost:18083/internal/chaos/cpu?seconds=240&threads=2'
kubectl -n cloudcart get hpa order-service -w
```
