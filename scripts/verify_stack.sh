#!/bin/bash

BASE_DOMAIN="lgtm-obs.tip2.libyanspider.cloud"
MIMIR_Url="http://$BASE_DOMAIN:9009"
LOKI_URL="http://$BASE_DOMAIN:3100"
TEMPO_URL="http://$BASE_DOMAIN:3200"

echo "=== verifying LGTM+P Stack on $BASE_DOMAIN ==="

# 1. Check Metrics (Mimir)
echo -n "Checking Metrics (Mimir)... "
# Query for 'up' metric which Alloy scrapes from itself
METRIC_RESPONSE=$(curl -s "$MIMIR_Url/prometheus/api/v1/query?query=up")
STATUS=$(echo $METRIC_RESPONSE | jq -r '.status')
if [ "$STATUS" == "success" ]; then
    RESULT_COUNT=$(echo $METRIC_RESPONSE | jq '.data.result | length')
    if [ "$RESULT_COUNT" -gt 0 ]; then
        echo "✅ OK (Found $RESULT_COUNT active targets)"
    else
        echo "⚠️  Connected, but no targets found yet (Alloy might still be scraping)"
    fi
else
    echo "❌ Failed to query Mimir"
    echo "Response: $METRIC_RESPONSE"
fi

# 2. Check Logs (Loki)
echo -n "Checking Logs (Loki)... "
# Query for logs from Alloy component
# We need the current time for the query, but let's try a simple 'ready' check or label query first
# verify Loki is up
LOKI_READY=$(curl -s "$LOKI_URL/ready")
if [ "$LOKI_READY" == "ready" ]; then
     echo "✅ OK (Loki is Ready)"
else
     echo "❌ Loki is not ready"
fi

# 3. Check Traces (Tempo)
echo -n "Checking Traces (Tempo)... "
TEMPO_READY=$(curl -s "$TEMPO_URL/ready")
if [ "$TEMPO_READY" == "ready" ]; then
    echo "✅ OK (Tempo is Ready)"
else
    echo "❌ Tempo is not ready"
    echo "Response: $TEMPO_READY"
fi

echo "=== Verification Complete ==="
