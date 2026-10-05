# Incident 06: incorrect configuration (wrong dependency URL)

| | |
|---|---|
| **Severity** | SEV-4. Caught before release. |
| **Detection** | Pre-promotion smoke test against the preview (green) Service |
| **User impact** | **None.** 631 of 631 probe requests succeeded. |

## Summary

A configuration change set `USER_SERVICE_URL=http://user-svc`, a typo for
`http://user-service`. The ConfigMap checksum changed, so order-service got a
new blue-green revision. Its pre-promotion check exercises the real
order-to-user call path. That call failed, the release was aborted, and the
old pods, still running with the correct configuration, kept serving.

## Timeline

| Time | Event |
|---|---|
| 02:04:39 | Commit `config(local): point order-service at the user service` pushed |
| 02:04:55 | New ReplicaSet `79bc7bb48d` created behind `order-service-preview` |
| ~02:05:50 | Pre-promotion Job: `POST /api/orders {"userId":999999999,...}` returns **503** instead of the expected 422 |
| 02:05:58 | `RolloutAborted: Blue/green pre-promotion analysis phase error/failed: Metric "smoke-test" assessed Failed` |
| ~02:07 | `git revert` synced. `USER_SERVICE_URL=http://user-service`. Rollout `Healthy`. Full smoke test PASSED (13 checks). |

```console
$ kubectl -n cloudcart logs job/<analysis-job>
{"status":"UP"}
check: POST http://order-service-preview.cloudcart.svc/api/orders (expect HTTP 422)
HTTP 503: {"title":"Service Unavailable","status":503,"detail":"user-service is unavailable","dependency":"user-service"}
```

## Why the check is designed this way (Found while planning this drill)

The original pre-promotion check for order-service was `GET /api/orders/user/0`,
which only touches order-service's own database. It would have **passed**
with a broken dependency URL. It was replaced by a deliberately impossible
order:

- an order for user `999999999` forces order-service to call user-service;
- a healthy path answers **422** ("user does not exist"), a broken one answers **503**;
- nothing is written to any database.

Checks are configured per service in `helm/cloudcart/values.yaml`
(`services.<name>.smoke`: method, path, body, expected status).

## Why readiness did not catch it

Readiness checks only the service's *own* dependencies (its database).
Checking downstream services in readiness is a known anti-pattern: one
slow dependency would take every caller out of rotation and cascade. The
right place for "does the whole call path work" is the release gate, which
is where this was caught.

## Prevention

- Pre-promotion checks test real paths, not just `/health`.
- Configuration is versioned in Git and reviewed in a PR. The ConfigMap checksum annotation means every config change goes through the same blue-green gates as code.
- The order-service client fails fast (2 s connect / 3 s read timeouts) and returns a clear 503 with `"dependency": "user-service"`, which made the diagnosis immediate.
