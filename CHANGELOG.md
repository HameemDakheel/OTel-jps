# Changelog

All notable changes to obstack are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned
- Real screenshots in README and docs (manual capture post-launch)
- Submission of obstack templates to Coolify Templates / Dokploy Templates / CapRover One-Click Apps registries
- OAuth2 login for Grafana (deferred from v1.1; version number not yet assigned — v1.2.0 shipped
  a different set of work first, see below)

---

## [v1.2.0] — 2026-08-24

Browser RUM, application-level alerting (with a real delivery bug found and fixed), a generic
API golden-signals alert pack, and documented + verified MCP integration. Six tasks, driven by a
pre-deployment review that found real gaps rather than assumed the stack was ready.

### Added
- **Browser RUM via Grafana Faro** — new `faro` receiver on the OTel Collector (own port, 8027),
  a dedicated public Caddy route with a CORS-preflight fix (an unconditional `basic_auth`
  directive answers a browser's `OPTIONS` preflight with 401, silently breaking the whole feature
  for every real browser — the same defect class as a real incident on unrelated production
  infrastructure), a new dashboard (`configs/grafana/dashboards/frontend-rum.json` — signal
  volume by kind, JS error rate, the four Core Web Vitals, recent activity, an `app` template
  variable so it works for any hosted application), and a full setup guide
  (`docs/instrumentation/browser.md`). Required bumping the pinned OTel Collector image
  `0.111.0` → `0.153.0` — the faro receiver doesn't exist at all in `0.111.0` — which also forced
  a `service.telemetry.metrics` schema migration.
- **Generic API golden-signals alert pack** (`alerts/optional/api-golden-signals.yaml`) — 5xx
  rate, 5xx absolute count, p95 latency with a minimum-sample-count guard, and a parameterized
  dependency-pool-exhaustion template. Metric names are evidence-grounded (the pre-1.23 OTel HTTP
  semantic convention, confirmed against a real production alert rule using the same shape), not
  guessed.
- **Prometheus-to-Grafana alert bridge**
  (`configs/grafana/provisioning/alerting/rules.yaml`) — see Fixed below; this is the mechanism
  that makes every alert this project ships (old and new) actually reach anyone.
- **Grafana MCP integration guide** (`docs/integrations/mcp.md`, new "Integrations" nav section)
  — documents and verifies running the official `grafana/mcp-grafana` server against a
  self-hosted obstack Grafana instead of Grafana Cloud. No obstack code changed; verified for
  real against a running instance (dashboard search, a live PromQL query, and alert-rule listing
  all confirmed working through the actual MCP protocol), not just described from the upstream
  README.
- CI now validates every optional alert pack (previously only the default pack was checked) and
  every Grafana alerting/dashboard provisioning YAML file.

### Fixed
- **Alerts fired in Prometheus but reached nobody** — the most significant finding of this
  release. There was no Alertmanager service and no ruler-mirroring wired into Grafana's
  Prometheus datasource, so every alert this project has ever shipped — the 12 default rules,
  every optional pack, old and new — evaluated inside Prometheus's own internal state and never
  reached Grafana's contact points, regardless of whether `ALERT_WEBHOOK_URL` held a real URL or
  the placeholder. Proved directly with a guaranteed-firing test alert and a listener at the
  configured webhook: zero requests after 75 seconds. Fixed with one Grafana-managed alert rule
  that watches Prometheus's own fired-alert state and re-fires it through the contact points
  Task 3 (v1.1.1-era work) already built — no new service required.
- **`scripts/verify_stack.sh`'s alert-webhook check could fail forever even when correctly
  configured** — it read `ALERT_WEBHOOK_URL` from the calling shell's environment, but neither
  the script nor `make verify` ever sources `.env`, so a real webhook URL sitting in `.env` never
  reached the check the documented, normal way a user runs `make verify`. Fixed by reading the
  value from the live Grafana container's own environment instead — also more correct than
  reading `.env`, since it reflects what's actually deployed.
- CI's OTel Collector validation step had been failing on every push since the `hostmetrics`
  receiver landed (four months prior) — it never supplied the `/hostfs` mount that receiver's
  `root_path` needs. Fixed.
- A stale compose-merge check in CI referenced `compose/otel-demo.yml`, deleted in `809fa61` and
  replaced by a separate compose project — the reference had been dead since. Fixed.
- Eight pre-redesign dead config files (`configs/loki.yaml`, `configs/mimir.yaml`, and others
  from before the Loki/Mimir → VictoriaLogs/Prometheus redesign), unreferenced by any compose
  file, confirmed by repo-wide grep before deletion.

