# obstack

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Stars](https://img.shields.io/github/stars/HameemDakheel/obstack?style=social)](https://github.com/HameemDakheel/obstack/stargazers)
[![Version](https://img.shields.io/badge/version-v1.1.1-blue)](https://github.com/HameemDakheel/obstack/releases)
[![Validate](https://github.com/HameemDakheel/obstack/actions/workflows/validate.yml/badge.svg)](https://github.com/HameemDakheel/obstack/actions/workflows/validate.yml)
[![Docs](https://github.com/HameemDakheel/obstack/actions/workflows/deploy-docs.yml/badge.svg)](https://github.com/HameemDakheel/obstack/actions/workflows/deploy-docs.yml)

> **Production observability for your $20/month VPS.** All 5 signals (logs, metrics, traces, profiles, dashboards). One command. No headache.

---

## What is this?

obstack is an OpenTelemetry-native observability stack you self-host on a single Linux VPS. After one command, you have:

- **Grafana** with 4 pre-built dashboards already populated with live data
- **Prometheus** for metrics
- **VictoriaLogs** for logs (87% less RAM than Loki, 94% lower query latency)
- **Tempo** for distributed traces
- **Pyroscope** for continuous profiling
- **Caddy** with automatic Let's Encrypt TLS
- 12 pre-tuned alert rules ready to fire
- cAdvisor for per-container resource metrics

**Total idle RAM: ~310 MB.** Fits comfortably on a 4 GB VPS with room for your application.

This is **not** an enterprise stack scaled down. It's an observability stack designed from day one for self-hosters: solo devs, indie SaaS founders, the r/selfhosted crowd. If you don't want to operate a Kubernetes cluster but still want production-grade observability, this is for you.

---

## Quick install

```bash
git clone https://github.com/HameemDakheel/obstack.git
cd obstack
cp .env.example .env

# Generate basic-auth hash for OTLP ingestion
docker run --rm caddy:2-alpine caddy hash-password --plaintext 'YOUR_PASSWORD'
# (paste output into .env as BASIC_AUTH_HASH)

# Set ALERT_WEBHOOK_URL in .env to a real Slack/Discord/PagerDuty webhook.
# Its default value routes every alert nowhere, silently — `make verify`
# checks this and will fail until it's set to something real.

make simple
make verify
```

Open `https://localhost/` (or your domain). Login: `admin` / value of `GRAFANA_ADMIN_PASSWORD` in `.env`.

Full walkthrough: **[5-minute Quickstart](docs/quickstart.md)**.

---

## What you get out of the box

Four pre-built dashboards in Grafana's "obstack" folder, populated with **real data** from second 1 (the stack monitors itself):

- **Stack Health** — every component up/down, OTLP ingestion rates by signal, per-component memory
- **Container Metrics** — per-container CPU / RAM / network (cAdvisor)
- **Logs Explorer** — recent logs across the stack and your apps
- **Traces Browser** — service graph + span duration heatmap

Plus 12 pre-tuned alerts (service down, high error rate, disk full, cert expiring, ingestion drop, cardinality explosion, …) and 4 datasources connected and queryable.

---

## How it compares

| | obstack | SigNoz | OpenObserve | Grafana LGTM (DIY) | Datadog |
|---|---------|--------|-------------|---------------------|---------|
| **License** | MIT | Apache 2.0 | AGPL/Apache | AGPL (mixed) | Proprietary |
| **Idle RAM** | ~310 MB | 4-152 GB | ~300 MB | ~3 GB | n/a |
| **Fits 4 GB VPS** | ✅ | ❌ (prod docs say 56 CPU / 152 GB) | ✅ | ❌ | n/a |
| **All 5 signals** | ✅ | ❌ (no profiling) | ❌ (no profiling) | ✅ | ✅ |
| **One-command install** | ✅ `make simple` | ✅ `docker compose up` | ✅ single binary | ❌ DIY assembly | n/a |
| **Auto-provisioned dashboards on first run** | ✅ 4 | partial | partial | ❌ | ✅ |
| **Pre-tuned alert pack** | ✅ 12 | ❌ | ❌ | ❌ | ✅ |
| **Self-hosted** | ✅ | ✅ | ✅ | ✅ | ❌ |
| **Cost predictable** | ✅ ($20 VPS) | ✅ | ✅ | ✅ | ❌ ($1.50-3.50 / GB) |

---

## See it with real microservice traces

Want to see what the stack looks like with a credible microservice workload? Run the [optional OTel demo overlay](demo/README.md):

```bash
make demo
```

This adds 7 services from the [official OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) (Astronomy Shop subset) plus a load generator. The Traces Browser dashboard immediately shows the service graph: frontend → cart → checkout → payment → recommendation. Needs ~8 GB RAM total — use a bigger machine for evaluation.

---

## Architecture sketch

```
Your apps ─→ OTLP gRPC :4317 / HTTP /v1/* ─→ Caddy (TLS + basic auth)
                                                ↓
                                       OTel Collector
                                                ↓
            ┌────────────┬────────────┬─────────┴──────────┐
            ▼            ▼            ▼                    ▼
       Prometheus   VictoriaLogs    Tempo              Pyroscope
            └────────────┴────────────┴────────────────────┘
                                   ↓
                                Grafana ─→ your browser
```

Full detail: **[docs/architecture.md](docs/architecture.md)**.

Why these specific components and not LGTM directly? See:
- [ADR 0001 — Hybrid stack](docs/decisions/0001-hybrid-stack.md)
- [ADR 0004 — No MinIO at Simple profile](docs/decisions/0004-no-minio-for-simple.md)
- [ADR 0005 — Prometheus over Mimir at Simple](docs/decisions/0005-prometheus-not-mimir-for-simple.md)

---

## Profiles

obstack ships as one product with four profiles:

| Profile | Target machine | RAM | Retention | HA | Status |
|---------|----------------|-----|-----------|----|----|
| **Simple** | Single VPS | 4 GB | 7 days | No | ✅ v1.0 |
| Standard | Single 8 GB server | 8 GB | 30 days | No | 🔜 v1.1 |
| Scale | Multi-node | 16 GB+ | 90 days | Yes | 🔜 v2 |
| Enterprise | Regulated / compliance | sized | 1+ year | Full HA + DR | 🔜 v3 |

Full detail: **[docs/profiles.md](docs/profiles.md)**.

---

## Documentation

- **[Quickstart](docs/quickstart.md)** — 5 minutes to populated dashboards
- **[Architecture](docs/architecture.md)** — what's inside, why
- **[Profiles](docs/profiles.md)** — Simple → Standard → Scale → Enterprise
- **[Deploy with Docker Compose](docs/deployment/docker-compose.md)** — full production install
- **[Instrumentation guides](docs/instrumentation/)** — Node.js, Python, Go, Java, Ruby
- **[Operations & Runbooks](docs/operations/)** — backup, upgrade, troubleshooting, incident response
- **[Reference](docs/reference/)** — env vars, ports, volumes, default alerts
- **[Architecture Decision Records](docs/decisions/)** — why these specific choices
- **[Demo overlay](demo/README.md)** — real microservice traces in 1 command

Full docs index: **[docs/README.md](docs/README.md)**.

---

## Contributing

obstack is MIT-licensed and accepts contributions. Common ways to help:

- File issues for bugs you hit
- Send PRs for documentation improvements
- Share custom dashboards via PR (drop a JSON into `configs/grafana/dashboards/`)
- Suggest alert rules via PR (add to `alerts/`)

For larger contributions, please open an issue first to discuss the approach.

---

## Acknowledgements

obstack stands on the shoulders of giants. We don't reinvent storage, query engines, or visualisation — we assemble a polished, resource-frugal product from existing best-of-breed open-source components:

- **[OpenTelemetry](https://opentelemetry.io/)** — the standard we ingest, the protocol we speak.
- **[Grafana](https://grafana.com/)** — the visual moat. Plus Tempo and Pyroscope come from the Grafana ecosystem.
- **[VictoriaMetrics](https://victoriametrics.com/)** — VictoriaLogs makes the "fits on 4 GB" pitch honest.
- **[Prometheus](https://prometheus.io/)** — the metrics standard, used by everyone for a reason.
- **[Caddy](https://caddyserver.com/)** — auto-TLS that "just works."
- **[cAdvisor](https://github.com/google/cadvisor)** — container metrics with no fuss.
- **[Coolify](https://coolify.io)**, **[Dokploy](https://dokploy.com)**, **[CapRover](https://caprover.com)**, and the **Jelastic** ecosystem — the PaaS platforms our beachhead audience runs.
- **[Keep a Changelog](https://keepachangelog.com)** — for the format of our `CHANGELOG.md`.
- **[MkDocs Material](https://squidfunk.github.io/mkdocs-material/)** — the documentation site theme.

If we missed crediting your work, please open an issue.

---

## License

[MIT](LICENSE) © Hameem Dakheel and contributors. Use it, fork it, modify it, sell it. The only thing we ask: keep the copyright notice.
