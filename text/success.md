## OTel Observability Stack Deployed Successfully!

**Environment:** ${env.displayName}

---

### Access Points

| Service | URL |
|---------|-----|
| **Grafana** | [http://${nodes.cp.master.intIP}:3000](http://${nodes.cp.master.intIP}:3000) |
| **Loki API** | http://${nodes.cp.master.intIP}:3100 |

**Grafana Credentials:**
Username: `admin`
Password: `admin`

---

### OTLP Endpoints

Configure your applications to send telemetry:

| Protocol | Endpoint |
|----------|----------|
| **gRPC** | `${nodes.cp.master.intIP}:4317` |
| **HTTP** | `http://${nodes.cp.master.intIP}:4318/v1/traces` |

---

### Verify Stack Status

```bash
# For Swarm mode
docker stack services otel

# For Engine mode
docker compose -f /app/ops/docker-compose.yml ps
```
