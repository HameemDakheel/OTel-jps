# obstack-mcp — Design Specification

**Date:** 2026-08-24
**Status:** Draft — awaiting owner review (this document IS the Task 8 deliverable; no code has
been written, per the owner's explicit 2026-08-23 decision — see §1)
**Supersedes:** none (new document)
**Authors:** Hameem (product/security review), Claude (research/synthesis)
**Companion work this phase:** `docs/integrations/mcp.md` (Task 6) documents connecting the
*existing, official* `grafana/mcp-grafana` server to obstack today. This document is different:
it's a from-scratch design for a *new*, obstack-specific server that manages the stack itself
(alert packs, retention, resource usage), not one that queries Grafana's own data. The two are
complementary, not competing — a user could run both.

---

## 1. Why this document exists, and why it isn't code

The original pre-plan review flagged **zero MCP support of any kind** (finding H5) as a gap.
Task 6, this same phase, closed the "query my telemetry from an AI assistant" half of that gap by
documenting the official Grafana MCP server. It did not close the other half: **there is no way
for an AI assistant to ask about, or act on, the *stack's own configuration* — which alert packs
are active, what the retention settings are, whether the last verification run passed, how much
memory each component is actually using.**

That's a materially different kind of tool than Task 6's. Task 6 wired up a server that reads
telemetry data — the same class of access Grafana's own UI already grants to anyone who can log
in. A server that can reach into a running production stack's *configuration* is a different risk
class entirely, even in a read-only v1: it becomes a single, MCP-shaped point of failure that, if
compromised, tells an attacker things Grafana's login screen doesn't (what alert packs are
active, i.e. what's *not* being watched; exact resource headroom; whether the last health check
passed). The owner's 2026-08-23 decision was explicit: **this phase's deliverable is a design
document that gets reviewed before a single line of implementation is written**, not a v1 rushed
alongside RUM, alerting, and the golden-signals pack. This document is that design, and it is the
full acceptance criterion for Task 8 — reviewing it and sending it back with changes is a
completely valid outcome, not a failure of this task.

---

## 2. Tool surface, v1

Every tool below is **read-only** — none of them can change stack configuration, rotate a
credential, or delete data. That's not an oversight; it's the entire point of scoping v1 this
tightly. See §4 for what's deliberately excluded and why.

A design choice that shapes every tool below, worth stating once instead of five times: **none of
these tools need Docker socket access, `docker exec`, or any privileged host mount.** They're all
implementable as an unprivileged HTTP client living on `obs-net` — the same network Caddy,
Grafana, Prometheus, and every other obstack service already share — making the same kind of
requests those services already make to each other. This is a real constraint that shaped the
design, not a coincidence: it means the container's own Docker Compose service definition never
needs `privileged: true` or a `/var/run/docker.sock` mount, which by itself removes an entire
category of "what if the credential leaks" scenario before it can even come up in §5.

| Tool | What it does | How it gets the data (no Docker socket) |
|---|---|---|
| `get_stack_status()` | Reports which components are up, matching what `scripts/verify_stack.sh` checks (otel-collector, prometheus, victorialogs, tempo, pyroscope, grafana, caddy) | Direct HTTP requests to each component's own health/ready endpoint over `obs-net` — the exact URLs `verify_stack.sh` already uses (`http://prometheus:9090/-/ready`, etc.) — from inside the obstack-mcp container itself, not by shelling into Caddy |
| `run_verify()` | Runs the same check `make verify` does and returns pass/fail per component | Same mechanism as `get_stack_status()`, plus the `alert-webhook` check — reading `ALERT_WEBHOOK_URL` from obstack-mcp's own container environment (injected by Compose, same as every other service gets its config), not by `docker exec`-ing into Grafana the way the real `verify_stack.sh` does today (see the callout below) |
| `list_active_alert_packs()` | Lists which alert rule groups are actually loaded and evaluating | Prometheus's own `/api/v1/rules` endpoint — reports what's *actually loaded*, which is a stronger signal than listing files in `alerts/`, since a YAML file sitting in `alerts/optional/` that was never `cp`'d into `alerts/` isn't active no matter what the filesystem says |
| `get_retention_settings()` | Reports configured retention for each backend (Prometheus, VictoriaLogs, Tempo, Pyroscope) | Read from obstack-mcp's own container environment — `PROMETHEUS_RETENTION`, `VICTORIALOGS_RETENTION`, `TEMPO_RETENTION_HOURS`, `PYROSCOPE_RETENTION_HOURS` (the exact same env vars already documented in `CLAUDE.md`'s Environment Variables section) injected at container-start, same as any other service. These are durations, not secrets — no different in sensitivity from a value already visible in `.env.example` |
| `get_resource_usage()` | Reports CPU/memory per obstack component | A PromQL query against Prometheus for `container_memory_usage_bytes` / `container_cpu_usage_seconds_total`, scoped to obstack's own container names — data cAdvisor *already* collects and Prometheus *already* stores. obstack-mcp doesn't need cAdvisor's own `privileged: true` + host-mount access (see `docker-compose.yml`'s `cadvisor` service) to answer this — it just reads what cAdvisor already exposed |

