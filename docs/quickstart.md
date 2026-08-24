# Quickstart

> **What you'll need:** Docker 24+ and Docker Compose v2 · 4 GB RAM · optional public domain
> **Time to complete:** ~5 minutes

This guide gets a complete observability stack running on a fresh Linux VPS in 5 minutes. By the end you'll have Grafana open in your browser with 4 dashboards already populated with live data.

---

## What you're about to install

obstack is a single-VPS observability stack. After this quickstart you'll have running:

- **Caddy** — TLS termination, basic auth on ingestion, reverse proxy
- **OpenTelemetry Collector** — receives OTLP, fans out to backends
- **Prometheus** — metrics
- **VictoriaLogs** — logs
- **Tempo** — traces
- **Pyroscope** — continuous profiling
- **Grafana** — single UI for all four signals
- **cAdvisor** — per-container resource metrics

Total idle RAM: ~310 MB (verified on Phase 2). Comfortable on a 4 GB VPS with room for your application.

---

## Step 1 — Clone the repo

```bash
git clone https://github.com/HameemDakheel/obstack.git
cd obstack
cp .env.example .env
```

Open `.env` in your editor. You need to change four things to get started:

```dotenv
DOMAIN=localhost                              # leave as-is for local dev; set to your real domain in prod
GRAFANA_ADMIN_PASSWORD=changeme               # change to anything
BASIC_AUTH_HASH=...                           # generated in step 2
ALERT_WEBHOOK_URL=https://example.invalid/alert   # your real Slack/Discord/PagerDuty webhook — see below
```

**Don't skip `ALERT_WEBHOOK_URL`.** Its default value is a placeholder that accepts every alert
and delivers none of them — no error, no bounce, nothing. A stack left on this default looks
completely healthy while every alert silently disappears. `make verify` (Step 4) checks for this
default specifically and will fail until you replace it with a real webhook URL.

---

## Step 2 — Generate a basic-auth hash

The OTLP ingestion endpoints (`/v1/traces`, `/v1/metrics`, `/v1/logs`) are protected by basic auth at the Caddy layer. Generate a bcrypt hash for the password your applications will use:

```bash
docker run --rm caddy:2-alpine caddy hash-password --plaintext 'YOUR_PASSWORD'
```

Copy the output (starts with `$2a$14$...`) into `.env` as `BASIC_AUTH_HASH`. The default username is `ingest` (configurable via `BASIC_AUTH_USER`).

---

## Step 3 — Start the stack

```bash
make simple
```

That's it. The stack pulls images (~1 GB total, first time only) and starts 8 containers. After ~30 seconds, every component is healthy.

If you don't have `make` installed, the equivalent is:

```bash
docker compose -f docker-compose.yml -f compose/simple.yml up -d
```

---

## Step 4 — Verify

```bash
make verify
```

Expected output:

```
── obstack stack verification ──────────────────
  PASS caddy (probe container running)
  PASS otel-collector
  PASS prometheus
  PASS victorialogs
  PASS tempo
  PASS pyroscope
  PASS grafana
  PASS alert-webhook (configured)

── 8 passed, 0 failed ─────────────────────────
✅ All checks passed.
```

If you skipped setting `ALERT_WEBHOOK_URL` in Step 1, the last line reads
`FAIL alert-webhook (ALERT_WEBHOOK_URL is unset or still the placeholder — every alert will fire
into a void)` and the script exits non-zero — go back and set it, then re-run `make verify`.

If anything else fails, see [Troubleshooting](operations/troubleshooting.md).

---

## Step 5 — Open Grafana

Visit `https://<DOMAIN>/` in your browser. With `DOMAIN=localhost`, the cert will be self-signed — accept the warning for dev work.

Login:
- **Username:** `admin`
- **Password:** the value of `GRAFANA_ADMIN_PASSWORD` in `.env`

In the left sidebar, click **Dashboards** → **obstack**. You'll see four pre-built dashboards already populated with **real data** — the stack monitoring itself:

1. **Stack Health** — component up/down, ingestion rates, memory per component
2. **Container Metrics** — per-container CPU/RAM/network (cAdvisor)
3. **Logs Explorer** — recent logs from all services
4. **Traces Browser** — service graph + span latency heatmap

Take 30 seconds to click through them — this is what your apps' telemetry will look like once they're instrumented.

---

## Step 6 — Send your first telemetry from an app

Now point your application at the OTLP endpoints. Pick your language:

- [Node.js](instrumentation/nodejs.md)
- [Python](instrumentation/python.md)
- [Go](instrumentation/go.md)
- [Java](instrumentation/java.md)
- [Ruby](instrumentation/ruby.md)

Each guide has a copy-paste-runnable code sample that emits a test trace, metric, and log within minutes.

The endpoints your application will use:

| Signal | Endpoint | Protocol |
|--------|----------|----------|
| Traces | `https://<DOMAIN>/v1/traces` | OTLP HTTP |
| Metrics | `https://<DOMAIN>/v1/metrics` | OTLP HTTP |
| Logs | `https://<DOMAIN>/v1/logs` | OTLP HTTP |
| All (gRPC) | `<DOMAIN>:4317` | OTLP gRPC |

Authentication: HTTP Basic auth (username from `BASIC_AUTH_USER`, password from your hash plaintext). For OTLP SDKs, set the env var:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT="https://<DOMAIN>"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n 'ingest:YOUR_PASSWORD' | base64)"
```

---

## What's next

- **Want to see realistic microservice traces?** Run `make demo` to spin up the [OTel demo overlay](https://github.com/HameemDakheel/obstack/blob/main/demo/README.md). Requires ~8 GB RAM total.
- **Operating the stack day-to-day?** Read the [Operations](operations/troubleshooting.md) docs.
- **Want to know why we picked these specific components?** See the [Architecture Decision Records](decisions/0001-hybrid-stack.md).
- **Need to scale beyond 4 GB?** See [Profiles](profiles.md).

---

## Cleanup

When you're done experimenting:

```bash
make stop                # stops the stack, keeps data on disk
make clean               # stops the stack AND deletes all telemetry data (interactive)
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `make verify` reports a service down | Container crashed during startup | `docker logs obstack-<name>` to see why |
| Browser warns about untrusted cert | Using `DOMAIN=localhost` (self-signed) | Accept the cert for dev; use a real domain in prod |
| Grafana login fails | Password mismatch in `.env` | Check `GRAFANA_ADMIN_PASSWORD`, restart Grafana |
| OTLP requests get 401 | Basic auth header wrong | Re-encode `username:password` as base64; ensure `Authorization: Basic <base64>` header |
| `make verify` reports OTLP test fails | Basic auth hash doesn't match plaintext | Re-generate hash with the password you're using |
| `make verify` reports `FAIL alert-webhook` | `ALERT_WEBHOOK_URL` in `.env` is unset or still `https://example.invalid/alert` | Set it to a real Slack/Discord/PagerDuty webhook URL, then re-run `make verify` — every alert is silently going nowhere until you do |

For more, see the [full troubleshooting guide](operations/troubleshooting.md).
