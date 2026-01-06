# LGTM+P Stack Integration Guide

This guide explains how to connect your external infrastructure (Database, Load Balancer, and Storage) to your new Observability stack.

## 1. Database Monitoring (Postgres / MySQL)

To monitor your databases, you should ideally use **Grafana Alloy** as a collector on your DB server, or configure the centralized Alloy instance to scrape your DB.

### A. Using Alloy Exporters
Add this to your `config.alloy` to monitor a Postgres database:

```alloy
prometheus.exporter.postgres "db_main" {
  data_source_name = "postgresql://user:password@localhost:5432/dbname?sslmode=disable"
}

prometheus.scrape "postgres_scrape" {
  targets    = prometheus.exporter.postgres.db_main.targets
  forward_to = [prometheus.remote_write.mimir.receiver]
}
```

### B. Dashboard Recommendation
Once metrics are flowing into Mimir, import the following official dashboards in Grafana:
- **Postgres**: Dashboard ID `9628`
- **MySQL**: Dashboard ID `7362`

---

## 2. Load Balancer / Nginx Monitoring

Monitoring your Load Balancer consists of two parts: **Metrics** (Request rates, latencies) and **Logs** (Error tracking, access trends).

### A. Metrics via Nginx Exporter
If you use Nginx as your LB, enable the `stub_status` module and scrape it:

```alloy
prometheus.exporter.nginx "lb" {
  address = "http://lb-host:8080/stub_status"
}

prometheus.scrape "nginx_scrape" {
  targets    = prometheus.exporter.nginx.lb.targets
  forward_to = [prometheus.remote_write.mimir.receiver]
}
```

### B. Access Logs to Loki
Forward your Nginx access logs to Loki for powerful log analysis:

```alloy
loki.source.file "nginx_logs" {
  targets    = [
    { __path__ = "/var/log/nginx/access.log", job = "nginx" },
    { __path__ = "/var/log/nginx/error.log", job = "nginx" },
  ]
  forward_to = [loki.write.local.receiver]
}
```

---

## 3. Storage Monitoring (MinIO)

Your MinIO cluster provides a built-in Prometheus metrics endpoint.

### A. Scraping MinIO Metrics
MinIO exposes metrics at `/minio/v2/metrics/cluster`. No exporter is needed; just scrape it directly.

```alloy
prometheus.scrape "minio" {
  targets = [{
    __address__ = "minio:9000",
  }]
  metrics_path = "/minio/v2/metrics/cluster"
  forward_to    = [prometheus.remote_write.mimir.receiver]
}
```

### B. MinIO Dashboard
Import Dashboard ID `13502` in Grafana to see cluster health, disk usage, and IOPS.

---

## 4. Connecting Your Applications (OTLP)

Your applications should send data to the centralized OTLP endpoint using **Basic Authentication**.

- **Endpoint**: `https://${env.domain}/v1/`
- **Username**: `otlp`
- **Password**: (Check your success email/dashboard for the generated key)

### Example Environment Variables:
```bash
OTEL_EXPORTER_OTLP_ENDPOINT="https://${env.domain}/v1/"
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <base64_encoded_otlp:password>"
OTEL_RESOURCE_ATTRIBUTES="service.name=my-app,env=prod"
```