### Changed
- OTel Collector image pinned to `0.153.0` (from `0.111.0`) — see Added, RUM.
- The repo's local `CLAUDE.md` (untracked, never committed — so this doesn't show as a diff)
  described a fully superseded architecture and was rewritten from the real, current files.

---

## [v1.1.1] — 2026-04-29

Demo redesign + Caddy OTLP routing fix + Astronomy Shop dashboard, recipes, tutorial, and CONTRIBUTING.

### Fixed
- **Caddyfile `/v1/*` routing** — `handle_path` was stripping the `/v1` prefix before reverse-proxying to otel-collector:4318, so OTLP requests landed as `/traces`/`/metrics`/`/logs` and 404'd. Switched to `handle` so the prefix is preserved. The public OTLP path now actually works.
- **Caddy hostname matching** — added a second site block for `caddy` / `obstack-caddy` (Docker-internal aliases) with `tls internal`, so in-network clients on `obs-net` can post OTLP without Host-header tricks. Never exposed publicly.

### Added
- **Astronomy Shop demo dashboard** (`configs/grafana/dashboards/demo-app.json`) — 13 panels using `traces_span_metrics_*` so every demo SDK contributes: request/error rate, p95/p99 latency by service, top slowest spans, top erroring spans, span throughput by kind, demo logs panel.
- **Demo tutorial** (`docs/operations/demo-tutorial.md`) — 7-step hands-on guide: credential setup, bring-up, trace→span→logs drill-down, failure injection, alert pack activation, cleanup.
- **Demo recipes** (`docs/operations/demo-recipes.md`) — 8 hands-on scenarios covering all 15 OTel demo feature flags (`cartFailure`, `paymentFailure` percentage variants, `productCatalogFailure`, `recommendationCacheFailure`, `adHighCpu`, `adManualGc`, `adFailure`, `imageSlowLoad`, `emailMemoryLeak`, `kafkaQueueProblems`, `loadGeneratorFloodHomepage`, `failedReadinessProbe`, `paymentUnreachable`, `llmInaccurateResponse`, `llmRateLimitError`) plus Locust load-generator usage.
- **CONTRIBUTING.md** — dev setup, repo layout, conventions for adding dashboards/alerts/configs, Conventional Commits, PR process, release flow, bug-report template, code of conduct.

### Changed
- **`examples/otel-demo/` redesigned end-to-end** — replaces the v1.1.0 7-service subset (which couldn't actually run because OTel demo's frontend/checkout have hard deps on kafka/postgres/email/etc.) with the full official OTel demo v2.2.0 cloned at runtime + a thin override layer. The override disables jaeger/grafana/prometheus/opensearch (obstack does those), reroutes the bundled otel-collector to obstack via OTLP/HTTP+Basic-auth, joins `obs-net`, and patches a few env-var gaps in upstream's compose. `scripts/demo-up.sh` auto-clones upstream on first run.
- `examples/otel-demo/upstream/` and `examples/otel-demo/.env` are now `.gitignore`d (cloned at runtime; contains plaintext credentials).

### Migration

If you were using the v1.1.0 demo (`make demo-up`), nothing changes for you — the same command works, but the underlying compose project is different. State from the old demo is preserved (volumes); just re-run `make demo-up`. First post-upgrade run will clone upstream into `examples/otel-demo/upstream/` and pull demo images (~5 min).

If you wrote custom dashboards or alerts assuming the old 7-service subset, expand them — there are 17 services emitting telemetry now.

---

## [v1.1.0] — 2026-04-27

Standard profile, host metrics, opinionated alert packs, demo redesign.

### Added
- **Standard profile** (`compose/standard.yml`) — 8 GB host target, 30-day retention. Bumped resource limits per service. New `make standard`, `make standard-stop`, `make standard-logs`, `make standard-verify`.
- **OTel Collector `hostmetrics` receiver** — host-level CPU/RAM/disk/network/load metrics. otel-collector now bind-mounts `/` as `/hostfs:ro,rslave`. No new container.
- **Host Health dashboard** (`configs/grafana/dashboards/host-health.json`) — 6 panels: CPU by state, memory by state, filesystem usage, load average, network throughput, disk I/O.
- **Optional alert packs** (`alerts/optional/{postgres,nginx,redis,host}.yaml`) — opt-in via `cp` to `alerts/`. Each pack documents its required exporter.
- **`alerts/optional/README.md`** — activation/deactivation instructions and pack catalogue.
- **`examples/`** top-level directory for standalone test workloads.
- **`examples/otel-demo/`** — standalone compose project that runs the official OTel demo subset and emits OTLP to obstack's *public* endpoint (`https://${DOMAIN}/v1/...`) with HTTP Basic auth — same path real customer apps use. Includes `.env.example` and a rewritten `README.md`.
- **`scripts/demo-up.sh`** — helper that loads `examples/otel-demo/.env`, computes the Basic-auth header, and runs `docker compose up -d`.
- **Makefile targets** `demo-up`, `demo-down`, `demo-logs`.
- **Standard-profile retention notes** in `.env.example`.
- **Documentation** — Standard profile fully documented in `docs/profiles.md`; Simple→Standard upgrade procedure in `docs/operations/upgrade.md`; optional alert packs in `docs/reference/default-alerts.md`.