**A real implementation detail worth flagging now, before it becomes a surprise during
implementation**: the *existing* `scripts/verify_stack.sh` gets its readiness checks by running
`docker exec obstack-caddy wget ...` and (since Task 5's fix) `docker exec obstack-grafana
printenv ALERT_WEBHOOK_URL` — i.e., the *script itself* needs Docker socket access today, because
it runs on the *host*, outside the Docker network, and uses `docker exec` as a way to reach
internal-only hostnames. `run_verify()` **cannot be a literal wrapper around that script** without
inheriting its Docker-socket dependency, which directly contradicts the "no Docker socket in v1"
principle above. The fix is architectural, not a workaround: obstack-mcp runs *inside* `obs-net`
as its own container (see §6), so it can reach `http://prometheus:9090/-/ready` and friends
*directly*, the same way Grafana's own datasource provisioning already does — no `docker exec`
needed, because obstack-mcp isn't reaching in from outside the network the way a host-run script
has to. This means `run_verify()`'s *behavior* matches `verify_stack.sh`, but its *implementation*
is closer to "the same HTTP checks, running from a different vantage point" than "wrap the
existing script." The `alert-webhook` check specifically needs one more decision: reading
`ALERT_WEBHOOK_URL` from obstack-mcp's own environment (proposed above) tells you what obstack-mcp
itself was configured with, which only matches what's live on Grafana if both containers were
recreated from the same `.env` at the same time — a real edge case, not a hypothetical one, since
this exact class of drift (`.env` changed, container not recreated) is what Task 5 found and fixed
for the *existing* check. Worth deciding explicitly during implementation whether that's an
acceptable trade-off for avoiding Docker socket access, or whether `run_verify()`'s alert-webhook
check should be scoped out of v1 specifically for this reason, leaving the other four
`verify_stack.sh` checks intact.

---

## 3. What v1 explicitly does NOT include, and why

| Excluded | Why it's excluded, specifically |
|---|---|
| **Credential rotation** (regenerating `BASIC_AUTH_HASH`, Grafana admin password, etc.) | A tool that can rotate credentials can also *lock out* the legitimate owner if misused, or hand an attacker a fresh credential of their own choosing. There's no read-only version of "rotate a secret" — it's inherently a write operation with irreversible consequences, exactly the category this phase's design review exists to keep out of v1. |
| **`docker exec` / any Docker-socket access** | Covered in depth in §2's callout. Beyond the specific `run_verify()` case: any tool with Docker socket access is, functionally, root on the host — Docker socket access is a well-known privilege-escalation vector precisely because "run a container" and "run arbitrary code as root" are the same capability. No tool in a read-only v1 needs that power, so no tool should have it. |
| **Anything that deletes data** | Compare directly against SigNoz's own shipped MCP server (a real, running reference point — see §6's citation): it ships `signoz_delete_dashboard`, `signoz_delete_alert`, `signoz_delete_notification_channel`, each guarded only by "a confirmed id" in the tool description, not by any structural safeguard. An AI assistant with that tool available can delete a production dashboard or alert rule if a user's request is ambiguous, if the model misreads intent, or — the scenario this project's whole security posture already has to account for — if it's manipulated via a prompt injection sitting in observed data (a log line, a dashboard title, anything the model reads as part of doing its job). obstack-mcp's v1 tool surface is entirely read-only specifically so that class of failure has no lever to pull. |
| **Anything that changes a secret** | Same reasoning as credential rotation — this is `ALERT_WEBHOOK_URL`, `BASIC_AUTH_HASH`, `GRAFANA_ADMIN_PASSWORD`, and anything like them. Changing any of these is an operational action with real consequences (a wrong webhook URL silently breaks alerting exactly the way Task 5's H7 finding did — see `docs/reference/default-alerts.md` — except this time by an AI assistant's own action instead of a config oversight). |

