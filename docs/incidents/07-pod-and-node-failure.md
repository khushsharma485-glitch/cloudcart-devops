# Incident 07: pod failure, node drain, and a NotReady node

## Part A: a pod crashes

| Replicas | Probe result | Recovery |
|---|---|---|
| 1 (product-service) | **62 of 170 requests failed** (HTTP 503 for about 35 s) | ReplicaSet created a replacement immediately; the JVM took about 35 s to become Ready |
| 2, spread over nodes (user-service) | **0 of 143 failed** | the surviving pod served everything while the replacement started |

```console
02:11:08 delete pod product-service-869fdf5dd8-rf5kq (simulated crash)
02:11:08 product-service-...-kxhnd=0/1/ContainerCreating  ...-rf5kq=1/1/Terminating
02:11:15 product-service-...-kxhnd=0/1/Running
02:11:44 product-service-...-kxhnd=1/1/Running
```

**Lesson:** Kubernetes self-heals the *pod*, not the *availability*.
Availability needs at least 2 replicas, `topologySpreadConstraints` across
nodes and zones, and a readiness probe so traffic only reaches ready pods.
Dev and prod use `minReplicas: 2` / `3`. Locally most services run 1 replica
to fit an 8 GB laptop.

## Part B: draining a node (maintenance, upgrade)

user-service: 2 replicas on different nodes, PodDisruptionBudget `minAvailable: 1`.

```console
$ kubectl drain cloudcart-worker --ignore-daemonsets --delete-emptydir-data
evicting pod cloudcart/user-service-757f48f8bb-xql98
evicting pod cloudcart/product-service-869fdf5dd8-kxhnd
...
node/cloudcart-worker drained
traffic probe: 274 requests to http://localhost:8080/api/users over 150s
  HTTP 200: 274
  zero failed requests
```

The PDB lets the eviction API remove a user-service pod only while the other
one is available, so a drain (or an EKS managed node group upgrade, which
drains the same way) cannot take the service down.

## Part C: a node went NotReady (Found by drill: resource exhaustion)

This incident was **not planned**. It happened during the high-CPU drill
followed by a release.

| | |
|---|---|
| **Detection** | `kubectl` timeouts, `TLS handshake timeout` from the API server, node `NotReady`, Calico pods failing probes, blue-green smoke Jobs `DeadlineExceeded` |
| **Impact** | Release 2.5.0 was correctly refused twice (pre-promotion smoke test timed out); the running version kept serving |

### Investigation

```console
$ kubectl get nodes
cloudcart-worker    NotReady
$ docker exec cloudcart-worker free -m
Mem:  7814 total   7261 used   113 free
$ kubectl -n kube-system describe pod calico-node-...
Liveness probe failed: command timed out: "calico component node health --felix-live --bird-live" timed out after 10s
```

### Root cause

The HPA had scaled order-service to 4 replicas during the CPU drill. The next
blue-green release created a preview ReplicaSet at the **same** size (4), so
8 JVMs ran next to the full platform (Argo CD, Prometheus, Loki, Grafana,
Calico) on one 8 GB Docker VM. Memory ran out, the node's own components
(kubelet, Calico) stopped answering probes, and the node went NotReady.

### Resolution

1. Restarted the two worker node containers; all nodes Ready, about 3 GB free.
2. Capped the local HPA at `maxReplicas: 2` and removed the unused Argo CD ApplicationSet controller.
3. Retried the 2.5.0 Rollout (`kubectl argo rollouts retry rollout order-service`). It passed pre-promotion, cut over and passed post-promotion analysis.

### Prevention (production)

- Blue-green needs capacity for **2 x current replicas** during a release. Size node groups for it, or use Cluster Autoscaler / Karpenter so the extra capacity is added on demand.
- Requests must reflect real usage so the scheduler does not overcommit nodes. Kube-reserved and system-reserved memory protect the kubelet.
- Alert on node memory pressure (kube-prometheus-stack ships `KubeNodeNotReady` and `NodeMemoryHighUtilization`).
- The release gate worked as intended: a release cannot promote on an unhealthy cluster.