### Changed
- `docker-compose.yml` — `otel-collector` service mounts `/:/hostfs:ro,rslave` so the hostmetrics receiver can read host metrics from inside Docker.
- `configs/otel-collector/config.yaml` — hostmetrics receiver added to the metrics pipeline.
- `docs/deployment/docker-compose.md` — host-sizing recommendations updated for Standard profile and Standard+demo.

### Removed (BREAKING for v1.0.x users using `make demo`)
- **`compose/otel-demo.yml`** — the internal-network demo overlay is replaced by the standalone `examples/otel-demo/` compose project. The old approach used internal Docker hostnames and bypassed Caddy/basic-auth — it was a false-positive test. The new approach exercises the production OTLP path.
- **`demo/` directory** — its content moved into `examples/otel-demo/README.md`.
- **`make demo`, `make demo-stop`, `make demo-logs`** Makefile targets — replaced by `make demo-up`, `make demo-down`, `make demo-logs`. Different semantics: the new targets run a standalone external client; the old ones layered the demo into obstack's compose.

### Migration from v1.0.x

If you were running `make demo` from v1.0.x:

```bash
# 1. Stop and discard the old demo overlay (this used the same containers
#    obstack does, so be careful — only run if you're not running obstack).
docker compose -f docker-compose.yml -f compose/simple.yml down

# 2. Pull v1.1.0.
git pull
git checkout v1.1.0

# 3. Bring obstack back up (no demo).
make simple

# 4. Configure the standalone demo client.
cd examples/otel-demo
cp .env.example .env
# Edit .env to set DEMO_OBSTACK_ENDPOINT and credentials.
cd -

# 5. Bring up the demo as a separate stack.
make demo-up
```

The demo's apps now run as a separate Docker compose project, talking to obstack over the public OTLP path — exactly how a real customer's apps would integrate.

---

## [v1.0.1] — 2026-04-27

The rename release. No functional changes for Simple-profile users beyond the project identifier; one breaking change in container names.

### Changed
- **Project renamed from `OTel-jps` to `obstack`.** GitHub repo renamed via `gh repo rename obstack`; auto-redirect from old URLs is in place. All in-repo references (~70 files) updated: README, CHANGELOG, all docs, all templates (Coolify/Dokploy/CapRover/Jelastic), launch drafts, MkDocs `site_name`, `site_url`, `repo_url`. Spec/plan filenames updated to match (`2026-04-25-obstack-redesign.md`, `2026-04-25-obstack-redesign-INDEX.md`). Local workspace path on the maintainer's machine (`/home/hameem/workspace/OTel-jps`) intentionally left unchanged — it's filesystem-only, not user-facing.

### Breaking
- **Container names changed** from `otel-jps-<service>` → `obstack-<service>`. Existing v1.0.0 deployments need a one-time migration: `docker rm -f $(docker ps -a --filter 'name=otel-jps-' -q)` followed by `make simple`. **Volumes (data) are preserved** because volume names did not change.

---

## [v1.0.0] — 2026-04-25

The first production release. Combines the work from all alpha milestones (`alpha.1` through `alpha.4`) plus CI/CD and launch readiness from Phase 5.

### Added
- `LICENSE` file (MIT).
- `.github/workflows/validate.yml` — CI on every push: validates YAML/JSON configs, docker-compose merges, Caddyfile, OTel Collector config, Prometheus alert rules, bash scripts, MkDocs strict build, and shellcheck.
- `.github/workflows/deploy-docs.yml` — CD that builds the MkDocs site and deploys to GitHub Pages on push to `main` when `docs/` or `mkdocs.yml` change.
- `CHANGELOG.md` (this file).
- `launch/` directory with launch announcement drafts (Show HN, r/selfhosted, Twitter).
- `assets/screenshots/README.md` — capture instructions for the 4 dashboards plus terminal output.

