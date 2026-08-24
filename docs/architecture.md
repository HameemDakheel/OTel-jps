# Architecture

> **Audience:** anyone curious about *why* obstack looks the way it does, what's inside, and how data flows through it. Read after [Quickstart](quickstart.md).

---

## At a glance

obstack is an OpenTelemetry-native observability stack that runs as 8 Docker containers on a single VPS. Applications emit telemetry over OTLP, which Caddy proxies (with basic auth) to an OpenTelemetry Collector. The Collector fans out the four signals to four purpose-specific backends. Grafana provides a single UI for querying all of them.

Total idle RAM: **~310 MB** for the entire stack. Designed from the start for a 4 GB VPS, not down-scaled from an enterprise architecture.

---

## Component diagram (data flow)

```
       ┌─────────────────┐
       │  Your apps      │
       │  (Node, Python, │
       │   Go, Java, …)  │
       └────────┬────────┘
                │ OTLP gRPC :4317  /  OTLP HTTP /v1/{traces,metrics,logs}
                ▼
       ┌─────────────────┐
       │     Caddy       │  ◄─── TLS termination (auto Let's Encrypt)
       │  reverse proxy  │  ◄─── Basic auth on /v1/*
       └────────┬────────┘
                │
                ▼
       ┌─────────────────────┐
       │  OTel Collector     │  ◄─── batching, memory limiting,
       │  (contrib)          │       resource detection
       └─┬─────┬─────┬───────┘
         │     │     │
   metrics    │     traces                                  ┌──────────┐
         │   logs    │                                      │ cAdvisor │
         ▼     ▼     ▼                                      └────┬─────┘
  ┌──────────┐ ┌─────────────┐ ┌──────────┐ ┌────────────┐       │
  │Prometheus│ │VictoriaLogs │ │  Tempo   │ │ Pyroscope  │       │
  │ (TSDB)   │ │             │ │          │ │            │       │
  └─────┬────┘ └──────┬──────┘ └─────┬────┘ └──────┬─────┘       │
        │             │              │             │             │
        └────┬────────┴──────────────┴─────────────┘             │
             │  scrape /metrics, /-/ready, etc. ─────────────────┘
             ▼
       ┌─────────────────┐
       │     Grafana     │  ◄── auto-provisioned datasources + dashboards
       │   (the UI)      │  ◄── auto-provisioned alerts + contact points
       └────────┬────────┘
                │
                ▼ via Caddy (TLS + Grafana login)
       ┌─────────────────┐
       │   Your browser  │
       └─────────────────┘
```