A version-2-and-later tool surface (create/activate an alert pack, adjust retention, rotate a
credential with confirmation) is a real and reasonable thing to want eventually — SigNoz's own
server proves there's demand for write-capable observability MCP tooling. This document doesn't
rule that out. It says v1 shouldn't include it, and that whenever it's proposed, it needs its own
pass through exactly this kind of review — the blast-radius question in §5 answered fresh for
each new write-capable tool, not inherited from this read-only analysis.

---

## 4. Auth model

**Recommendation: a dedicated credential, using the same Caddy basic-auth *mechanism* obstack
already uses everywhere else — but never the same credential as OTLP ingestion.**

The plan explicitly poses this as an open decision, so the reasoning, not just the conclusion:

- **Reusing the existing `$BASIC_AUTH_USER`/`$BASIC_AUTH_HASH` pair would be a scope violation,
  not a convenience.** That credential's entire purpose is "let an application push telemetry
  IN" — it's the credential every instrumented app (potentially many services, environments, and
  people, per `docs/instrumentation/*.md`) is handed. obstack-mcp's tools are the opposite
  direction: reading the stack's OWN configuration OUT. Handing every app-instrumentation
  credential holder read access to the stack's alert-pack list and resource usage is a strictly
  larger blast radius than the ingestion credential was ever meant to carry, for no benefit.
- **A brand-new auth mechanism (OAuth, a JWT scheme, anything not already in this stack) would
  add a second thing to get right**, when Caddy's `basic_auth` directive is already proven,
  already documented, and already has a working precedent for "a new dedicated port, not a path
  prefix" (Pyroscope's `:4040` block, Faro's `:8027` block — both added this same phase, both with
  their own comments explaining why a dedicated port beats a prefix). obstack-mcp gets its own
  port and its own `$MCP_BASIC_AUTH_USER`/`$MCP_BASIC_AUTH_HASH` pair in `.env`, following that
  exact established pattern.
- **Localhost-only binding, evaluated as the plan requires**: worth offering as a *deployment
  option*, not the default. obstack's whole positioning (`docs/architecture.md`: "production
  observability for your $20/month VPS") assumes the operator wants to reach their stack
  remotely — that's why OTLP ingestion, Pyroscope, and Faro are all public-through-Caddy rather
  than loopback-only. obstack-mcp should follow the same default for consistency, with a
  documented override (bind the new Caddy site block to a loopback-only listener, or simply don't
  publish the port in `docker-compose.yml`) for an operator who only ever wants to reach it via
  SSH tunnel or a VPN. SigNoz's own server makes exactly this same option explicit
  (`MCP_SERVER_HOST=127.0.0.1` — see §6) — evidence this is a real, requested deployment shape,
  not a hypothetical one.

---

## 5. Transport

**Recommendation: HTTP (streamable-HTTP) as the primary, always-on transport, through the same
Caddy + basic-auth pattern as everything else in §4 — with stdio supported as a secondary, local
development affordance, not the primary path.**

This is the one place where obstack-mcp's shape genuinely differs from both reference points this
document leans on elsewhere:

- **`grafana/mcp-grafana`** (documented and verified against obstack in Task 6,
  `docs/integrations/mcp.md`) is typically run *externally* — an MCP client (or the operator)
  starts it as a subprocess pointed at a Grafana URL, wherever that Grafana happens to be. stdio
  is the natural default there because the server's whole lifecycle is "start it when you need
  it, from wherever you're sitting."
- **`SigNoz/signoz-mcp-server`** supports both, and its own README treats HTTP mode as the
  primary path for anything beyond a single desktop client — it documents both an OAuth
  multi-tenant HTTP mode and a simpler shared-credential HTTP mode, with stdio positioned as the
  "Claude Desktop / Cursor" local-client option.
