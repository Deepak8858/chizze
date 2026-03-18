# ═══════════════════════════════════════════════════════
# Chizze Backend — One-Click Deploy to Production
# Usage: pwsh .\deploy-backend.ps1
# ═══════════════════════════════════════════════════════
$ErrorActionPreference = "Stop"

# ── Config ──
$VM       = "34.131.63.117"
$VM_USER  = "deepakupkgs"
$SSH_KEY  = "$env:USERPROFILE\.ssh\google-vm-key"
$REMOTE   = "/home/$VM_USER/chizze/backend"
$LOCAL    = "$PSScriptRoot\backend"
$SSH      = "ssh -i $SSH_KEY -o ConnectTimeout=10 ${VM_USER}@${VM}"
$SCP      = "scp -i $SSH_KEY"

function Log($msg)  { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  ✔ $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "  ✘ $msg" -ForegroundColor Red; exit 1 }

# ── Pre-flight ──
Log "Pre-flight checks..."
if (-not (Test-Path $LOCAL))   { Fail "Backend dir not found: $LOCAL" }
if (-not (Test-Path $SSH_KEY)) { Fail "SSH key not found: $SSH_KEY" }
$null = Invoke-Expression "$SSH 'echo ok'" 2>&1
if ($LASTEXITCODE -ne 0) { Fail "Cannot connect to $VM" }
Ok "Connection verified"

# ── Sync files via scp ──
Log "Syncing backend source files..."

# Key directories to sync
$dirs = @(
    @{ local = "$LOCAL\cmd";                remote = "$REMOTE/cmd" },
    @{ local = "$LOCAL\internal";           remote = "$REMOTE/internal" },
    @{ local = "$LOCAL\pkg";                remote = "$REMOTE/pkg" }
)

foreach ($d in $dirs) {
    if (Test-Path $d.local) {
        Invoke-Expression "$SSH 'mkdir -p $($d.remote)'"
        Invoke-Expression "$SCP -r $($d.local) ${VM_USER}@${VM}:$(Split-Path $d.remote -Parent)/"
        if ($LASTEXITCODE -ne 0) { Fail "Failed to copy $($d.local)" }
    }
}

# Copy root files (go.mod, go.sum, Dockerfile, docker-compose.yml, .dockerignore)
$rootFiles = @("go.mod", "go.sum", "Dockerfile", "docker-compose.yml", ".dockerignore")
foreach ($f in $rootFiles) {
    $fp = "$LOCAL\$f"
    if (Test-Path $fp) {
        Invoke-Expression "$SCP '$fp' ${VM_USER}@${VM}:$REMOTE/$f"
    }
}
Ok "Files synced"

# ── Build & deploy ──
Log "Building Docker image + restarting..."
Invoke-Expression "$SSH 'cd $REMOTE && docker compose up -d --build --force-recreate api 2>&1'"
if ($LASTEXITCODE -ne 0) { Fail "Docker build/deploy failed" }
Ok "Container rebuilt"

# ── Health check ──
Log "Waiting for health check..."
$retries = 0
$maxRetries = 20
do {
    Start-Sleep -Seconds 2
    $retries++
    $health = Invoke-Expression "$SSH 'curl -sf http://localhost:8080/health 2>/dev/null'" 2>$null
} while ($LASTEXITCODE -ne 0 -and $retries -lt $maxRetries)

if ($LASTEXITCODE -ne 0) {
    Warn "Health check failed. Container logs:"
    Invoke-Expression "$SSH 'docker logs backend-api-1 --tail 20 2>&1'"
    Fail "Backend deploy FAILED — API not healthy"
}
Ok "API healthy (took ~$($retries * 2)s)"

# ── Ensure nginx WebSocket path is correct (/api/v1/ws not /ws) ──
Log "Checking nginx WebSocket location..."
$nginxWsCheck = Invoke-Expression "$SSH 'grep -c ""location /api/v1/ws"" /etc/nginx/sites-enabled/chizze-api 2>/dev/null'" 2>$null
if ($nginxWsCheck -eq "0" -or $LASTEXITCODE -ne 0) {
    Warn "nginx missing /api/v1/ws location — fixing now..."
    Invoke-Expression "$SSH 'sudo sed -i ""s|location /ws {|location /api/v1/ws {|g"" /etc/nginx/sites-enabled/chizze-api && sudo nginx -t && sudo nginx -s reload'"
    if ($LASTEXITCODE -eq 0) { Ok "nginx WebSocket location fixed and reloaded" }
    else { Warn "nginx fix failed — check manually: sudo nano /etc/nginx/sites-enabled/chizze-api" }
} else {
    Ok "nginx WebSocket location /api/v1/ws is correct"
}

# ── Clear stale Redis delivery state on every deploy ──
Log "Clearing stale Redis delivery state..."
Invoke-Expression "$SSH 'docker exec backend-redis-1 redis-cli DEL busy_riders pending_riders > /dev/null && docker exec backend-redis-1 redis-cli KEYS ""pending_rider:*"" | xargs -r docker exec -i backend-redis-1 redis-cli DEL > /dev/null && docker exec backend-redis-1 redis-cli KEYS ""pending_delivery:*"" | xargs -r docker exec -i backend-redis-1 redis-cli DEL > /dev/null && echo ok'" 2>$null
Ok "Stale Redis delivery state cleared"

# ── Verify key endpoints ──
Log "Verifying endpoints..."
$endpoints = @("/health", "/api/v1/restaurants")
foreach ($ep in $endpoints) {
    $code = Invoke-Expression "$SSH 'curl -s -o /dev/null -w ""%{http_code}"" http://localhost:8080$ep'" 2>$null
    Ok "$ep → $code"
}

# ── Done ──
Write-Host ""
Invoke-Expression "$SSH 'docker ps --format ""table {{.Names}}\t{{.Status}}"" | grep backend'"
Write-Host ""
Write-Host "═══════════════════════════════════════" -ForegroundColor Green
Write-Host "  Backend deploy SUCCESS $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Green
Write-Host "═══════════════════════════════════════" -ForegroundColor Green
