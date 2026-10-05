"""Generates dashboards/cloudcart-overview.json.

The dashboard is code: edit this file, run `python monitoring/grafana/generate_dashboard.py`,
commit both. Panels follow the golden signals (traffic, errors, latency,
saturation) plus JVM, Kubernetes and business metrics, and a Loki log panel.
"""
import json
from pathlib import Path

PROM = {"type": "prometheus", "uid": "prometheus"}
LOKI = {"type": "loki", "uid": "loki"}
NS = 'namespace="$namespace"'
APP = 'job=~"$service"'
HTTP = f'{NS}, {APP}, uri!~"/actuator.*"'

panels = []
_id = 0


def panel(title, kind, targets, x, y, w, h, unit=None, **extra):
    global _id
    _id += 1
    p = {
        "id": _id,
        "title": title,
        "type": kind,
        "datasource": targets[0].get("datasource", PROM),
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [{"refId": chr(65 + i), **t} for i, t in enumerate(targets)],
        "fieldConfig": {"defaults": {}, "overrides": []},
        "options": {},
    }
    if unit:
        p["fieldConfig"]["defaults"]["unit"] = unit
    for k, v in extra.items():
        if k == "thresholds":
            p["fieldConfig"]["defaults"]["thresholds"] = {"mode": "absolute", "steps": v}
            p["fieldConfig"]["defaults"]["color"] = {"mode": "thresholds"}
        elif k in ("decimals", "min", "max"):
            p["fieldConfig"]["defaults"][k] = v
        else:
            p[k] = v
    panels.append(p)


