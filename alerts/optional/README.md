# Optional alert packs

Each YAML file in this directory is a self-contained Prometheus alert rule pack. They are **not loaded by default**.

## Activate a pack

```bash
cp alerts/optional/postgres.yaml alerts/
docker compose -f docker-compose.yml -f compose/simple.yml restart prometheus
```

## Deactivate a pack

```bash
rm alerts/postgres.yaml
docker compose -f docker-compose.yml -f compose/simple.yml restart prometheus
```

## Available packs

| Pack | Requires | Purpose |
|------|----------|---------|
| `postgres.yaml` | [`prometheus-postgres-exporter`](https://github.com/prometheus-community/postgres_exporter) sending metrics to obstack | Connection saturation, replication lag, deadlocks, long-running transactions |
| `nginx.yaml` | [`nginx-prometheus-exporter`](https://github.com/nginxinc/nginx-prometheus-exporter) | Up/down, connection waiting ratio |
| `redis.yaml` | [`redis_exporter`](https://github.com/oliver006/redis_exporter) | Up/down, memory pressure, evictions, rejected connections |
| `host.yaml` | The OTel Collector `hostmetrics` receiver (built into obstack v1.1+; nothing extra to deploy) | Host CPU saturation, memory pressure, disk fill, iowait, network errors |
| `api-golden-signals.yaml` | Your app instrumented with OTel HTTP server instrumentation (e.g. `otelhttp` for Go) — no separate exporter needed | 5xx error rate, absolute 5xx count, p95 latency, dependency-pool exhaustion (generic template — read the file's header before activating; the pool-exhaustion rule needs real metric names substituted in) |

## Adding your own packs

Drop a new YAML file (any filename) into `alerts/optional/` for community sharing or `alerts/` for active loading. Validate with `promtool check rules <file>`.