### Changed
- README polish — acknowledgements section, status badge, version badge bumped to `v1.0.0`.

### Removed
- Legacy `.github/workflows/deploy.yml` (LGTM-stack era; references defunct components).

---

## [v1.0.0-alpha.4] — 2026-04-25

**Phase 4: PaaS templates and deployment guides.**

### Added
- `templates/coolify/` — Coolify-tuned compose, template metadata JSON, README.
- `templates/dokploy/` — Dokploy template with `${randomPassword}` and `${input}` env-var prompting, compose, README.
- `templates/caprover/` — Multi-service One-Click App YAML (8 separate CapRover apps), captain-definition stub, README.
- `docs/deployment/coolify.md` — Coolify deployment guide.
- `docs/deployment/dokploy.md` — Dokploy deployment guide.
- `docs/deployment/caprover.md` — CapRover deployment guide (most complex due to multi-app pattern).
- `docs/deployment/jelastic.md` — Jelastic deployment guide.
- `mkdocs.yml` — Coolify, Dokploy, CapRover, Jelastic added to deployment nav.

### Changed
- `templates/jelastic/manifest.jps` — completely rewritten for the new hybrid stack. Removed all MinIO/Mimir/Loki/Alloy references. Now delegates installation to `make simple` and verification to `./scripts/verify_stack.sh`.
- `templates/jelastic/linker.jps` — updated to inject OTLP env vars pointing at the Caddy-fronted public domain with HTTP Basic auth headers (instead of the old direct-to-Alloy port 4317 path).

---

## [v1.0.0-alpha.3] — 2026-04-25

**Phase 3: Documentation site, ADRs, instrumentation guides, runbooks.**

### Added
- 6 ADRs in `docs/decisions/` — hybrid stack, OTel Collector vs Alloy, Caddy vs Nginx, no MinIO at Simple, Prometheus vs Mimir at Simple, self-monitoring vs synthetic seeder.
- Foundation docs: `docs/quickstart.md`, `docs/architecture.md`, `docs/profiles.md`.
- 5 instrumentation guides under `docs/instrumentation/`: Node.js, Python, Go, Java, Ruby.
- Operations docs: `docs/operations/backup-restore.md`, `upgrade.md`, `troubleshooting.md`.
- 4 incident runbooks: `disk-full.md`, `service-down.md`, `cert-renewal.md`, `high-cardinality.md`.
- 5 reference docs in `docs/reference/`: `env-vars.md`, `ports.md`, `volumes.md`, `default-alerts.md`, `default-dashboards.md`.
- `docs/deployment/docker-compose.md` — canonical "fresh VPS" install guide.
- `docs/README.md` — documentation site index.
- `mkdocs.yml` — MkDocs Material site configuration.

### Changed
- `README.md` — fully rewritten with the wedge pitch, comparison table vs SigNoz/OpenObserve/LGTM-DIY/Datadog, and links into the new docs tree.

---

## [v1.0.0-alpha.2] — 2026-04-25

**Phase 2: Stack polish — dashboards, alerts, demo, observability.**

### Added
- `cadvisor` service — per-container CPU/RAM/network metrics, scraped by Prometheus.
- 4 default Grafana dashboards in `configs/grafana/dashboards/`: Stack Health, Container Metrics, Logs Explorer, Traces Browser. Auto-provisioned into the "obstack" folder.
- 12 default Prometheus alert rules in `alerts/default-rules.yaml` covering service down, high error rate, cardinality explosion, disk usage, and more.
- Grafana alerting provisioning: contact point + notification policy (`configs/grafana/provisioning/alerting/`).
- `compose/otel-demo.yml` — opt-in OTel demo overlay (curated 7-service Astronomy Shop subset) for evaluation and screenshots.
- `demo/README.md` — instructions for running the OTel demo overlay.
- Makefile shortcuts: `make demo`, `make demo-stop`, `make demo-logs`.
- `ALERT_WEBHOOK_URL` env var (configurable Slack/Discord/PagerDuty webhook).

### Changed
- `Makefile`: `make simple` now prints the Grafana URL hint after starting.
- `configs/grafana/provisioning/dashboards/dashboards.yaml`: `foldersFromFilesStructure` set to `false` so the named "obstack" folder takes effect (was previously `true`, which silently overrode the named folder).

