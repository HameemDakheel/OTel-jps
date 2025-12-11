# OTel-jps

[![Jelastic](https://img.shields.io/badge/Jelastic-JPS-blue)](https://jelastic.com/)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-Collector-orange)](https://opentelemetry.io/)

A **Jelastic JPS manifest** for one-click deployment of a complete OpenTelemetry-based observability stack.

## 🚀 Stack Components

| Service | Image | Purpose |
|---------|-------|---------|
| **OTel Collector** | `otel/opentelemetry-collector-contrib` | Receives, processes, and exports telemetry data |
| **Grafana Tempo** | `grafana/tempo:latest` | Distributed tracing backend |
| **Grafana Loki** | `grafana/loki:latest` | Log aggregation system |
| **Grafana** | `grafana/grafana:latest` | Visualization and dashboards |

## 📡 Exposed Endpoints

| Port | Protocol | Service |
|------|----------|---------|
| `4317` | gRPC | OTLP Receiver |
| `4318` | HTTP | OTLP Receiver |
| `3100` | HTTP | Loki API |
| `3000` | HTTP | Grafana UI |

## 🔧 Installation

### Option 1: Jelastic Marketplace

1. Import `manifest.jps` into your Jelastic dashboard
2. Configure the repository URL (or use default)
3. Click **Install**

### Option 2: Jelastic CLI

```bash
jps install manifest.jps --envName otel-stack
```

### Option 3: Local Docker Compose

```bash
cd ops
docker compose up -d
```

## 📦 Repository Structure

```
OTel-jps/
├── manifest.jps              # Jelastic installation manifest
└── ops/
    ├── docker-compose.yml    # Docker Compose configuration
    ├── otel-config.yaml      # OpenTelemetry Collector config
    ├── tempo-config.yaml     # Grafana Tempo config
    └── loki-config.yaml      # Grafana Loki config
```

## 🔌 Sending Telemetry

Configure your applications to send OTLP data:

**gRPC Endpoint:**
```
http://<YOUR_NODE_IP>:4317
```

**HTTP Endpoint:**
```
http://<YOUR_NODE_IP>:4318/v1/traces
http://<YOUR_NODE_IP>:4318/v1/logs
http://<YOUR_NODE_IP>:4318/v1/metrics
```

### Example: Go Application

```go
import "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"

exporter, _ := otlptracehttp.New(ctx,
    otlptracehttp.WithEndpoint("YOUR_NODE_IP:4318"),
    otlptracehttp.WithInsecure(),
)
```

## 🔐 Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| Grafana | `admin` | `admin` |

## 📄 License

MIT License
