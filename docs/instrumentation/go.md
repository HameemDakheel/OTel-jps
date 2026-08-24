# Go instrumentation

> **What you'll need:** Go 1.21+, an obstack stack reachable at `https://<DOMAIN>/`, and the basic-auth credentials from your `.env`.
> **Time to complete:** ~15 minutes (Go has no SDK-level auto-instrumentation; you wire the SDK manually).

Go does **not** have language-runtime auto-instrumentation in the way Node/Python/Java do — you set up the SDK explicitly and use middleware libraries (`otelhttp`, `otelgin`, `otelgorm`, etc.) for popular frameworks.

---

## Step 1 — Add dependencies

```bash
go get go.opentelemetry.io/otel \
       go.opentelemetry.io/otel/sdk \
       go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp \
       go.opentelemetry.io/otel/sdk/trace \
       go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
```

---

## Step 2 — Configure via environment variables

```bash
export OTEL_SERVICE_NAME=my-go-app
export OTEL_EXPORTER_OTLP_ENDPOINT=https://<DOMAIN>
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_HEADERS="authorization=Basic $(echo -n 'ingest:YOUR_PASSWORD' | base64)"
```

The Go SDK respects these standard env vars — you don't have to thread them through code.

---

## Step 3 — Initialise the SDK in `main`

```go
// main.go
package main

import (
    "context"
    "log"
    "net/http"
    "os"
    "time"

    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

func initTracer(ctx context.Context) (*sdktrace.TracerProvider, error) {
    exp, err := otlptracehttp.New(ctx) // reads OTEL_EXPORTER_OTLP_* env vars
    if err != nil {
        return nil, err
    }
    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exp),
        sdktrace.WithResource(resource.NewWithAttributes(
            semconv.SchemaURL,
            semconv.ServiceName(os.Getenv("OTEL_SERVICE_NAME")),
        )),
    )
    otel.SetTracerProvider(tp)
    return tp, nil
}

func main() {
    ctx := context.Background()
    tp, err := initTracer(ctx)
    if err != nil {
        log.Fatal(err)
    }
    defer func() {
        ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        defer cancel()
        _ = tp.Shutdown(ctx)
    }()

    handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Write([]byte("hello\n"))
    })

    // wrap with otelhttp — every request becomes a trace automatically
    http.Handle("/", otelhttp.NewHandler(handler, "root"))
    log.Println("listening on :8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
```

Run:

```bash
go run main.go
curl http://localhost:8080/
```

---

## Step 4 — Verify in Grafana

Open Grafana → **Explore** → datasource: **Tempo** → "Search" tab → service: `my-go-app`. Each `curl` produces one span with HTTP request attributes.

---

## Step 5 — Add database / framework instrumentation

For common Go libraries:

| Library | Instrumentation package |
|---------|------------------------|
| `database/sql` | `go.opentelemetry.io/contrib/instrumentation/database/sql/otelsql` |
| Gin (web framework) | `go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin` |
| Echo | `go.opentelemetry.io/contrib/instrumentation/github.com/labstack/echo/otelecho` |
| GORM | `gorm.io/plugin/opentelemetry` |
| Kafka (sarama) | `go.opentelemetry.io/contrib/instrumentation/github.com/IBM/sarama/otelsarama` |
| gRPC | `go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc` |

Browse the full list: <https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation>

---

## Continuous profiling (Pyroscope)

Profiling is a **separate library and a separate endpoint** from everything above — `pyroscope-go`,
not the OTel SDK, pushing to obstack's dedicated `:4040` port, not `:4317`/`:4318`. Do not expect
`OTEL_EXPORTER_OTLP_*` env vars to affect this at all; they don't.