### Fixed
- Removed misleading `wget` healthchecks for distroless containers (Caddy, OTel Collector, VictoriaLogs, Pyroscope) — they showed `(unhealthy)` in `docker compose ps` even when services were working. Healthcheck-as-truth replaced by `verify_stack.sh` probing through the Caddy container.
- Grafana provisioning files now use `$VAR` (plain) instead of `${VAR:-default}` (Bash-style) — the latter was silently breaking provisioning under strict validation.

---

## [v1.0.0-alpha.1] — 2026-04-25

**Phase 1: Replace the legacy LGTM+MinIO prototype with the hybrid stack.**

### Added
- New `docker-compose.yml` declaring the 7-component stack: Caddy, OTel Collector contrib, Prometheus, VictoriaLogs, Tempo, Pyroscope, Grafana.
- `compose/simple.yml` — Simple-profile overlay with resource limits.
- `compose/standard.yml`, `compose/scale.yml` — placeholder stubs for future profiles.
- `configs/caddy/Caddyfile` — TLS, basic auth on `/v1/*`, reverse proxy.
- `configs/otel-collector/config.yaml` — OTLP receivers, batch/memory-limit processors, fan-out to all 4 backends.
- `configs/prometheus/prometheus.yml` — self-scraping + remote-write receiver enabled.
- `configs/tempo/tempo.yaml` — monolithic mode, filesystem storage, metrics_generator with span-graphs.
- `configs/pyroscope/pyroscope.yaml` — filesystem storage.
- `configs/grafana/provisioning/datasources/all.yaml` — 4 datasources auto-provisioned with logs↔traces↔profiles correlations.
- `configs/grafana/provisioning/dashboards/dashboards.yaml` — auto-load JSON dashboards from `configs/grafana/dashboards/`.
- `scripts/verify_stack.sh` — parameterized health check probing all 7 components.
- `Makefile` with shortcuts: `simple`, `stop`, `restart`, `logs`, `verify`, `update`, `config`, `clean`.
- `templates/jelastic/manifest.jps` and `linker.jps` (relocated from repo root + `addons/`).

### Changed
- `.env.example` — variables renamed for the new stack: `BASIC_AUTH_HASH`, `GRAFANA_ADMIN_PASSWORD`, retention overrides per-backend.
- `.gitignore` — refreshed to cover `volumes/`, `.cache/`, common editor temps.

### Removed
- `INTEGRATION.md` (folded into `docs/instrumentation/` in Phase 3).
- `logs.txt` (1 MB debug artifact).
- `scripts/init_buckets.sh` (no MinIO at Simple profile).
- The original `nginx/`, `configs/alloy/`, `configs/mimir.yaml`, `configs/loki.yaml` from the LGTM-era prototype.

### Fixed
- Tempo: added `-config.expand-env=true` flag so `${TEMPO_RETENTION_HOURS}` actually expands in the YAML.
- Pyroscope: removed `limits.retention_period` field (deprecated/moved in Pyroscope 1.10).
- Grafana: removed `grafana-pyroscope-datasource` from `GF_INSTALL_PLUGINS` — it's a core plugin in Grafana 11.x and can't be installed separately.
- Grafana datasource provisioning: removed legacy `datasources.yml` that was conflicting with the new `all.yaml` (caused "only one default datasource" errors).

---

## Versioning

obstack follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html):
- **Major** version (`v2.0.0`) — breaking changes (e.g. config format change, removed component).
- **Minor** version (`v1.1.0`) — new features (e.g. new profile, new dashboard, new alert).
- **Patch** version (`v1.0.1`) — bug fixes.

Pre-release versions (`v1.0.0-alpha.N`) are used during phased development. Once `v1.0.0` ships, alphas end.

[Unreleased]: https://github.com/HameemDakheel/obstack/compare/v1.1.1...HEAD
[v1.1.1]: https://github.com/HameemDakheel/obstack/releases/tag/v1.1.1
[v1.1.0]: https://github.com/HameemDakheel/obstack/releases/tag/v1.1.0
[v1.0.1]: https://github.com/HameemDakheel/obstack/releases/tag/v1.0.1
[v1.0.0]: https://github.com/HameemDakheel/obstack/releases/tag/v1.0.0
[v1.0.0-alpha.4]: https://github.com/HameemDakheel/obstack/releases/tag/v1.0.0-alpha.4
[v1.0.0-alpha.3]: https://github.com/HameemDakheel/obstack/releases/tag/v1.0.0-alpha.3
[v1.0.0-alpha.2]: https://github.com/HameemDakheel/obstack/releases/tag/v1.0.0-alpha.2
[v1.0.0-alpha.1]: https://github.com/HameemDakheel/obstack/releases/tag/v1.0.0-alpha.1
