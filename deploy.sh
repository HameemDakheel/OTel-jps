#!/bin/bash
set -e

# Usage
if [ -z "$1" ]; then
    echo "Usage: ./deploy.sh <ENVIRONMENT_HOSTNAME>"
    echo "Example: ./deploy.sh env-2333722.fin.libyanspider.cloud"
    exit 1
fi

ENV_HOSTNAME=$1
echo "🚀 Starting Deployment for Host: $ENV_HOSTNAME"

# 1. Update .env with the correct hostname
echo "🔧 Updating .env configuration..."
# Backup original .env
cp .env .env.bak
# Replace localhost with actual hostname for public endpoints
sed -i "s|localhost|${ENV_HOSTNAME}|g" .env
echo "✅ .env updated."

# 2. Update external-nginx.conf with the current node's IP
# (Assuming this script runs on the node where Nginx and the Stack are deployed together,
# or at least on the manager node that Nginx points to)
# Try to get the route to the internet to find the public/private LAN IP
CURRENT_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+')
if [ -z "$CURRENT_IP" ]; then
    # Fallback
    CURRENT_IP=$(hostname -I | awk '{print $1}')
fi
echo "🔧 Detecting Node IP: $CURRENT_IP"

echo "🔧 Updating external-nginx.conf..."
sed -i "s|10.6.4.132|${CURRENT_IP}|g" external-nginx.conf
sed -i "s|server_name .*;|server_name ${ENV_HOSTNAME};|g" external-nginx.conf
echo "✅ external-nginx.conf updated."

# 3. Deploy Docker Stack
echo "🧹 Cleaning up old stacks..."
docker stack rm otel-stack || true
docker stack rm otel-prod || true
docker stack rm otel-dev || true
echo "⏳ Waiting 15s for cleanup..."
sleep 15

echo "🐳 Deploying Docker Stack..."
# Export environment variables for the stack
set -a
. ./.env
set +a

docker stack deploy -c docker-compose.yml otel-stack

# 4. Instructions for Nginx
echo ""
echo "========================================================"
echo "🎉 Stack Deployed Successfully!"
echo "========================================================"
echo "⚠️  Nginx Configuration Step Required:"
echo ""
echo "If you are running Nginx on THIS server, run:"
echo "  sudo cp external-nginx.conf /etc/nginx/conf.d/observability.conf"
echo "  sudo nginx -s reload"
echo ""
echo "If Nginx is on a DIFFERENT upstream server:"
echo "  Copy 'external-nginx.conf' to that server's /etc/nginx/conf.d/observability.conf"
echo "  And reload Nginx there."
echo ""
echo "🔍 Monitor services with: docker stack ps otel-stack"