def row(title, y):
    global _id
    _id += 1
    panels.append({"id": _id, "type": "row", "title": title, "collapsed": False,
                   "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []})


def q(expr, legend=""):
    return {"expr": expr, "legendFormat": legend, "datasource": PROM}


GREEN, AMBER, RED = "green", "orange", "red"

# ---- headline stats --------------------------------------------------------
row("Overview", 0)
panel("Availability", "stat",
      [q(f'avg(up{{{NS}, {APP}}})')], 0, 1, 4, 4, unit="percentunit", decimals=1,
      thresholds=[{"color": RED, "value": None}, {"color": AMBER, "value": 0.9}, {"color": GREEN, "value": 0.99}])
panel("Requests / min", "stat",
      [q(f'sum(rate(http_server_requests_seconds_count{{{HTTP}}}[5m])) * 60')], 4, 1, 4, 4,
      unit="short", decimals=0, thresholds=[{"color": "blue", "value": None}])
panel("Error rate (5xx)", "stat",
      [q(f'(sum(rate(http_server_requests_seconds_count{{{HTTP}, status=~"5.."}}[5m])) or vector(0))'
         f' / clamp_min(sum(rate(http_server_requests_seconds_count{{{HTTP}}}[5m])), 0.0001)')],
      8, 1, 4, 4, unit="percentunit", decimals=2,
      thresholds=[{"color": GREEN, "value": None}, {"color": AMBER, "value": 0.01}, {"color": RED, "value": 0.05}])
panel("P95 latency", "stat",
      [q(f'histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{{{HTTP}}}[5m])))')],
      12, 1, 4, 4, unit="s", decimals=3,
      thresholds=[{"color": GREEN, "value": None}, {"color": AMBER, "value": 0.25}, {"color": RED, "value": 0.5}])
panel("Pods ready", "stat",
      [q(f'sum(kube_pod_status_ready{{{NS}, condition="true", pod=~"(user|product|order)-service.*"}})')],
      16, 1, 4, 4, unit="short", thresholds=[{"color": RED, "value": None}, {"color": GREEN, "value": 1}])
panel("Firing alerts", "stat",
      [q(f'count(ALERTS{{alertstate="firing", {NS}}}) or vector(0)')], 20, 1, 4, 4, unit="short",
      thresholds=[{"color": GREEN, "value": None}, {"color": RED, "value": 1}])

# ---- golden signals --------------------------------------------------------
row("Traffic, errors, latency", 5)
panel("Request rate by service", "timeseries",
      [q(f'sum by (job) (rate(http_server_requests_seconds_count{{{HTTP}}}[2m]))', "{{job}}")],
      0, 6, 8, 8, unit="reqps")
panel("Error rate by service (5xx ratio)", "timeseries",
      [q(f'(sum by (job) (rate(http_server_requests_seconds_count{{{HTTP}, status=~"5.."}}[2m])) or (sum by (job) (rate(http_server_requests_seconds_count{{{HTTP}}}[2m])) * 0))'
         f' / clamp_min(sum by (job) (rate(http_server_requests_seconds_count{{{HTTP}}}[2m])), 0.0001)', "{{job}}")],
      8, 6, 8, 8, unit="percentunit", min=0, max=1)
panel("Latency p50 / p95 / p99", "timeseries",
      [q(f'histogram_quantile(0.50, sum by (le) (rate(http_server_requests_seconds_bucket{{{HTTP}}}[2m])))', "p50"),
       q(f'histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{{{HTTP}}}[2m])))', "p95"),
       q(f'histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket{{{HTTP}}}[2m])))', "p99")],
      16, 6, 8, 8, unit="s")
panel("Responses by status code", "timeseries",
      [q(f'sum by (status) (rate(http_server_requests_seconds_count{{{HTTP}}}[2m]))', "{{status}}")],
      0, 14, 12, 7, unit="reqps")
panel("Orders placed vs rejected", "timeseries",
      [q(f'sum(rate(cloudcart_orders_placed_total{{{NS}}}[5m])) * 60', "placed / min"),
       q(f'sum by (reason) (rate(cloudcart_orders_rejected_total{{{NS}}}[5m])) * 60', "rejected: {{reason}}")],
      12, 14, 12, 7, unit="short")

# ---- saturation ------------------------------------------------------------
row("Saturation and scaling", 21)
panel("CPU usage vs request (per pod)", "timeseries",
      [q(f'sum by (pod) (rate(container_cpu_usage_seconds_total{{{NS}, container="app"}}[2m]))'
         f' / sum by (pod) (kube_pod_container_resource_requests{{{NS}, container="app", resource="cpu"}})', "{{pod}}")],
      0, 22, 8, 8, unit="percentunit")
panel("Memory working set vs limit (per pod)", "timeseries",
      [q(f'sum by (pod) (container_memory_working_set_bytes{{{NS}, container="app"}})'
         f' / sum by (pod) (kube_pod_container_resource_limits{{{NS}, container="app", resource="memory"}})', "{{pod}}")],
      8, 22, 8, 8, unit="percentunit")
panel("Replicas (HPA current / desired)", "timeseries",
      [q(f'kube_horizontalpodautoscaler_status_current_replicas{{{NS}}}', "{{horizontalpodautoscaler}} current"),
       q(f'kube_horizontalpodautoscaler_status_desired_replicas{{{NS}}}', "{{horizontalpodautoscaler}} desired")],
      16, 22, 8, 8, unit="short")
panel("Container restarts (1h)", "timeseries",
      [q(f'sum by (pod) (increase(kube_pod_container_status_restarts_total{{{NS}, container="app"}}[1h]))', "{{pod}}")],
      0, 30, 8, 7, unit="short")
panel("DB connection pool (active / pending)", "timeseries",
      [q(f'sum by (job) (hikaricp_connections_active{{{NS}, {APP}}})', "{{job}} active"),
       q(f'sum by (job) (hikaricp_connections_pending{{{NS}, {APP}}})', "{{job}} pending")],
      8, 30, 8, 7, unit="short")
panel("Outbound calls from order-service", "timeseries",
      [q(f'sum by (client_name, status) (rate(http_client_requests_seconds_count{{{NS}}}[2m]))', "{{client_name}} {{status}}")],
      16, 30, 8, 7, unit="reqps")

# ---- JVM -------------------------------------------------------------------
row("JVM", 37)
panel("JVM heap used", "timeseries",
      [q(f'sum by (pod) (jvm_memory_used_bytes{{{NS}, {APP}, area="heap"}})', "{{pod}}")],
      0, 38, 8, 8, unit="bytes")
panel("JVM live threads", "timeseries",
      [q(f'sum by (pod) (jvm_threads_live_threads{{{NS}, {APP}}})', "{{pod}}")],
      8, 38, 8, 8, unit="short")
panel("GC pause time", "timeseries",
      [q(f'sum by (pod) (rate(jvm_gc_pause_seconds_sum{{{NS}, {APP}}}[2m]))', "{{pod}}")],
      16, 38, 8, 8, unit="s")

# ---- logs ------------------------------------------------------------------
row("Logs (Loki)", 46)
panel("Errors and warnings", "logs",
      [{"expr": '{namespace="$namespace", app=~"$service", level=~"ERROR|WARN"}', "datasource": LOKI}],
      0, 47, 24, 10, options={"showTime": True, "wrapLogMessage": False, "prettifyLogMessage": False,
               "enableLogDetails": True, "sortOrder": "Descending"})

dashboard = {
    "uid": "cloudcart-overview",
    "title": "CloudCart - Service Overview",
    "tags": ["cloudcart"],
    "timezone": "utc",
    "schemaVersion": 39,
    "refresh": "30s",
    "time": {"from": "now-1h", "to": "now"},
    "templating": {"list": [
        {"name": "namespace", "type": "custom", "query": "cloudcart",
         "current": {"text": "cloudcart", "value": "cloudcart"}, "hide": 0},
        {"name": "service", "type": "query", "datasource": PROM, "multi": True, "includeAll": True,
         "allValue": "user-service|product-service|order-service",
         "query": {"query": 'label_values(up{namespace="$namespace"}, job)', "refId": "svc"},
         "regex": "/.*-service/", "current": {"text": "All", "value": "$__all"}, "refresh": 2},
    ]},
    "panels": panels,
}

out = Path(__file__).parent / "dashboards" / "cloudcart-overview.json"
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(dashboard, indent=2) + "\n", encoding="utf-8")
print(f"wrote {out} ({len(panels)} panels)")
