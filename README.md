# OTel-jps

[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-Observability-orange)](https://opentelemetry.io/)
[![Docker Swarm](https://img.shields.io/badge/Docker-Swarm-blue)](https://docs.docker.com/engine/swarm/)

OpenTelemetry Observability Stack for Docker Swarm with **Production** and **Development** environments.

## Architecture

```mermaid
graph TD
    subgraph "External Access"
        User((User/Browser))
        ExtNginx[External Nginx<br/>Port: 443]
    end

    subgraph "Docker Swarm Stack (otel-stack)"
        subgraph "Telemetry Router"
            Collector[OTel Collector<br/>Ports: 4317/4318]
        end

        subgraph "Backends"
            Jaeger[Jaeger (Traces)<br/>UI: 16686<br/>gRPC: 4317]
            Prom[Prometheus (Metrics)<br/>Port: 9090]
            OS[OpenSearch (Logs)<br/>Port: 9200]
        end

        subgraph "Visualization"
            Grafana[Grafana<br/>Port: 3000]
        end
    end

    %% Ingress Flow
    User -->|HTTPS| ExtNginx
    ExtNginx -->|/grafana/| Grafana
    ExtNginx -->|/v1/traces| Collector
    ExtNginx -->|/jaeger/| Jaeger

    %% Data Flow
    Collector -->|Traces| Jaeger
    Collector -->|Metrics| Prom
    Collector -->|Logs| OS

    %% Visualization Flow
    Grafana -->|Query| Jaeger
    Grafana -->|Query| Prom
    Grafana -->|Query| OS
```

## Services Overview

| Service | Internal Port | Exposed Port | Description |
|---------|---------------|--------------|-------------|
| **OTel Collector** | 4317, 4318 | 4317, 4318 | Central telemetry router. Receives data via OTLP. |
| **Grafana** | 3000 | 3000 | Main dashboard UI. Linked to all backends. |
| **Jaeger** | 16686, 4317 | 16686, 4317 | Distributed tracing backend and UI. |
| **Prometheus** | 9090 | 9090 | Metrics database (Time-Series). |
| **OpenSearch** | 9200 | 9200 | Logs database (Search Engine). |

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    observability-net (overlay)                  │
├─────────────────────────────────┬───────────────────────────────┤
│         PROD STACK              │          DEV STACK            │
│  ┌─────────────────────────┐    │    ┌─────────────────────┐    │
│  │ otel-collector (:4317)  │    │    │ OTel Demo Services  │    │
│  │ tempo                   │◄───┼────│ (frontend, cart,    │    │
│  │ loki (:3100)            │    │    │  checkout, etc.)    │    │
│  │ grafana (:3000)         │    │    │ jaeger (:16686)     │    │
│  └─────────────────────────┘    │    │ grafana (:3001)     │    │
│                                 │    └─────────────────────┘    │
└─────────────────────────────────┴───────────────────────────────┘
```

## 📋 Prerequisites

- Docker Swarm cluster (initialized)
- Git installed on manager node

## 🚀 Quick Start

### 1. Clone Repository (on Swarm Manager)

```bash
git clone https://github.com/HameemDakheel/OTel-jps.git /app
cd /app
```

### 2. Create Overlay Network

```bash
docker network create -d overlay --attachable observability-net
```

### 3. Deploy Production Stack

```bash
cd /app/prod
docker stack deploy -c docker-compose.yml otel-prod
```

### 4. Deploy Development Stack (Optional)

```bash
cd /app/dev
docker stack deploy -c docker-compose.yml otel-dev
```

## 📡 Access Points

### Production Stack

| Service | URL | Credentials |
|---------|-----|-------------|
| **Grafana** | `http://<DOMAIN>:3000` | admin / admin |
| **Loki API** | `http://<DOMAIN>:3100` | - |
| **OTLP gRPC** | `<DOMAIN>:4317` | - |
| **OTLP HTTP** | `http://<DOMAIN>:4318` | - |

### Development Stack

| Service | URL | Credentials |
|---------|-----|-------------|
| **Web Store** | `http://<DOMAIN>:8080` | - |
| **Grafana** | `http://<DOMAIN>:3001` | admin / admin |
| **Jaeger UI** | `http://<DOMAIN>:16686` | - |

## 📁 Repository Structure

```
OTel-jps/
├── prod/                         # Production Stack
│   ├── docker-compose.yml        # Swarm stack definition
│   ├── otel-config.yaml          # OTel Collector config
│   ├── tempo-config.yaml         # Tempo config
│   ├── loki-config.yaml          # Loki config
│   └── grafana-datasources.yaml  # Auto-provisioned datasources
│
├── dev/                          # Development Stack
│   ├── docker-compose.yml        # OTel Demo services
│   ├── otel-config.yaml          # Dev collector config
│   └── grafana-datasources.yaml  # Dev datasources (Jaeger)
│
└── README.md
```

## 🔧 Stack Management

### View Services

```bash
# Production
docker stack services otel-prod

# Development
docker stack services otel-dev
```

### View Logs

```bash
docker service logs otel-prod_otel-collector
docker service logs otel-dev_frontend
```

### Remove Stacks

```bash
docker stack rm otel-prod
docker stack rm otel-dev
```

## 🔌 Sending Telemetry

Configure your applications to send OTLP data to the collector:

### Environment Variables

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://<DOMAIN>:4317
OTEL_SERVICE_NAME=my-service
```

### Example: Go Application

```go
exporter, _ := otlptracegrpc.New(ctx,
    otlptracegrpc.WithEndpoint("DOMAIN:4317"),
    otlptracegrpc.WithInsecure(),
)
```

### Example: Python Application

```python
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

exporter = OTLPSpanExporter(endpoint="DOMAIN:4317", insecure=True)
```

## 📊 Grafana Dashboards

Both Grafana instances are pre-configured with datasources:

### Production Grafana (:3000)
- **Tempo** - Distributed tracing
- **Loki** - Log aggregation (with trace correlation)

### Dev Grafana (:3001)
- **Jaeger** - Tracing for demo services
- Links to prod Tempo/Loki if available

## 📄 License

MIT License
