# Grafana MCP (AI assistants)

> **What you'll need:** a running obstack instance, admin access to its Grafana, and an MCP
> client that supports either stdio or streamable-HTTP servers (Claude Desktop, Claude Code,
> Cursor, and others).
> **Time to complete:** ~10 minutes.
> **No obstack code changes required** — this page is entirely about running someone else's
> tool against your own obstack Grafana. `grafana/mcp-grafana` is the official, self-hostable
> server from Grafana Labs — the same project behind `mcp.grafana.com` — pointed at your own
> URL and token instead of Grafana Cloud.

MCP (Model Context Protocol) lets an AI assistant query your observability stack directly:
search dashboards, run PromQL/LogQL, list alert rules, pull a trace, all without you
copy-pasting query results into a chat window. Everything below was tested against a real
running obstack instance, not assumed from the project's README.

---

## Step 1 — Create a Grafana service account token

Service account tokens are the current, non-deprecated way to authenticate — the older
`GRAFANA_API_KEY` style still works for backward compatibility but is being phased out.

### Via the Grafana UI

1. Log into your obstack Grafana (`https://<DOMAIN>/`, the admin credentials from `.env`).
2. **Administration → Service accounts → Add service account.**
3. Give it a name (e.g. `mcp-server`) and a role. `Editor` is the simplest choice — broad
   read/write access covering most MCP server operations. Use a more restricted custom role if
   you want the assistant limited to read-only queries.
4. Open the new service account → **Add service account token** → copy the token immediately;
   Grafana shows it exactly once.

### Via the API (scriptable, useful for automation)

```bash
# Create the service account
curl -s -X POST -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"name":"mcp-server","role":"Editor"}' \
  "https://<DOMAIN>/api/serviceaccounts"
# → {"id":2,"name":"mcp-server",...}  — note the "id"

# Generate its token (replace 2 with the id from above)
curl -s -X POST -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"name":"mcp-server-token"}' \
  "https://<DOMAIN>/api/serviceaccounts/2/tokens"
# → {"id":1,"name":"mcp-server-token","key":"glsa_..."}  — the "key" is your token, shown once
```

Treat this token like a password — anyone holding it can do whatever the service account's role
allows against your Grafana instance. Store it in your MCP client's own secret handling, not in
a file that gets committed anywhere.

---

## Step 2 — Run `grafana/mcp-grafana` pointed at obstack

The image name from Docker Hub is `grafana/mcp-grafana` (the canonical one — a differently
namespaced `mcp/grafana` mirror also exists and works, but the project's own docs use this
name, so that's what's documented here).

### For an AI assistant that manages the process itself (Claude Desktop, Claude Code, Cursor)

Most desktop MCP clients run the server as a subprocess over stdio — add this to the client's
MCP server configuration:

```json
{
  "mcpServers": {
    "grafana": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "-e", "GRAFANA_URL=https://<DOMAIN>",
        "-e", "GRAFANA_SERVICE_ACCOUNT_TOKEN=<your token from Step 1>",
        "grafana/mcp-grafana", "-t", "stdio"
      ]
    }
  }
}
```

