#!/usr/bin/env bash
# verify_stack.sh — health-check every component in the obstack stack.
# Probes services from INSIDE the Caddy container (which has wget and lives
# on the obs-net network), so distroless backends can still be verified.
# Usage: ./scripts/verify_stack.sh
# Exits 0 if all components are reachable, non-zero otherwise.

set -euo pipefail

DOMAIN="${DOMAIN:-localhost}"
SCHEME="${SCHEME:-https}"
TIMEOUT="${TIMEOUT:-10}"
PROBE_CONTAINER="${PROBE_CONTAINER:-obstack-caddy}"

# Component → (internal URL, expected substring or empty for HTTP 200)
declare -A CHECKS=(
  ["otel-collector"]="http://otel-collector:13133/|"
  ["prometheus"]="http://prometheus:9090/-/ready|"
  ["victorialogs"]="http://victorialogs:9428/health|"
  ["tempo"]="http://tempo:3200/ready|ready"
  ["pyroscope"]="http://pyroscope:4040/ready|"
  ["grafana"]="http://grafana:3000/api/health|database"
)

PASS=0
FAIL=0
RESULTS=()

check_component() {
  local name="$1"
  local url="$2"
  local expected="$3"

  local body
  if ! body="$(docker exec "$PROBE_CONTAINER" wget -qO- --timeout="$TIMEOUT" "$url" 2>&1)"; then
    RESULTS+=("FAIL $name (HTTP request failed: $url)")
    return 1
  fi

  if [[ -n "$expected" ]] && ! echo "$body" | grep -q "$expected"; then
    RESULTS+=("FAIL $name (expected '$expected' in response)")
    return 1
  fi

  RESULTS+=("PASS $name")
  return 0
}

echo "── obstack stack verification ──────────────────"

# Caddy itself is the probe — verify it's running first
if ! docker inspect --format='{{.State.Status}}' "$PROBE_CONTAINER" 2>/dev/null | grep -q running; then
  echo "  FAIL caddy (probe container '$PROBE_CONTAINER' not running)"
  exit 1
fi
RESULTS+=("PASS caddy (probe container running)")
PASS=$((PASS+1))

for name in otel-collector prometheus victorialogs tempo pyroscope grafana; do
  IFS='|' read -r url expected <<< "${CHECKS[$name]}"
  if check_component "$name" "$url" "$expected"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
  fi
done

# A "verified" stack that still routes every alert into a void is not
# actually verified — this was the same failure class as a real incident
# this stack's own operator already had once on Grafana Cloud: every alert
# routed to a placeholder address for months and reached nobody. The
# contact-points.yaml default IS the placeholder below
# (configs/grafana/provisioning/alerting/contact-points.yaml), and nothing
# checked whether a deployment ever left it there. This check does.
ALERT_WEBHOOK_PLACEHOLDER="https://example.invalid/alert"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-$ALERT_WEBHOOK_PLACEHOLDER}"
if [[ "$ALERT_WEBHOOK_URL" == "$ALERT_WEBHOOK_PLACEHOLDER" || -z "$ALERT_WEBHOOK_URL" ]]; then
  RESULTS+=("FAIL alert-webhook (ALERT_WEBHOOK_URL is unset or still the placeholder — every alert will fire into a void)")
  FAIL=$((FAIL+1))
else
  RESULTS+=("PASS alert-webhook (configured)")
  PASS=$((PASS+1))
fi

printf '\n'
for r in "${RESULTS[@]}"; do
  echo "  $r"
done

printf '\n── %d passed, %d failed ─────────────────────────\n' "$PASS" "$FAIL"

if (( FAIL > 0 )); then
  exit 1
fi

echo "✅ All checks passed."