> Verified end-to-end 2026-08-24: a real `pyroscope-go` client pushed a CPU profile through this
> exact route, and the profile was independently confirmed both by querying Pyroscope directly and
> by querying it through Grafana's own Pyroscope datasource (`configs/grafana/provisioning/datasources/all.yaml`,
> `uid: pyroscope`) — 32 real Go runtime stack frames, non-zero tick count, both queries returning
> identical data.

### Step 1 — Add the dependency

```bash
go get github.com/grafana/pyroscope-go
```

### Step 2 — Start the profiler at process startup

```go
import "github.com/grafana/pyroscope-go"

profiler, err := pyroscope.Start(pyroscope.Config{
    ApplicationName:   "my-go-app",
    ServerAddress:     "https://<DOMAIN>:4040",
    BasicAuthUser:     "ingest",       // from your .env's BASIC_AUTH_USER
    BasicAuthPassword: "YOUR_PASSWORD", // the plaintext password, NOT the bcrypt hash in .env
    ProfileTypes: []pyroscope.ProfileType{
        pyroscope.ProfileCPU,
        pyroscope.ProfileAllocObjects,
        pyroscope.ProfileAllocSpace,
        pyroscope.ProfileInuseObjects,
        pyroscope.ProfileInuseSpace,
    },
})
if err != nil {
    log.Fatal(err)
}
defer profiler.Stop()
```

Nothing else in your program needs to change — the profiler runs in the background for the life of
the process once started.

### Step 3 — Verify in Grafana

Open Grafana → **Explore** → datasource: **Pyroscope** → select `my-go-app` under Application. A
flame graph appears within roughly a minute of the process starting.

If you'd rather verify from the command line first:

```bash
curl -u ingest:YOUR_PASSWORD \
  "https://<DOMAIN>:4040/pyroscope/render?query=process_cpu:cpu:nanoseconds:cpu:nanoseconds%7Bservice_name%3D%22my-go-app%22%7D&from=now-5m&until=now&format=json"
```

A response with a populated `flamebearer.names` array and a non-zero `numTicks` means the push
worked. An empty array after a minute or more usually means the profiler never started
successfully — check the error returned by `pyroscope.Start`, which this snippet already does.

### Why this is a dedicated port, not `https://<DOMAIN>/pyroscope`

`BasicAuthUser`/`BasicAuthPassword` are the exact config field names — confirmed against Grafana's
own client docs and by a real successful push. The `ServerAddress` you set here becomes the literal
base URL the client posts to; obstack routes it straight through on its own Caddy port rather than
under a path prefix on the main site, specifically to avoid a `handle` vs `handle_path` prefix
mismatch — see `configs/caddy/Caddyfile`'s own comment on the `:4040` block for the full reasoning.

## Common pitfalls

- **TLS verify with self-signed cert** — `otlptracehttp.New(ctx, otlptracehttp.WithInsecure())` for plain HTTP, OR provide a custom client with `otlptracehttp.WithTLSClientConfig(&tls.Config{InsecureSkipVerify: true})` for dev. **Don't use either in production** — point at a real domain.
- **Spans appear with empty service name** — make sure `OTEL_SERVICE_NAME` is set *before* the program starts (or pass via `resource.NewWithAttributes`).
- **Spans not appearing** — Go's `BatchSpanProcessor` batches up to 5 seconds. The `defer tp.Shutdown(ctx)` flushes pending spans on exit.
- **Wrong endpoint URL** — `OTEL_EXPORTER_OTLP_ENDPOINT` should be the base URL (`https://example.com`), not a path. The SDK appends `/v1/traces` automatically.
- **eBPF auto-instrumentation** — projects like [`OpenTelemetry Go Auto-Instrumentation`](https://github.com/open-telemetry/opentelemetry-go-instrumentation) exist but are alpha as of 2026; not recommended for production yet.

---

## Next steps

- [Java instrumentation](java.md)
- [Node.js instrumentation](nodejs.md)
- [Architecture overview](../architecture.md)
- [OpenTelemetry Go docs](https://opentelemetry.io/docs/languages/go/)
