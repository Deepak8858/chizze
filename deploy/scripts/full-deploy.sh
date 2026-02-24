#!/bin/bash
# ══════════════════════════════════════════
# Chizze — Full Production Deployment Script
# DigitalOcean Droplet: 165.232.177.81
# Domain: api.devdeepak.me
# ══════════════════════════════════════════
# This script runs ON the server after files are copied
# Usage: bash full-deploy.sh
# ══════════════════════════════════════════

set -euo pipefail

DEPLOY_DIR="/opt/chizze"
DOMAIN="api.devdeepak.me"
EMAIL="admin@devdeepak.me"

echo "═══════════════════════════════════════"
echo "  Chizze Full Production Deployment"
echo "  Droplet: 165.232.177.81"
echo "  Domain:  $DOMAIN"
echo "═══════════════════════════════════════"

# ─── 1. System Setup ───
echo ""
echo "═══ Step 1: System Setup ═══"
apt-get update -qq && apt-get upgrade -y -qq

# Install Docker if missing
if ! command -v docker &> /dev/null; then
    echo "→ Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo "  ✓ Docker installed"
else
    echo "  ✓ Docker already installed"
fi

# Install Docker Compose if missing
if ! docker compose version &> /dev/null; then
    echo "→ Installing Docker Compose..."
    apt-get install -y -qq docker-compose-plugin
    echo "  ✓ Docker Compose installed"
else
    echo "  ✓ Docker Compose already installed"
fi

# Install git if missing
if ! command -v git &> /dev/null; then
    apt-get install -y -qq git
fi

# ─── 2. Firewall ───
echo ""
echo "═══ Step 2: Firewall ═══"
if command -v ufw &> /dev/null; then
    ufw allow 22/tcp   2>/dev/null || true
    ufw allow 80/tcp   2>/dev/null || true
    ufw allow 443/tcp  2>/dev/null || true
    ufw --force enable  2>/dev/null || true
    echo "  ✓ Firewall: 22, 80, 443 open"
fi

# ─── 3. Swap (if not present, for low-memory droplets) ───
if [ ! -f /swapfile ]; then
    echo ""
    echo "═══ Step 3: Creating 2GB Swap ═══"
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "  ✓ 2GB swap created"
fi

# ─── 4. Prepare deploy directory ───
echo ""
echo "═══ Step 4: Prepare Deploy Directory ═══"
mkdir -p $DEPLOY_DIR
cd $DEPLOY_DIR

# Verify required files exist
for f in docker-compose.prod.yml .env.prod nginx/nginx.conf nginx/proxy_params.conf; do
    if [ ! -f "$f" ]; then
        echo "❌ Missing: $f"
        exit 1
    fi
done
echo "  ✓ All deploy files present"

# ─── 5. Build Docker Image ───
echo ""
echo "═══ Step 5: Building Docker Image ═══"
if [ -d "$DEPLOY_DIR/backend" ]; then
    cd $DEPLOY_DIR/backend
    docker build -t chizze-api:latest --build-arg VERSION=1.0.0 .
    echo "  ✓ chizze-api:latest built"
    cd $DEPLOY_DIR
else
    echo "❌ Backend directory not found at $DEPLOY_DIR/backend"
    exit 1
fi

# ─── 6. SSL Certificate ───
echo ""
echo "═══ Step 6: SSL Certificate ═══"
mkdir -p $DEPLOY_DIR/certbot/www $DEPLOY_DIR/ssl

if [ ! -f "$DEPLOY_DIR/ssl/live/$DOMAIN/fullchain.pem" ]; then
    echo "→ No SSL cert found, requesting from Let's Encrypt..."
    
    # Start temp nginx for ACME challenge
    cat > /tmp/nginx-acme.conf << 'ACMEEOF'
server {
    listen 80;
    server_name _;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        return 200 'Chizze SSL setup';
        add_header Content-Type text/plain;
    }
}
ACMEEOF

    # Stop any existing containers using port 80
    docker stop nginx-acme 2>/dev/null || true
    docker rm nginx-acme 2>/dev/null || true
    docker compose -f $DEPLOY_DIR/docker-compose.prod.yml down 2>/dev/null || true

    docker run -d --name nginx-acme \
        -p 80:80 \
        -v /tmp/nginx-acme.conf:/etc/nginx/conf.d/default.conf:ro \
        -v "$DEPLOY_DIR/certbot/www:/var/www/certbot" \
        nginx:1.25-alpine
    
    sleep 3

    # Request certificate
    docker run --rm \
        -v "$DEPLOY_DIR/ssl:/etc/letsencrypt" \
        -v "$DEPLOY_DIR/certbot/www:/var/www/certbot" \
        certbot/certbot:latest certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --non-interactive \
        -d "$DOMAIN"

    # Cleanup
    docker stop nginx-acme && docker rm nginx-acme

    if [ -f "$DEPLOY_DIR/ssl/live/$DOMAIN/fullchain.pem" ]; then
        echo "  ✓ SSL certificate obtained for $DOMAIN"
    else
        echo "  ⚠ SSL cert request failed. Will start without SSL."
        echo "  Make sure DNS A record for $DOMAIN points to 165.232.177.81"
    fi
else
    echo "  ✓ SSL certificate already exists"
fi

# ─── 7. Start Services ───
echo ""
echo "═══ Step 7: Starting Services ═══"
cd $DEPLOY_DIR

# If no SSL cert, use HTTP-only nginx config
if [ ! -f "$DEPLOY_DIR/ssl/live/$DOMAIN/fullchain.pem" ]; then
    echo "→ SSL cert not available, using HTTP-only mode..."
    cp nginx/nginx-http.conf nginx/nginx.conf
fi

export DOCKER_IMAGE=chizze-api:latest
docker compose -f docker-compose.prod.yml up -d --remove-orphans

echo "→ Waiting for services to start..."
sleep 10

# ─── 8. Health Check ───
echo ""
echo "═══ Step 8: Health Check ═══"
MAX=20
for i in $(seq 1 $MAX); do
    if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        echo ""
        echo "═══════════════════════════════════════"
        echo "  ✅ DEPLOYMENT SUCCESSFUL!"
        echo "═══════════════════════════════════════"
        echo ""
        docker compose -f docker-compose.prod.yml ps
        echo ""
        echo "API Health:"
        curl -s http://localhost:8080/health 2>/dev/null | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8080/health
        echo ""
        echo ""
        echo "Endpoints:"
        echo "  HTTP:  http://165.232.177.81/health"
        if [ -f "$DEPLOY_DIR/ssl/live/$DOMAIN/fullchain.pem" ]; then
            echo "  HTTPS: https://$DOMAIN/health"
            echo "  API:   https://$DOMAIN/api/v1/"
        fi
        echo ""
        echo "Logs:  docker compose -f docker-compose.prod.yml logs -f"
        echo "Stop:  docker compose -f docker-compose.prod.yml down"
        exit 0
    fi
    printf "  Waiting... %d/%d\r" "$i" "$MAX"
    sleep 3
done

echo ""
echo "❌ Health check failed after $MAX attempts"
echo "→ Checking logs..."
docker compose -f docker-compose.prod.yml logs --tail=50
exit 1