**Alerting is two steps, not one** — the diagram's "auto-provisioned alerts" line is Grafana's
side of it, but Grafana doesn't evaluate `alerts/*.yaml` itself. Prometheus does, on its own
(that's what `rule_files` in `configs/prometheus/prometheus.yml` is for), and a single
Grafana-managed rule (`configs/grafana/provisioning/alerting/rules.yaml`) watches Prometheus's own
fired-alert state and re-fires it through Grafana's contact points. See
[Default alerts](reference/default-alerts.md) for the full mechanism and why it needed fixing
(2026-08-24) — an earlier version of this stack had the contact points and webhook correctly
configured with nothing ever feeding them.

---

## Components

| Component | Role | Why this one | Decision |
|-----------|------|--------------|----------|
| **Caddy** v2 | TLS, basic auth, reverse proxy | Auto-Let's Encrypt; 3-line config; what r/selfhosted uses | [ADR 0003](decisions/0003-caddy-not-nginx.md) |
| **OpenTelemetry Collector contrib** | OTLP ingestion + fan-out | Upstream standard; copy-paste from official docs works | [ADR 0002](decisions/0002-otel-collector-not-alloy.md) |
| **Prometheus** | Metrics backend | Universal recognition; remote-write receive enabled | [ADR 0005](decisions/0005-prometheus-not-mimir-for-simple.md) |
| **VictoriaLogs** | Logs backend | 87% less RAM than Loki, 94% lower query latency | [ADR 0001](decisions/0001-hybrid-stack.md) |
| **Grafana Tempo** (monolithic) | Traces backend | Object-store-native; no full-text indexing overhead | [ADR 0001](decisions/0001-hybrid-stack.md) |
| **Pyroscope** | Profiles backend | Native Grafana panel; differentiator vs SigNoz/OpenObserve | [ADR 0001](decisions/0001-hybrid-stack.md) |
| **Grafana** | Single UI | The brand and integration moat | [ADR 0001](decisions/0001-hybrid-stack.md) |
| **cAdvisor** | Per-container metrics | Required for Container Metrics dashboard | Phase 2 |

---

## Signal flow per signal

### Traces

```
App → OTLP HTTP /v1/traces (or gRPC :4317) → Caddy basic auth → OTel Collector
   → batch processor (200 ms / 8192 spans) → otlphttp/tempo exporter → Tempo HTTP /v1/traces
   → Tempo's metrics_generator emits span-metrics → remote_write to Prometheus
```

Tempo's `metrics_generator` is what powers the Traces Browser dashboard's latency heatmap (`traces_spanmetrics_latency_bucket`).

### Metrics

```
App → OTLP HTTP /v1/metrics → Caddy → OTel Collector
   → batch processor → prometheusremotewrite exporter → Prometheus :9090/api/v1/write
   → TSDB on filesystem
```

Prometheus is started with `--web.enable-remote-write-receiver` so it can accept push from the Collector.

### Logs

```
App → OTLP HTTP /v1/logs → Caddy → OTel Collector
   → batch processor → otlphttp/logs exporter → VictoriaLogs /insert/opentelemetry
   → VictoriaLogs storage on filesystem
```

VictoriaLogs uses LogsQL for queries. The Logs Explorer dashboard uses the `victoriametrics-logs-datasource` plugin.

### Profiles

At v1, applications push profiles directly to Pyroscope's native ingest endpoint (`/ingest`) rather than through the OTel Collector. The OTel profiles signal is still maturing and the Collector contrib distribution doesn't yet have a stable named profiles pipeline. This is documented in [ADR 0001](decisions/0001-hybrid-stack.md) and may change in a later release.

```
App with Pyroscope SDK → POST /ingest → Pyroscope storage on filesystem
```

The Pyroscope datasource in Grafana is auto-provisioned and queries Pyroscope directly. Tempo's `tracesToProfilesV2` correlation is configured so jumping from a span to its CPU profile works in the Traces Browser dashboard.

### Self-monitoring

Every component emits its own metrics, and Prometheus has scrape jobs for all of them:

```yaml
scrape_configs:
  - job_name: prometheus-self
    static_configs: [{ targets: ['localhost:9090'] }]
  - job_name: otel-collector
    static_configs: [{ targets: ['otel-collector:8888'] }]
  - job_name: tempo
    static_configs: [{ targets: ['tempo:3200'] }]
  - job_name: pyroscope
    static_configs: [{ targets: ['pyroscope:4040'] }]
  - job_name: grafana
    static_configs: [{ targets: ['grafana:3000'] }]
  - job_name: cadvisor
    static_configs: [{ targets: ['cadvisor:8080'] }]
```

This is why dashboards have data on first launch — no synthetic seeder needed. Documented in [ADR 0006](decisions/0006-self-monitoring-not-seeder.md).

---

## Storage

At Simple profile, all backends use **filesystem storage** in named Docker volumes:

| Volume | Container | Backend |
|--------|-----------|---------|
| `prometheus_data` | obstack-prometheus | Prometheus TSDB |
| `victorialogs_data` | obstack-victorialogs | VictoriaLogs storage |
| `tempo_data` | obstack-tempo | Tempo blocks + WAL |
| `pyroscope_data` | obstack-pyroscope | Pyroscope DB + filesystem store |
| `grafana_data` | obstack-grafana | Grafana DB + plugins + sessions |
| `caddy_data` | obstack-caddy | Let's Encrypt certs |
| `caddy_config` | obstack-caddy | Caddy config cache |

No MinIO. Documented in [ADR 0004](decisions/0004-no-minio-for-simple.md). MinIO returns at the Scale profile when multiple replicas need shared storage.

---

## Authentication

Two authentication boundaries:

1. **Caddy basic auth on OTLP ingestion paths** (`/v1/*` routes). Username comes from `BASIC_AUTH_USER` env var; password is bcrypt-hashed in `BASIC_AUTH_HASH`. Applications send `Authorization: Basic <base64>` header.

2. **Grafana login on UI**. Username/password from `GRAFANA_ADMIN_USER`/`GRAFANA_ADMIN_PASSWORD`. First-launch password change recommended. Anonymous access disabled.

Internal communication between containers (Collector → backends, Grafana → backends) is over the `obs-net` Docker bridge — *not* exposed to the outside world. No internal TLS at Simple profile; revisit at Enterprise.

---

## Resource budget (Phase 2 measurements)

| Container | Idle RAM | Limit |
|-----------|---------|-------|
| Caddy | 14 MB | 128 MB |
| OTel Collector | 34 MB | 256 MB |
| Prometheus | 54 MB | 384 MB |
| VictoriaLogs | 4 MB | 256 MB |
| Tempo | 27 MB | 512 MB |
| Pyroscope | 70 MB | 384 MB |
| Grafana | 68 MB | 256 MB |
| cAdvisor | 42 MB | 128 MB |
| **Total** | **~313 MB** | — |

Adding ~700 MB for OS + Docker overhead → **~1 GB system idle on a 4 GB VPS**, leaving ~3 GB headroom for query bursts and the user's actual application workload.

---

## What's deliberately NOT in v1

- **Multi-tenancy** — single-tenant only at Simple. Multi-tenancy moves to Enterprise.
- **HA / replication** — single-node. HA at Scale profile.
- **eBPF auto-instrumentation** — that's [Coroot's](https://coroot.com) lane.
- **Custom UI** — Grafana is the UI. We don't reinvent that.
- **AI triage / anomaly detection** — flagged as v2/v3 candidate.
- **Datadog migrator** — flagged as v2/v3 candidate.

See the [Spec](superpowers/specs/2026-04-25-obstack-redesign.md) §10 for the full open-questions list.

---

## Profiles preview

obstack has four profiles. Only **Simple** ships in v1:

| Profile | Target machine | RAM | Retention | HA | Status |
|---------|----------------|-----|-----------|----|----|
| Simple | Single VPS | 4 GB | 7 d | No | ✅ v1.0 |
| Standard | Single beefy server | 8 GB | 30 d | No | 🔜 v1.1 |
| Scale | Multi-node | 16 GB+ | 90 d | Yes | 🔜 v2 |
| Enterprise | Regulated / compliance | sized | 1 yr+ | Full HA + DR | 🔜 v3 |

Full detail: [Profiles](profiles.md).
