# Contributing to obstack

Thanks for your interest in obstack — a self-hosted OpenTelemetry-native observability stack (Caddy + OTel Collector + Prometheus + VictoriaLogs + Tempo + Pyroscope + Grafana). This guide covers how to set up a dev environment, the project's conventions, and the path from idea → PR → release.

If anything here is unclear or wrong, that itself is a contribution worth making — file an issue or open a docs PR.

---

## Project scope

obstack is **opinionated**. It targets:

- **Self-hosters** running on a single VPS through to multi-server teams.
- **OTel-native** — every component speaks OpenTelemetry; we don't accept patches that bypass OTel for "convenience" backends.
- **Profiles** (Simple / Standard / Scale / Enterprise) that share the base `docker-compose.yml` and layer overlays for resource limits, retention, and HA toggles.

Things we **welcome**:

- Bug fixes (especially in Caddyfile, otelcol pipeline configs, dashboards, alerts).
- New optional alert packs in `alerts/optional/`.
- New examples in `examples/` (additional test workloads, language-specific instrumentation samples).
- Dashboard improvements that work on Grafana 12+ and use the existing datasources.
- Documentation — tutorials, runbooks, troubleshooting recipes.

Things we'll **probably decline**:

- Replacing existing components without a strong reason (e.g. Loki instead of VictoriaLogs).
- Vendor-specific patches (we stay upstream-neutral).
- Features that only matter for a specific cloud (we run on plain Docker Compose; cloud-specific automation belongs in a separate repo).

When in doubt, **open an issue first** to discuss scope before writing code.

---

## Dev environment

You need: Docker 24+, `docker compose`, `make`, `git`, Python 3.10+ (for YAML/JSON validation), `bash`. Tested on Linux and macOS.

```bash
git clone https://github.com/HameemDakheel/obstack
cd obstack

# .env contains credentials — copy from example and edit
cp .env.example .env

# Bring the Simple profile up
make simple

# After ~30 seconds:
make verify       # expect "7 passed, 0 failed"
```

Open Grafana at <https://localhost/> (admin / from your `.env`).

---

## Repository layout (what lives where)

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | Base service definitions — image versions, networks, volumes, healthchecks. **Never** put resource limits or profile-specific config here. |
| `compose/<profile>.yml` | Profile overlays (`simple.yml`, `standard.yml`, `scale.yml`). Just `deploy.resources.limits` and per-profile env vars. |
| `configs/` | Component configs. Keep static defaults here; never bake credentials in (use env vars). |
| `configs/grafana/dashboards/*.json` | Auto-provisioned dashboards. Add new ones by dropping JSON here. |
| `alerts/default-rules.yaml` | Alerts loaded by default in every profile. |
| `alerts/optional/<pack>.yaml` | Drop-in alert packs for specific exporters. |
| `examples/` | Standalone reference workloads (currently `otel-demo/`). |
| `scripts/` | Helper scripts (`verify_stack.sh`, `demo-up.sh`). `init_buckets.sh` and `prepare_configs.sh` were removed 2026-08-23 — both were MinIO-era leftovers, unreferenced anywhere and (`prepare_configs.sh`) incapable of running against the current `.env` shape at all. See `docs/superpowers/plans/2026-08-23-rum-alerting-mcp-hardening.md`, Task 1. |
| `docs/` | MkDocs source. Strict build (`mkdocs build --strict`, run in CI by `.github/workflows/validate.yml`) must pass with no warnings — there is no `make docs-build` target. |
| `templates/jelastic/manifest.jps` | Jelastic one-click installer manifest (JSON, not YAML) — **not** at repo root. |

---

## Conventions

### Adding a dashboard

1. Save your Grafana dashboard JSON in `configs/grafana/dashboards/<name>.json`.
2. Use `"datasource": { "uid": "prometheus" }` (or `"tempo"`, `"victorialogs"`, `"pyroscope"`). Don't hardcode datasource UIDs that don't exist in `configs/grafana/provisioning/datasources/all.yaml`.
3. Set `"uid": "obstack-<slug>"` for stable URLs.
4. Add `"tags": ["obstack", ...]` so it appears in the obstack folder.
5. **Test it** with `make simple && make verify` then open Grafana → Dashboards → obstack folder. Empty panels are an automatic reject.

### Adding an alert pack

1. Create `alerts/optional/<name>.yaml` with valid Prometheus rule syntax.
2. Header comment must list:
   - What exporter / receiver is required.
   - One-sentence purpose.
   - Activation command (`cp alerts/optional/<name>.yaml alerts/`).
3. Validate with `promtool check rules`:

   ```bash
   docker run --rm -v "$PWD/alerts/optional:/rules:ro" \
     --entrypoint promtool prom/prometheus:v3.0.1 \
     check rules /rules/<name>.yaml
   ```

4. Document the pack in `alerts/optional/README.md`'s table.
5. Add it to the table in `docs/reference/default-alerts.md` under "Optional alert packs".

### Editing configs

