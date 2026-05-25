#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  Carbelim API Engine — ONE-TIME server setup
#  Works on: Amazon Linux 2023 (ec2-user)
#
#  Run this ONCE on a fresh EC2 instance:
#    chmod +x setup-server.sh && ./setup-server.sh
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

APP_DIR="$HOME/cb_api_server_tool"
REPO_URL="https://github.com/Hiteshldt/cb_api_server_tool.git"
BRANCH="production"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Carbelim API Engine — Server Setup"
echo "  OS: Amazon Linux 2023"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. System update ─────────────────────────────────────────
echo "[1/7] Updating system..."
sudo dnf update -y -q
sudo dnf install -y -q git curl nginx

# ── 2. Node.js 20 via NVM ────────────────────────────────────
echo "[2/7] Installing Node.js 20..."
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo dnf install -y nodejs
node -v && npm -v

# ── 3. PM2 ───────────────────────────────────────────────────
echo "[3/7] Installing PM2..."
sudo npm install -g pm2
pm2 --version

# ── 4. Clone repo ─────────────────────────────────────────────
echo "[4/7] Cloning repository (branch: $BRANCH)..."
if [ -d "$APP_DIR" ]; then
  echo "  Folder exists — pulling latest"
  cd "$APP_DIR"
  git fetch origin
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
else
  git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
  cd "$APP_DIR"
fi

# ── 5. Install npm dependencies ───────────────────────────────
echo "[5/7] Installing dependencies..."
npm install --omit=dev

# ── 6. Create .env ────────────────────────────────────────────
echo "[6/7] Creating .env..."
if [ ! -f "$APP_DIR/.env" ]; then
  RANDOM_KEY=$(openssl rand -hex 12)
  cat > "$APP_DIR/.env" << EOF
PORT=3001
ADMIN_API_KEY=cbadmin_${RANDOM_KEY}
CONFIG_DIR=./data
DEBUG=false
EOF
  echo ""
  echo "  ⚠️  Generated a random admin key."
  echo "  Your key: $(grep ADMIN_API_KEY $APP_DIR/.env | cut -d= -f2)"
  echo "  Save it now — you'll need it to log into the admin UI."
  echo ""
else
  echo "  .env already exists — skipping"
fi

# ── 7. Nginx config ───────────────────────────────────────────
echo "[7/7] Configuring Nginx..."
sudo cp "$APP_DIR/nginx/carbelim.conf" /etc/nginx/conf.d/carbelim.conf
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl start nginx

# ── Start app with PM2 ────────────────────────────────────────
echo ""
echo "Starting app..."
cd "$APP_DIR"
pm2 start ecosystem.config.js --env production
pm2 save

# Auto-start PM2 on reboot
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd \
  -u ec2-user --hp /home/ec2-user 2>/dev/null || true
pm2 save

# ── Health check ─────────────────────────────────────────────
sleep 3
echo ""
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/health)
if [ "$HTTP" = "200" ]; then
  PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR_IP")
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ✅  Setup complete!"
  echo ""
  echo "  Admin UI →  http://$PUBLIC_IP/admin"
  echo "  Health   →  http://$PUBLIC_IP/health"
  echo ""
  echo "  Admin key: $(grep ADMIN_API_KEY $APP_DIR/.env | cut -d= -f2)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo "  ❌  Health check failed (HTTP $HTTP)"
  echo "  Run: pm2 logs cb-api-engine"
fi
