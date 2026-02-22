#!/bin/bash
# ══════════════════════════════════════════
# Chizze — Manual Deploy Script
# ══════════════════════════════════════════
# For manual deploys when CI/CD is not available
# Usage: bash deploy.sh [image-tag]
# ══════════════════════════════════════════

set -euo pipefail

TAG=${1:-latest}
DEPLOY_DIR="/opt/chizze"
IMAGE="ghcr.io/chizze/chizze-api:${TAG}"

echo "═══════════════════════════════════════"
echo "  Chizze Deploy — tag: $TAG"
echo "═══════════════════════════════════════"

cd "$DEPLOY_DIR"

# ─── Validate environment ───
if [ ! -f .env.prod ]; then
    echo "❌ Missing .env.prod — copy from .env.example and fill in values"
    exit 1
fi

# ─── Pull latest image ───
echo "→ Pulling image: $IMAGE"
docker pull "$IMAGE" || {
    echo "❌ Failed to pull image. Check registry auth."
    exit 1
}

# ─── Save current image for rollback ───
CURRENT_IMAGE=$(docker compose -f docker-compose.prod.yml images api -q 2>/dev/null || echo "")
echo "  Current image: ${CURRENT_IMAGE:-none}"

# ─── Deploy ───
echo "→ Starting deployment..."
export DOCKER_IMAGE="$IMAGE"
docker compose -f docker-compose.prod.yml up -d --remove-orphans

# ─── Health check ───
echo "→ Waiting for health check..."
MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
    if curl -sf http://localhost:8080/health/ready > /dev/null 2>&1; then
        echo ""
        echo "═══════════════════════════════════════"
        echo "  ✅ Deploy successful! (attempt $i/$MAX_ATTEMPTS)"
        echo "═══════════════════════════════════════"
        
        # Show status
        docker compose -f docker-compose.prod.yml ps
        echo ""
        curl -s http://localhost:8080/health | python3 -m json.tool 2>/dev/null || true
        exit 0
    fi
    printf "  Attempt %d/%d...\r" "$i" "$MAX_ATTEMPTS"
    sleep 2
done

# ─── Rollback on failure ───
echo ""
echo "❌ Health check failed after $MAX_ATTEMPTS attempts"
echo "→ Rolling back..."

if [ -n "$CURRENT_IMAGE" ]; then
    export DOCKER_IMAGE="$CURRENT_IMAGE"
    docker compose -f docker-compose.prod.yml up -d --remove-orphans
    echo "  Rolled back to: $CURRENT_IMAGE"
else
    docker compose -f docker-compose.prod.yml down
    echo "  No previous image — services stopped"
fi

exit 1
