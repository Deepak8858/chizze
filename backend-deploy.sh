#!/bin/bash
# ═══════════════════════════════════════════════════════
# Chizze Backend — One-Command Deploy to Production
# Usage: bash backend-deploy.sh
# ═══════════════════════════════════════════════════════
set -euo pipefail

# ── Config ──
VM_HOST="34.131.63.117"
VM_USER="deepakupkgs"
SSH_KEY="$HOME/.ssh/google-vm-key"
REMOTE_DIR="/home/$VM_USER/chizze/backend"
LOCAL_BACKEND="$(dirname "$0")/backend"
SSH_CMD="ssh -i $SSH_KEY -o ConnectTimeout=10 $VM_USER@$VM_HOST"
SCP_CMD="scp -i $SSH_KEY"

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
ok()    { echo -e "${GREEN}  ✔ $1${NC}"; }
warn()  { echo -e "${YELLOW}  ⚠ $1${NC}"; }
fail()  { echo -e "${RED}  ✘ $1${NC}"; exit 1; }

# ── Pre-flight checks ──
log "Pre-flight checks..."
[ -d "$LOCAL_BACKEND" ] || fail "Backend directory not found at $LOCAL_BACKEND"
[ -f "$SSH_KEY" ]       || fail "SSH key not found at $SSH_KEY"
$SSH_CMD "echo ok" > /dev/null 2>&1 || fail "Cannot connect to $VM_HOST"
ok "Connection verified"

# ── Sync files (exclude build artifacts, .env, vendor cache) ──
log "Syncing backend files to $VM_HOST..."
rsync -avz --delete \
  --exclude '.env' \
  --exclude 'bin/' \
  --exclude 'server.exe' \
  --exclude '.gomod/' \
  --exclude '.gopath/' \
  --exclude 'coverage/' \
  -e "ssh -i $SSH_KEY" \
  "$LOCAL_BACKEND/" "$VM_USER@$VM_HOST:$REMOTE_DIR/"
ok "Files synced"

# ── Build new image ──
log "Building new Docker image..."
$SSH_CMD "cd $REMOTE_DIR && sudo docker compose build --no-cache api" || fail "Docker build failed"
ok "Image built"

# ── Rolling restart (zero-downtime) ──
log "Deploying with rolling restart..."
$SSH_CMD "cd $REMOTE_DIR && sudo docker compose up -d --force-recreate --no-deps api"
ok "Container recreated"

# ── Wait for health check ──
log "Waiting for health check..."
RETRIES=0
MAX_RETRIES=15
until $SSH_CMD "curl -sf http://localhost:8080/health > /dev/null 2>&1"; do
  RETRIES=$((RETRIES + 1))
  if [ $RETRIES -ge $MAX_RETRIES ]; then
    warn "Health check failed after ${MAX_RETRIES}s. Checking logs..."
    $SSH_CMD "sudo docker logs backend-api-1 --tail 20"
    fail "Deploy failed — API not healthy"
  fi
  sleep 1
done
ok "API healthy (took ${RETRIES}s)"

# ── Verify endpoints ──
log "Verifying key endpoints..."
API="https://api.devdeepak.me"
check_endpoint() {
  local path=$1
  local expected_code=${2:-200}
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$API$path" 2>/dev/null || echo "000")
  if [ "$code" = "$expected_code" ]; then
    ok "$path → $code"
  else
    warn "$path → $code (expected $expected_code)"
  fi
}

check_endpoint "/health"
check_endpoint "/api/v1/restaurants"
check_endpoint "/api/v1/coupons"

# ── Show status ──
log "Deployment complete!"
echo ""
$SSH_CMD "sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E '(NAMES|backend)'"
echo ""
$SSH_CMD "curl -s http://localhost:8080/health"
echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  Deploy successful at $(date +%H:%M:%S) ${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
