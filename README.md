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
| **Portainer** *(optional)* | `portainer/portainer-ce:latest` | Docker management UI |

## 📡 Exposed Endpoints

| Port | Protocol | Service |
|------|----------|---------|
| `4317` | gRPC | OTLP Receiver |
| `4318` | HTTP | OTLP Receiver |
| `3100` | HTTP | Loki API |
| `3000` | HTTP | Grafana UI |
| `9443` | HTTPS | Portainer UI *(if enabled)* |

## 🔧 Deployment Modes

### Single Docker Engine
- Simple, single-node deployment
- Uses `docker compose`
- Best for: Development, testing, small workloads

### Docker Swarm Cluster
- Multi-node with configurable managers and workers
- Uses `docker stack deploy`
- Best for: Production, high availability

## 📦 Installation

### Option 1: Import via URL (Recommended)

1. Log in to your Jelastic dashboard
2. Click **Import** → **URL** tab
3. Paste:
   ```
   https://raw.githubusercontent.com/HameemDakheel/OTel-jps/main/manifest.jps
   ```
4. Configure options and click **Install**

### Option 2: Local Docker Compose

```bash
cd ops
docker compose up -d
```

### Option 3: Docker Swarm (Manual)

```bash
docker swarm init
cd ops
docker stack deploy -c docker-stack.yml otel
```

## 📁 Repository Structure

```
OTel-jps/
├── manifest.jps              # Main Jelastic installer
├── README.md
├── addons/
│   └── otel-stack-deploy.jps # Stack deployment addon
├── ops/
│   ├── docker-compose.yml    # Single-node compose
│   ├── docker-stack.yml      # Swarm stack file
│   ├── otel-config.yaml      # OTel Collector config
│   ├── tempo-config.yaml     # Tempo config
│   └── loki-config.yaml      # Loki config
└── text/
    └── success.md            # Post-install message
```

## 🔌 Sending Telemetry

Configure your applications to send OTLP data:

```
gRPC:  <NODE_IP>:4317
HTTP:  http://<NODE_IP>:4318/v1/traces
       http://<NODE_IP>:4318/v1/logs
```

### Example: Go Application

```go
exporter, _ := otlptracehttp.New(ctx,
    otlptracehttp.WithEndpoint("NODE_IP:4318"),
    otlptracehttp.WithInsecure(),
)
```

## 🔐 Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| Grafana | `admin` | `admin` |
| Portainer | *(set on first login)* | |

## 📄 License

MIT License
