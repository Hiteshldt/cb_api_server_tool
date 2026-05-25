#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  Carbelim API Engine — Deploy latest code
#  Run ON the EC2 server (Amazon Linux 2023, ec2-user)
#
#  From your Mac in one command:
#    ssh -i ~/carbelim-key.pem ec2-user@YOUR_IP \
#      "cd ~/cb_api_server_tool && ./scripts/deploy.sh"
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

APP_DIR="$HOME/cb_api_sever_tool"
BRANCH="production"
PORT=$(grep PORT "$APP_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || echo 3001)

cd "$APP_DIR"

PREV=$(git rev-parse --short HEAD)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Deploying $BRANCH  (was: $PREV)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

git fetch origin
git checkout "$BRANCH"
git pull origin "$BRANCH"

NEXT=$(git rev-parse --short HEAD)
echo "  Now at: $NEXT"

npm install --omit=dev --silent

pm2 reload cb-api-engine || pm2 start ecosystem.config.js --env production
pm2 save

sleep 2
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/health)

if [ "$HTTP" = "200" ]; then
  echo "  ✅  $PREV → $NEXT  deployed successfully"
else
  echo "  ❌  Health check failed after deploy (HTTP $HTTP)"
  echo "  Run: pm2 logs cb-api-engine"
  exit 1
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
