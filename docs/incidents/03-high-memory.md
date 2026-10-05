# Incident 03: memory exhaustion in order-service (and a JVM sizing bug)

| | |
|---|---|
| **Severity** | SEV-3. Found a real defect. |
| **Detection** | Container restart count, `lastState.terminated.reason`, alerts `CloudCartHighMemory` and `CloudCartJvmHeapHigh` |
| **User impact** | One pod restarted (about 36 s). Requests to that pod failed while it was down. |

## Summary

The chaos endpoint retained memory inside one order-service pod until it ran
out. The first run showed that the container was **OOMKilled by the kernel
(exit 137)** instead of failing with a Java `OutOfMemoryError`. That means no
log line, no heap information, and an alarming signal for what was really an
application problem. The JVM was sized wrong for its container, which was
fixed and verified in release 2.5.0.

## First run (before the fix): 2.2.0 with `MaxRAMPercentage=75`

```console
00:43:47 +200MB: {"retainedMegabytes":200}
order-service-787dc96b6-zkfj9   2m    241Mi
00:43:48 +250MB: connection dropped
00:44:24 recovered
restarts=1 lastState=OOMKilled exitCode=137
```

## Root cause

With a 512 Mi limit and `-XX:MaxRAMPercentage=75`, the heap may grow to
384 Mi. Metaspace (about 80 Mi for a Spring Boot app), thread stacks
(about 1 Mi per thread, with roughly 200 Tomcat threads), code cache and
direct buffers add another 150 to 200 Mi. The process therefore crossed the
cgroup limit **before** the heap was full. The kernel killed it, and the JVM
never got to throw `OutOfMemoryError` or run `ExitOnOutOfMemoryError`.

## Fix

`MaxRAMPercentage=65` in every Dockerfile, so the heap is about 333 Mi on a
512 Mi limit and non-heap memory has room. Released as order-service 2.5.0
through the normal blue-green pipeline.

## Second run (after the fix): 2.5.0

```console
01:41:57 +150MB: {"retainedMegabytes":150}
01:41:58 +150MB: connection dropped
01:42:36 state:
restarts=1 lastState=Error exitCode=3
Terminating due to java.lang.OutOfMemoryError: Java heap space
```

Now the failure is a clean, diagnosable JVM exit (code 3) with the reason in
the logs. Loki keeps it after the pod restarts.

## Prevention

- Rule of thumb: heap is at most about 65% of the memory limit for small (512 Mi to 1 Gi) Spring Boot containers.
- Alerts `CloudCartJvmHeapHigh` (heap above 90% for 10 minutes) and `CloudCartHighMemory` (working set above 85% of the limit) give warning before the kill.
- Follow-up: also set `-XX:+HeapDumpOnOutOfMemoryError` with a dump path on an `emptyDir` sized for it, for production debugging.

## Reproduce

```bash
POD=$(kubectl -n cloudcart get pods -l app.kubernetes.io/name=order-service -o name | head -1)
kubectl -n cloudcart port-forward $POD 18083:8080 &
for mb in 150 150 150; do curl -X POST "localhost:18083/internal/chaos/memory?megabytes=$mb"; done
kubectl -n cloudcart get $POD -o jsonpath='{.status.containerStatuses[0].lastState}'
kubectl -n cloudcart logs $POD --previous | grep OutOfMemoryError
```
