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
#
# Reads values from the LIVE Grafana container's own environment, not from a
# local .env file — confirmed necessary, not stylistic: this script does not
# source .env, and neither does `make verify`, so a first version of this
# check that read a plain shell variable FAILED PERMANENTLY even with a
# genuinely correct ALERT_WEBHOOK_URL sitting in .env, because that value
# never reaches this script's process environment the normal, documented way
# a user runs `make verify`. Proved directly: added a real-looking webhook
# URL to .env, ran `make verify` exactly as quickstart.md's Step 4 documents,
# and it still reported the placeholder failure. Reading the running
# container's actual env is also strictly more correct than reading the file
# even once fixed: it reflects what's actually deployed, not what a local
# .env says, which can drift if someone edits .env without recreating the
# grafana container.
#
# Two delivery mechanisms exist (contact-points.yaml: default-webhook and
# default-email — see that file's own header comment), and
# notification-policies.yaml decides which one is actually live. Checking
# ONLY the webhook path would repeat the exact false-negative bug already
# found and fixed once in this same check (see git history): a deployment
# correctly configured for email alone would FAIL this check forever, having
# done nothing wrong. So this checks BOTH and passes if EITHER is genuinely
# configured — it doesn't need to know which one notification-policies.yaml
# is actually routing to; if the operator picked one and left the other at
# its placeholder, this correctly reports the one they picked.
ALERT_WEBHOOK_PLACEHOLDER="https://example.invalid/alert"
ALERT_WEBHOOK_URL="$(docker exec obstack-grafana printenv ALERT_WEBHOOK_URL 2>/dev/null || true)"
webhook_configured=false
if [[ -n "$ALERT_WEBHOOK_URL" && "$ALERT_WEBHOOK_URL" != "$ALERT_WEBHOOK_PLACEHOLDER" ]]; then
  webhook_configured=true
fi

SMTP_ENABLED="$(docker exec obstack-grafana printenv GF_SMTP_ENABLED 2>/dev/null || true)"
ALERT_EMAIL_ADDRESSES="$(docker exec obstack-grafana printenv ALERT_EMAIL_ADDRESSES 2>/dev/null || true)"
EMAIL_PLACEHOLDER="alerts@example.invalid"
email_configured=false
if [[ "$SMTP_ENABLED" == "true" && -n "$ALERT_EMAIL_ADDRESSES" && "$ALERT_EMAIL_ADDRESSES" != "$EMAIL_PLACEHOLDER" ]]; then
  email_configured=true
fi

if [[ "$webhook_configured" == true || "$email_configured" == true ]]; then
  detail=""
  [[ "$webhook_configured" == true ]] && detail="webhook"
  [[ "$email_configured" == true ]] && detail="${detail:+$detail, }email"
  RESULTS+=("PASS alert-webhook (configured: $detail)")
  PASS=$((PASS+1))
else
  RESULTS+=("FAIL alert-webhook (neither ALERT_WEBHOOK_URL nor SMTP email is configured — every alert will fire into a void)")
  FAIL=$((FAIL+1))
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
