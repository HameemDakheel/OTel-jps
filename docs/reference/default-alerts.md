# Default alerts

> Source of truth: [`alerts/default-rules.yaml`](https://github.com/HameemDakheel/obstack/blob/main/alerts/default-rules.yaml)

obstack ships with 12 pre-tuned alerts covering the most common production failures. Loaded by
Prometheus on startup, evaluated there — and then bridged to Grafana Alerting's contact points by
one Grafana-managed rule (`configs/grafana/provisioning/alerting/rules.yaml`) that watches
Prometheus's own fired-alert state and re-fires through the configured webhook.

That bridge step matters and is worth naming explicitly: earlier versions of this doc claimed
alerts were "routed via Grafana Alerting to the configured webhook" without anything actually
doing that routing. Confirmed directly (2026-08-24): a guaranteed-firing test alert reached zero
requests at the webhook after 75 seconds, because nothing connected Prometheus's internal alert
state to Grafana's Alertmanager — no Alertmanager service exists in this stack, and Grafana's
Prometheus datasource has no ruler-mirroring configured (that's a Mimir/Cortex/Loki-only feature;
vanilla Prometheus doesn't expose the API surface it needs). The bridge rule above is the fix,
re-verified end to end after fixing it.

---

## Alerts

| Alert | Severity | Expression | Fires after | What it means | Runbook |
|-------|----------|-----------|------------|---------------|---------|
| `ServiceDown` | critical | `up == 0` | 2 m | A scrape target is unreachable | [service-down](../operations/runbooks/service-down.md) |
| `PrometheusTargetMissing` | critical | `absent(up{job="prometheus-self"})` | 5 m | Prometheus isn't scraping itself — meta-monitoring broken | [service-down](../operations/runbooks/service-down.md) |
| `HighIngestionDrop` | warning | `rate(otelcol_receiver_refused_spans_total[5m]) > 0` | 5 m | OTel Collector is refusing spans (backpressure, queue full) | [troubleshooting](../operations/troubleshooting.md) |
| `HighMemoryUsage` | warning | `container_memory / limit > 0.85` | 5 m | A container is approaching its memory limit | [service-down](../operations/runbooks/service-down.md) (if OOM follows) |
| `HighCPUUsage` | warning | `rate(container_cpu_seconds[5m]) > 0.9` | 10 m | A container is sustained at >90% of one core | — |
| `PrometheusHighCardinality` | warning | `prometheus_tsdb_head_series > 1000000` | 10 m | Cardinality explosion — Prometheus memory at risk | [high-cardinality](../operations/runbooks/high-cardinality.md) |
| `TempoIngestErrors` | warning | Tempo distributor can't reach ingesters | 10 m | Trace ingestion path broken | [troubleshooting](../operations/troubleshooting.md) |
| `GrafanaDown` | critical | `up{job="grafana"} == 0` | 2 m | UI is down — users have no access | [service-down](../operations/runbooks/service-down.md) |
| `OTelCollectorQueueFull` | warning | `otelcol_exporter_queue_size / capacity > 0.8` | 5 m | Collector exporter queue >80% full — drops imminent | [troubleshooting](../operations/troubleshooting.md) |
| `ContainerRestartLoop` | critical | `changes(container_start_time_seconds[10m]) > 3` | 0 m | Container has restarted >3× in 10 m | [service-down](../operations/runbooks/service-down.md) |
| `DiskUsageHigh` | warning | Root disk usage >80% | 10 m | Disk filling up | [disk-full](../operations/runbooks/disk-full.md) |
| `VictoriaLogsIngestSlowdown` | warning | Collector accepts logs but VictoriaLogs ingestion is zero | 5 m | Logs pipeline broken | [troubleshooting](../operations/troubleshooting.md) |

---

## Optional alert packs

Extra alert rules ship as drop-in YAML files in `alerts/optional/`. They are not loaded by default — copy the file you want into `alerts/` and restart Prometheus.

| Pack | File | Requires |
|------|------|----------|
| Postgres | `alerts/optional/postgres.yaml` | `prometheus-postgres-exporter` scraping your DB |
| Nginx | `alerts/optional/nginx.yaml` | `nginx-prometheus-exporter` |
| Redis | `alerts/optional/redis.yaml` | `redis_exporter` (oliver006/redis_exporter) |
| Host | `alerts/optional/host.yaml` | None — uses obstack's built-in OTel hostmetrics receiver |
| API golden signals | `alerts/optional/api-golden-signals.yaml` | Your app instrumented with OTel HTTP server instrumentation — no separate exporter. Generic template: read the file's own header before activating, especially for the dependency-pool rule, which ships with deliberately fake placeholder metric names you must replace |

Activation:

```bash
cp alerts/optional/postgres.yaml alerts/
docker compose -f docker-compose.yml -f compose/simple.yml restart prometheus
```

Each pack file's header comment lists the required exporter and what each alert covers. See `alerts/optional/README.md` for full details.

---

## Adding your own alerts

Drop a new YAML file into `alerts/` (any filename, valid Prometheus rule format). Prometheus will pick it up automatically — its `rule_files` glob is `/etc/prometheus/rules/*.yaml`.

After adding a file:

```bash
docker compose -f docker-compose.yml -f compose/simple.yml restart prometheus
```

Verify the new rule loaded:

```bash
docker exec obstack-caddy wget -qO- 'http://prometheus:9090/api/v1/rules' | grep -o '"name":"<your_alert>"'
```

---

## Routing & notifications

Default routing in [`configs/grafana/provisioning/alerting/notification-policies.yaml`](https://github.com/HameemDakheel/obstack/blob/main/configs/grafana/provisioning/alerting/notification-policies.yaml):

- `severity = info` → blackhole receiver (silently dropped)
- everything else → `default-webhook` (configurable via `ALERT_WEBHOOK_URL` env var)

Group settings:
- `group_by: [alertname, severity]`
- `group_wait: 30s`
- `group_interval: 5m`
- `repeat_interval: 4h`

---

## See also

- [`alerts/default-rules.yaml`](https://github.com/HameemDakheel/obstack/blob/main/alerts/default-rules.yaml)
- [Default dashboards](default-dashboards.md)
- [Operations / Troubleshooting](../operations/troubleshooting.md)
