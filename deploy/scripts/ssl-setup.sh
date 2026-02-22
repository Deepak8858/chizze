#!/bin/bash
# ══════════════════════════════════════════
# Chizze — SSL Certificate Setup (Let's Encrypt)
# ══════════════════════════════════════════
# Usage: bash ssl-setup.sh api.devdeepak.me
# ══════════════════════════════════════════

set -euo pipefail

DOMAIN=${1:-api.devdeepak.me}
EMAIL=${2:-admin@devdeepak.me}
DEPLOY_DIR="/opt/chizze"

echo "═══════════════════════════════════════"
echo "  SSL Setup for: $DOMAIN"
echo "═══════════════════════════════════════"

cd "$DEPLOY_DIR"

# ─── 1. Create temp Nginx for ACME challenge ───
echo "→ Starting temporary Nginx for certificate verification..."
mkdir -p certbot/www ssl

# Temporary Nginx config (HTTP only, for ACME)
cat > /tmp/nginx-acme.conf << 'EOF'
server {
    listen 80;
    server_name _;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        return 200 'Chizze SSL setup in progress';
    }
}
EOF

docker run -d --name nginx-acme \
    -p 80:80 \
    -v /tmp/nginx-acme.conf:/etc/nginx/conf.d/default.conf:ro \
    -v "$DEPLOY_DIR/certbot/www:/var/www/certbot" \
    nginx:1.25-alpine

sleep 2

# ─── 2. Request certificate ───
echo "→ Requesting certificate from Let's Encrypt..."
docker run --rm \
    -v "$DEPLOY_DIR/ssl:/etc/letsencrypt" \
    -v "$DEPLOY_DIR/certbot/www:/var/www/certbot" \
    certbot/certbot certonly \
    --webroot -w /var/www/certbot \
    -d "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --non-interactive

# ─── 3. Cleanup temp container ───
docker stop nginx-acme && docker rm nginx-acme

echo ""
echo "═══════════════════════════════════════"
echo "  ✅ SSL certificate obtained!"
echo "═══════════════════════════════════════"
echo ""
echo "Certificate location: $DEPLOY_DIR/ssl/live/$DOMAIN/"
echo ""
echo "Start production stack:"
echo "  cd $DEPLOY_DIR"
echo "  docker compose -f docker-compose.prod.yml up -d"
