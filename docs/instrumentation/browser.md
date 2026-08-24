# Browser instrumentation (Real User Monitoring)

> **What you'll need:** a frontend app you can add a `<script>` or npm package to, obstack reachable at `https://<DOMAIN>/`, and the value you set `FRONTEND_ORIGIN` to in `.env`.
> **Time to complete:** ~10 minutes.

This is a **separate signal path from everything else in this section.** Server-side Go/Python/Node/Java/Ruby apps push OTLP to ports `:4317`/`:4318`. The browser pushes a different wire format, [Grafana Faro](https://grafana.com/oss/faro/), to its own dedicated port, `:8027`. The OTel Collector accepts both — it just does not mix them.

---

## Step 1 — Install the Faro Web SDK

```bash
npm install @grafana/faro-web-sdk @grafana/faro-web-tracing
```

## Step 2 — Initialise it as early as possible in your app

Put this before your app's other startup code runs, so it can catch errors from the very first paint.

```javascript
import { initializeFaro } from '@grafana/faro-web-sdk';
import { TracingInstrumentation } from '@grafana/faro-web-tracing';

initializeFaro({
  url: 'https://<DOMAIN>:8027/collect',
  app: {
    name: 'my-frontend-app',
    version: '1.0.0',
    environment: 'production',
  },
  instrumentations: [
    // getWebInstrumentations() from @grafana/faro-web-sdk covers errors,
    // console capture, and Core Web Vitals in one call — see "What ships
    // by default" below for exactly what that includes.
    new TracingInstrumentation(),
  ],
});
```

`app.name` is what shows up as `service.name` once the data lands in Grafana — it is the same field
your Go/Node/Python services use, so pick a name that will not collide with a backend service in the
same Grafana instance (e.g. `my-app-web`, not `my-app`).

## Step 3 — Verify the ingestion route works before trusting a whole app to it

A CORS preflight has to succeed before the browser will even attempt the real POST, so it's worth
checking that in isolation first:

```bash
curl -i -X OPTIONS "https://<DOMAIN>:8027/collect" \
  -H "Origin: https://your-frontend-origin.example" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: content-type"
```

Expect `HTTP/1.1 200`, with `Access-Control-Allow-Origin` echoing back your origin. If you get a
`401` instead, see "Common pitfalls" below — it almost always means `FRONTEND_ORIGIN` in `.env`
doesn't match the origin your app actually runs on.

## Step 4 — Verify in Grafana

Open Grafana → the **obstack** folder → **obstack · Frontend RUM** dashboard
(`configs/grafana/dashboards/frontend-rum.json`). Pick your app from the **Application** dropdown at
the top (it lists every distinct `service.name` seen among RUM records, so it only fills in once
your app has actually sent something). You should see:

- **RUM signal volume by kind** — a timeseries of `log` / `measurement` / `exception` counts.
- **JS error rate** — uncaught exceptions over time.
- **Core Web Vitals** (LCP, FCP, CLS, TTFB) — averaged from the `measurement` records the Web
  Vitals instrumentation sends automatically.
- **Recent RUM activity** — a raw log view of everything, for when a stat panel raises a question
  the panels above can't answer.

If you'd rather check from the command line first: unlike Pyroscope's `:4040` port, VictoriaLogs'
own query API is **not** exposed publicly through Caddy — Grafana is the only thing that talks to it
directly, over the Docker-internal network. From the host running the stack, run the exact LogsQL
query the dashboard panels use, from inside the collector or Grafana container:

```bash
docker exec obstack-victorialogs wget -qO- \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --post-data 'query=service.name:in(my-frontend-app) | stats by (kind) count() as count' \
  http://127.0.0.1:9428/select/logsql/query
```

A result with non-zero counts for `log`, `measurement`, and/or `exception` confirms the pipeline
end to end: browser → Caddy `:8027` → collector's `faro` receiver → VictoriaLogs.

---

## What ships by default

`getWebInstrumentations()` (from `@grafana/faro-web-sdk`, not shown in Step 2's minimal example but
recommended for real use — see the full example below) turns on:

- **Errors** — uncaught exceptions and unhandled promise rejections, each one landing as a
  `kind:exception` record with `type`, `value`, and `stacktrace` fields.
- **Console** — `console.error`/`console.warn`/etc., landing as `kind:log` records.
- **Web Vitals** — LCP, FCP, CLS, TTFB (and INP where the browser supports it), landing as
  `kind:measurement`, `type:web-vitals` records, one measurement per page view.
- **Sessions** — every record is tagged with a `session_id`, generated client-side, so you can
  trace one visitor's whole page-view session across errors and vitals.

Full initialisation with every default instrumentation on:

```javascript
import { initializeFaro, getWebInstrumentations } from '@grafana/faro-web-sdk';
import { TracingInstrumentation } from '@grafana/faro-web-tracing';

initializeFaro({
  url: 'https://<DOMAIN>:8027/collect',
  app: { name: 'my-frontend-app', version: '1.0.0', environment: 'production' },
  instrumentations: [
    ...getWebInstrumentations(),
    new TracingInstrumentation(),
  ],
});
```

`TracingInstrumentation` additionally turns page loads and fetch/XHR calls into spans, which land in
Tempo through the same collector pipeline traces from your backend services already use — so a
frontend fetch call and the backend span it triggered can show up in the same trace if your backend
is also instrumented and propagates the `traceparent` header Faro sends.

---

## Common pitfalls

- **CORS preflight gets a 401, so nothing ever sends** — `FRONTEND_ORIGIN` in `.env` must be your
  frontend's *exact* origin (scheme + host + port, e.g. `https://app.example.com`, not a wildcard
  and not just the hostname). The Faro receiver's CORS config only allows that one origin to POST.
  If your frontend is served from more than one origin (a staging domain and a production domain,
  say), you need to pick one obstack deployment per origin, or front them with the same domain.
  This one is worth checking directly: a `401` on the OPTIONS preflight (not the real POST) is the
  signature of this specific misconfiguration — see Step 3 above.
- **`app.name` collides with a backend service** — Grafana's dashboards, including this one, group
  by `service.name`. If your Go API is also called `my-app`, its OTLP traces and your frontend's
  RUM traces will get merged under one name in every dashboard and every dropdown. Suffix one of
  them (`my-app-web`, `my-app-api`).
- **`initializeFaro` called too late** — if it runs after your app's own error-prone startup code,
  errors from that startup code never reach it. Put the call at the very top of your entrypoint,
  before anything that could throw.
- **Ad blockers / privacy extensions** — some block requests to unfamiliar third-party-looking
  hosts. Since obstack is self-hosted on your own domain, this is far less common than with a
  third-party RUM vendor's shared collection domain, but it's worth knowing about if a specific
  user's data never shows up while everyone else's does.
- **Expecting profiling data here too** — Faro does not carry continuous profiles. There is no
  browser-side equivalent of the Go/Python Pyroscope integration in this stack.

---

## Next steps

- [Go instrumentation](go.md) — if your frontend calls a Go backend and you want the trace to
  continue across the network boundary.
- [Architecture overview](../architecture.md)
- [Grafana Faro documentation](https://grafana.com/docs/grafana-cloud/monitor-applications/frontend-observability/faro-web-sdk/)
