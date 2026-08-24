# Upgrade

> **Audience:** anyone planning to bump obstack to a new release. Read after [Backup & Restore](backup-restore.md).

obstack pins every Docker image to an exact tag. Upgrading happens in **deliberate steps**, not via `:latest`.

---

## Pinning policy

Every image in `docker-compose.yml` is pinned:

```yaml
image: caddy:2-alpine
image: otel/opentelemetry-collector-contrib:0.153.0
image: prom/prometheus:v3.0.1
image: victoriametrics/victoria-logs:v1.1.0-victorialogs
image: grafana/tempo:2.6.1
image: grafana/pyroscope:1.10.0
image: grafana/grafana:11.3.0
image: gcr.io/cadvisor/cadvisor:v0.49.1
```

When obstack bumps a version, the change is **always** in a release with a `CHANGELOG.md` entry explaining what changed and why.

---

## Standard upgrade (pull + recreate)

```bash
git pull origin main
make update
```

`make update` is shorthand for:

```bash
docker compose -f docker-compose.yml -f compose/simple.yml pull
docker compose -f docker-compose.yml -f compose/simple.yml up -d
```

This pulls new image tags from the registry and recreates only the containers whose tags changed. Volumes are preserved.

After the upgrade, run:

```bash
make verify
```

If anything fails, see [Rollback](#rollback) below.

---

## Major-version upgrades

Some upgrades require config-file migrations (e.g. Prometheus v3 → v4 with breaking flag changes). The release CHANGELOG will say so explicitly. Always:

1. **Read the CHANGELOG** entry for the version you're upgrading to.
2. **Take a backup** ([backup-restore.md](backup-restore.md)) before the upgrade.
3. Run the upgrade in a non-production environment first if possible.

---

## Rollback

If `make verify` fails after an upgrade and the cause isn't immediately fixable:

1. Find the previous git ref:

   ```bash
   git log --oneline | head -10
   ```

2. Roll back to it:

   ```bash
   git checkout <previous-tag-or-commit>
   make update
   ```

3. Verify:

   ```bash
   make verify
   ```

This works because Docker keeps both old and new image tags pulled until you explicitly prune. Volume data is preserved across rollback as long as no breaking schema migrations were applied.

If a schema migration *was* applied (e.g. a new Grafana version migrated the SQLite DB), restoring the previous version requires restoring from backup.

---

## Breaking-change protocol

When obstack ships a release that requires manual intervention, the release notes follow this format:

```
## v1.2.0 — 2026-XX-XX

### Breaking changes
- VictoriaLogs storage path changed from `/vlogs` to `/victorialogs/data`. To upgrade,
  stop the stack, rename `/var/lib/docker/volumes/obstack_victorialogs_data/_data/vlogs`
  to `/var/lib/docker/volumes/obstack_victorialogs_data/_data/victorialogs/data`, then
  `make simple`. No data loss.

### Other changes
- ...
```

We never silently break things. If your version of `make verify` works on the old release and breaks on the new, that's a bug — report it.

---

## Image digest pinning (advanced, optional)

For maximum supply-chain security, replace tags with digests:

```yaml
image: caddy@sha256:abc123...
```

Get digests via:

```bash
docker pull caddy:2-alpine
docker inspect --format='{{index .RepoDigests 0}}' caddy:2-alpine
```

This is overkill for most self-hosters but recommended for compliance-sensitive deployments. The `update` workflow then becomes a deliberate digest update, not a tag pull.

---

## Profile upgrade: Simple → Standard

Standard uses the same components as Simple — only resource limits and retention differ. Volumes (data) carry over unchanged.

```bash
# 1. Stop Simple stack (data preserved in named volumes).
make stop

# 2. Optionally edit .env to bump retention to Standard defaults
#    (uncomment the PROMETHEUS_RETENTION=30d block etc.).

# 3. Start Standard.
make standard
make standard-verify
```

The whole procedure is ~30 seconds. No data migration. No re-instrumentation of your apps. Same OTLP endpoint.

---

## See also

- [Backup & Restore](backup-restore.md)
- [Troubleshooting](troubleshooting.md)
- [Architecture](../architecture.md)