- **obstack-mcp is different from both**: per §6, it's proposed as *a container living inside the
  stack itself*, the same way Grafana is. It isn't started ad hoc by a client reaching out to some
  external target — it's already running, all the time, as part of `docker compose up`. A
  long-running service that's part of the stack's own lifecycle should be reachable the same way
  every other long-running service in this stack is reachable: over the network, through Caddy,
  with the stack's own auth pattern (§4) — not spawned as a subprocess per client session.

stdio stays available (the underlying MCP server library obstack-mcp would be built on supports
both transports for free, per the `grafana/mcp-grafana`/`signoz-mcp-server` precedent of a single
`-t`/`TRANSPORT_MODE` flag choosing between them) specifically for local development and testing
against a stack running on the same machine — genuinely useful, just not the shape a remote
operator reaching their VPS would use day to day.

---

## 6. Blast radius if the credential leaks

This is the section that decides whether the v1 tool list above is actually safe to ship, per the
plan's own framing — so each tool gets a direct answer, not a general statement.

| Tool | What a leaked-credential attacker gets |
|---|---|
| `get_stack_status()` | Which of 7 named components are currently up or down. Operationally useful for planning an attack's timing (e.g., "hit them while a component is already degraded"), but the same information is derivable from simply probing the public OTLP/Pyroscope/Faro/Grafana endpoints directly and watching what errors — it doesn't reveal anything not already externally observable to a motivated attacker. |
| `run_verify()` | Same as above, plus whether `ALERT_WEBHOOK_URL` is configured (true/false, not the URL value itself, per §2's implementation notes) — tells an attacker whether alerting is likely to notice an incident, which is genuinely useful reconnaissance for an attacker planning to stay quiet. This is the highest-value tool in the v1 set for an attacker, worth naming explicitly rather than burying in a table. |
| `list_active_alert_packs()` | Which alert rule groups are loaded — tells an attacker what's *being watched*, and by omission, what isn't (e.g., "no `api-golden-signals` pack active" tells an attacker application-level abuse won't trigger an alert). This is genuine reconnaissance value, same shape as `run_verify()`'s webhook-configured signal. |
| `get_retention_settings()` | How many days of data exist before it's purged — mildly useful for an attacker deciding how much historical evidence of their activity might already be gone, but not independently actionable; needs to be combined with other access to matter. |
| `get_resource_usage()` | Per-component CPU/memory — the lowest-value tool for an attacker of the five. Useful for a DoS attacker deciding which component is closest to its limit, but obstack already ships `HostMemoryPressure`/`HighMemoryUsage`/`HighCPUUsage` alerts (`alerts/default-rules.yaml`) that would fire on the underlying condition regardless of whether an attacker specifically targeted it. |

**Taken together**: the realistic worst case of this v1 credential leaking is a well-informed
attacker who knows what's being monitored, whether they'd get noticed, and which component is
weakest — genuinely useful reconnaissance, not nothing. But **not one tool in this list can be
used to change anything, delete anything, or reach outside the stack's own already-network-exposed
data.** Contrast directly against what a leaked *Grafana admin* credential gets today (full
dashboard/data-source/user management), or what a leaked *OTLP ingestion* credential gets (write
access to every one of obstack's telemetry backends) — a leaked obstack-mcp v1 credential is a
strictly smaller blast radius than either credential this stack already depends on. That's the
argument this v1 tool surface is actually safe to build, contingent on staying exactly this
read-only — which is exactly why §3's exclusions are written as hard boundaries, not a starting
point to relax later without going through this same analysis again.

---

## 7. Where it runs

A new **optional** container (`obstack-mcp`), matching how cAdvisor was added in an earlier
phase — additive, not a replacement for anything, and off by default the same way the optional
alert packs are off by default until an operator opts in.

**Contrast with cAdvisor, worth stating explicitly**: cAdvisor needs `privileged: true`, `/dev/kmsg`,
and four read-only host-filesystem mounts (`/rootfs`, `/var/run`, `/sys`, `/var/lib/docker`) — see
`docker-compose.yml`'s `cadvisor` service — because it inspects the host and every container
directly. Per §2's design, obstack-mcp needs **none of that**: no `privileged`, no device access,
no host mounts. It's a plain unprivileged container on `obs-net`, making the same kind of HTTP
requests Grafana's own provisioned datasources already make.

**Resource limits, proposed**: cAdvisor's own footprint is 128M limit / 32M reservation, identical
across both Simple and Standard profiles (`compose/simple.yml`, `compose/standard.yml`) — the
lightest service in either profile overlay. obstack-mcp, being an even thinner layer (no host
introspection, just HTTP calls to already-running services), should fit comfortably at or below
that same number — proposed starting point: **64M limit / 16M reservation**, both profiles, to be
tuned once a real implementation exists to measure against (this document is explicitly not
claiming a number that's been benchmarked — it's a starting point grounded in the lightest
existing service's actual number, not a guess pulled from nowhere).

**Compose shape** (illustrative, not final — an implementation task would work out the exact
service block): joins `obs-net` like every other service; no `expose`d port needed if reached
exclusively through Caddy's new dedicated port (§4); reads `MCP_BASIC_AUTH_USER`,
`MCP_BASIC_AUTH_HASH`, `ALERT_WEBHOOK_URL`, and the four retention env vars from `.env`, the same
way every other service already does.

---

## 8. Open questions for review

Flagging these explicitly rather than silently picking an answer, since this document's whole job
is to come back for owner review before anything gets built:

1. **§2's `run_verify()` drift concern** — is reading `ALERT_WEBHOOK_URL` from obstack-mcp's own
   environment (rather than `docker exec`-ing into the live Grafana container the way the real
   `verify_stack.sh` does) an acceptable trade-off for staying Docker-socket-free, given the real
   drift scenario Task 5 already found once in the existing check?
2. **Should `run_verify()` exist in v1 at all**, given it's flagged in §6 as the single
   highest-value tool for an attacker with a leaked credential — or should it wait for v2, after
   real usage data from the four lower-risk tools?
3. **Localhost-only vs public-through-Caddy as the *documented default***, not just an available
   option — §4 recommends matching the existing public-by-default pattern for consistency, but an
   argument could be made that a tool surface this new should default conservative (loopback-only)
   until it's proven in the wild, even though every other obstack ingress point defaults public.
4. **Which MCP server framework/library** obstack-mcp would actually be built on (Go, matching
   the rest of this stack's tooling choices, or another language) — genuinely out of scope for
   this design document, which is about the tool surface and its risk boundary, not the
   implementation language, but worth the owner flagging a preference now so an eventual
   implementation task doesn't have to guess.

---

## References

- `docs/integrations/mcp.md` (this phase, Task 6) — the companion, already-shipped documentation
  for connecting the official `grafana/mcp-grafana` server to obstack. Read first for how obstack
  already handles one MCP integration in production.
- [`grafana/mcp-grafana`](https://github.com/grafana/mcp-grafana) — real, running precedent for
  the stdio/HTTP transport split referenced in §5, verified directly against a real obstack
  instance in Task 6 (not just read from its docs).
- [`SigNoz/signoz-mcp-server`](https://github.com/SigNoz/signoz-mcp-server) — the "real, shipped
  reference point" the original plan named explicitly. Its README (fetched directly for this
  document, not recalled from memory) is the source for: the stdio/HTTP/OAuth transport shapes in
  §5, the `MCP_SERVER_HOST=127.0.0.1` loopback-binding option cited in §4, and the write-capable
  tool surface (`signoz_delete_dashboard`, `signoz_delete_alert`, etc.) used as the direct
  contrast case in §3 for why v1 excludes anything destructive.
- `docker-compose.yml`'s `cadvisor` service definition — the precedent this document's §7 measures
  obstack-mcp's own proposed footprint and privilege level against.
- `alerts/default-rules.yaml`, `scripts/verify_stack.sh`,
  `configs/grafana/provisioning/alerting/rules.yaml` — the existing monitoring/alerting surface
  `list_active_alert_packs()` and `run_verify()` build on, including the H7 alert-delivery-bridge
  finding (this same phase, Task 5) that `run_verify()`'s webhook check needs to stay consistent
  with.