If you have [`uv`](https://docs.astral.sh/uv/getting-started/installation/) installed instead of
wanting a container per session, the project also publishes to PyPI — `uvx mcp-grafana` with the
same two environment variables works identically and starts faster.

### For a standalone server other tools connect to (streamable-HTTP)

```bash
docker run -d --name mcp-grafana \
  -p 8000:8000 \
  -e GRAFANA_URL=https://<DOMAIN> \
  -e GRAFANA_SERVICE_ACCOUNT_TOKEN=<your token from Step 1> \
  -e MCP_GRAFANA_SERVER_TOKEN=<a token YOU pick for callers to present> \
  grafana/mcp-grafana -t streamable-http -address 0.0.0.0:8000
```

`MCP_GRAFANA_SERVER_TOKEN` matters — without it the server starts but logs a security error and
accepts unauthenticated callers (it will refuse to start at all in a future major release, per
the project's own README). Set it, and have every MCP client send
`Authorization: Bearer <that token>`.

**A real trap, hit while verifying this page, worth naming explicitly**: the server validates
the incoming HTTP `Host` header and rejects anything that isn't a loopback variant of its own
`-address` by default (`forbidden: host not allowed`). This is a sane default for a server bound
to `0.0.0.0` — but it means if you run it in Docker and reach it by container/service name
(`http://mcp-grafana:8000` from another container on the same network) rather than
`localhost:8000`, every request gets rejected until you add `-allowed-hosts "*"` (only safe
behind a trusted reverse proxy that rewrites Host — don't set this on a server directly exposed
to the internet).

---

## Step 3 — Verify it actually works

Confirmed 2026-08-24 against a real local obstack instance (Simple profile), not just started
and assumed working — a raw MCP JSON-RPC session, the same protocol any real MCP client speaks:

```bash
# 1. Handshake — every session starts with initialize
curl -s -X POST http://localhost:8000/mcp \
  -H "Authorization: Bearer <your MCP_GRAFANA_SERVER_TOKEN>" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"1.0"}}}'
# → result.serverInfo.name == "mcp-grafana", and a Mcp-Session-Id response header —
#   copy that value, every request after this one needs it as a header.
```

With the session ID from that response as `$SID`, three calls confirm the capabilities this page
promises actually work — all three returned real data from the live stack when this was tested:

```bash
# 2. Dashboard search
curl -s -X POST http://localhost:8000/mcp \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" -H "Mcp-Session-Id: $SID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_dashboards","arguments":{"query":""}}}'
# → found every real dashboard obstack provisions, including the frontend-rum one from
#   docs/instrumentation/browser.md and the "obstack-alerting" folder from Task 5.

# 3. A real PromQL query (query_prometheus needs BOTH queryType and endTime for an instant query
#    — omitting endTime fails with a parse error, worth knowing before you're debugging it)
curl -s -X POST http://localhost:8000/mcp \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" -H "Mcp-Session-Id: $SID" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"query_prometheus","arguments":{"datasourceUid":"prometheus","expr":"up","queryType":"instant","endTime":"now"}}}'
# → up=1 for every real component: pyroscope, otel-collector, prometheus-self, cadvisor,
#   grafana, tempo.

# 4. Alert rules — the tool is called alerting_manage_rules, not list_alert_rules; pass
#    operation: "list" (other operations: get, versions, create, update, delete)
curl -s -X POST http://localhost:8000/mcp \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" -H "Mcp-Session-Id: $SID" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"alerting_manage_rules","arguments":{"operation":"list"}}}'
# → showed the real "Prometheus alerts bridge" rule from
#   configs/grafana/provisioning/alerting/rules.yaml (see reference/default-alerts.md), state
#   "normal", health "ok".
```

A real MCP client handles the handshake and session header for you — the raw curl sequence
above is only to prove the server works before trusting a whole conversation to it, the same way
you'd check a webhook lands before trusting an alert pipeline to it.

---

## What the assistant can actually do once connected

The server exposes far more than the three checks above — 65 tools as of this writing, covering
dashboards, folders, datasources, Prometheus, Loki, alerting, on-call schedules, Pyroscope
profiling, annotations, and more. A few obstack-relevant examples:

- *"What's the p95 latency on my API right now?"* → `query_prometheus` against your app's own
  metrics, same PromQL you'd write in Grafana Explore.
- *"Show me recent errors in the frontend."* → once `docs/instrumentation/browser.md` is set up,
  a Loki-style query against VictoriaLogs through the same mechanism.
- *"Is the Prometheus-alerts bridge rule healthy?"* → exactly the `alerting_manage_rules` call
  in Step 3 above.
- *"Search for a dashboard about container metrics."* → `search_dashboards`.

## Common pitfalls

- **Token pasted into a committed file** — service account tokens are secrets. Use your MCP
  client's own env/secret configuration, never a file that ends up in version control.
- **`forbidden: host not allowed`** — see the `-allowed-hosts` note in Step 2. Only relevant to
  the SSE/streamable-HTTP modes; stdio mode has no HTTP layer to reject a Host header on.
- **`query_prometheus` instant query fails to parse** — needs `endTime` explicitly set (`"now"`
  or an RFC3339 timestamp) even for `queryType: "instant"`. Confirmed directly: omitting it
  fails with `parsing end time: syntax error: unexpected $end...`.
- **Looking for `list_alert_rules`** — it's `alerting_manage_rules` with `operation: "list"`, one
  tool covering list/get/versions/create/update/delete rather than one tool per verb.
- **Read-only vs read-write** — the service account's Grafana role IS the access boundary. An
  assistant with an `Editor`-role token can create and modify dashboards, not just read them. If
  you only want an assistant to look, not touch, use a more restricted custom role, or the
  server's own `-disable-write` flag to remove every write-capable tool regardless of the
  token's role.

---

## Next steps

- [Architecture overview](../architecture.md)
- [Default alerts](../reference/default-alerts.md) — what the `alerting_manage_rules` example
  above is actually looking at
- [Official `grafana/mcp-grafana` repository](https://github.com/grafana/mcp-grafana)