- **`configs/caddy/Caddyfile`**: changes are visible after `docker compose -f docker-compose.yml -f compose/simple.yml restart caddy`. Test public OTLP path with a curl POST to `https://localhost/v1/traces` after every change.
- **`configs/otel-collector/config.yaml`**: validate with `docker run --rm -v "$PWD/configs/otel-collector:/cfg:ro" otel/opentelemetry-collector-contrib:0.142.0 --config=/cfg/config.yaml --dry-run` (or just restart and watch logs).
- **`configs/prometheus/prometheus.yml`**: validate with `promtool check config`.
- **`configs/tempo/tempo.yaml`** / **`pyroscope/pyroscope.yaml`**: restart and watch `/ready`.

### Editing manifest.jps

`manifest.jps` is **JSON, not YAML**. Validate with `python3 -c "import json; json.load(open('manifest.jps'))"`. Multi-line shell commands use `\n` (literal backslash-n in JSON strings). When in doubt, copy a working block.

---

## Coding style

- **Bash scripts**: `#!/usr/bin/env bash`, `set -euo pipefail`, validate with `bash -n <script>`.
- **YAML/JSON configs**: 2-space indent, no trailing whitespace, no tabs.
- **Dashboards**: prefer reusable template variables (`$service` etc.) over hardcoded values.
- **Comments in configs**: explain *why* (the trade-off, the constraint, the gotcha) — never *what* (the YAML keys are self-describing).

---

## Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<optional body>
```

Types: `feat`, `fix`, `docs`, `chore`, `test`, `refactor`, `perf`, `ci`, `build`.

Scopes used in this repo include: `caddy`, `otelcol`, `prometheus`, `tempo`, `pyroscope`, `grafana`, `alerts`, `demo`, `host-metrics`, `compose`, `make`, `manifest`, `release`.

Each commit should do **one thing**:

- Mixing a Caddy fix with a new dashboard = **two commits**.
- Bumping image versions across components = **one commit per component** (or a single `chore(deps)` that rolls them all if the change is mechanical).

Don't push commits with `[skip ci]` unless you genuinely need to.

---

## Pull requests

1. Fork, create a feature branch from `main`: `git checkout -b feat/<short-description>`.
2. Make your changes. Run the full local validation:

   ```bash
   make simple
   sleep 30
   make verify
   docker run --rm -v "$(pwd):/docs" -w /docs squidfunk/mkdocs-material:9.5.39 build --strict --site-dir /tmp/site
   ```

3. Open the PR. Title follows the same Conventional Commits format as commits.
4. PR description must include:
   - **Summary** — 1-3 bullets.
   - **What you changed** — paths and rationale.
   - **How you tested** — commands run, what you verified in Grafana / Prometheus / etc.
   - **Screenshots** if you touched dashboards or any user-facing UI.
   - **Breaking changes** if any (call out container-name changes, env-var renames, config schema changes — these need a CHANGELOG migration block).

5. CI runs validation on push: `docker compose config`, YAML/JSON parse, MkDocs strict build. Green CI is required before review.

### Review expectations

- A maintainer will respond within ~5 days. If we go silent for 2+ weeks, ping `@HameemDakheel` in a PR comment.
- Expect questions about scope, observability/cost trade-offs, and operational impact (cardinality explosions, retention, RAM ceilings).
- Requested changes? Push fixups; we'll squash on merge.

---

## Reporting bugs

File a [GitHub issue](https://github.com/HameemDakheel/obstack/issues/new) with:

- **obstack version** (`git log --oneline -1`).
- **Profile** (Simple / Standard / Scale).
- **Host environment** (OS, Docker version, RAM).
- **Steps to reproduce** including the exact command you ran.
- **Expected vs actual behavior**.
- Output of `make verify` and relevant `docker logs <service>`.

For security issues, **email <ai@ping.com.ly>** instead of filing a public issue. We'll respond within 7 days.

---

## Release flow

Maintainers cut releases. The flow:

1. Bump version everywhere it appears (`README.md` badge, `mkdocs.yml`, `CHANGELOG.md`).
2. Add a `## [vX.Y.Z]` block in `CHANGELOG.md` with Added / Changed / Removed / Migration sections.
3. Tag locally: `git tag -a vX.Y.Z -m "vX.Y.Z — <one-line summary>"`.
4. Run end-to-end verification per the latest release plan in `docs/superpowers/plans/`.
5. Push tag: `git push origin vX.Y.Z` (after the corresponding commit is on `main`).
6. Create a GitHub release using the CHANGELOG entry as the body.

Semver:
- **Patch** (vX.Y.**Z**): bug fixes, no behavior changes for users.
- **Minor** (vX.**Y**.0): additive features (new dashboards, new alert packs, new profiles, opt-in changes).
- **Major** (v**X**.0.0): breaking changes (container renames, removed components, env-var contract changes).

---

## Code of conduct

Be kind, be specific, and assume good faith. We follow the [Contributor Covenant 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Reports of misconduct go to <ai@ping.com.ly>.

---

## License

By contributing, you agree your contributions will be licensed under the [MIT License](LICENSE).
