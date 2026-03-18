# ═══════════════════════════════════════════════════════
# Chizze Admin Panel — One-Click Deploy to Production
# Usage: pwsh .\deploy-admin.ps1
# ═══════════════════════════════════════════════════════
$ErrorActionPreference = "Stop"

# ── Config ──
$VM       = "34.131.63.117"
$VM_USER  = "deepakupkgs"
$SSH_KEY  = "$env:USERPROFILE\.ssh\google-vm-key"
$REMOTE   = "/home/$VM_USER/chizze/admin"
$LOCAL    = "$PSScriptRoot\admin"
$SSH      = "ssh -i $SSH_KEY -o ConnectTimeout=10 ${VM_USER}@${VM}"
$SCP      = "scp -i $SSH_KEY"

function Log($msg)  { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  ✔ $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "  ✘ $msg" -ForegroundColor Red; exit 1 }

# ── Pre-flight ──
Log "Pre-flight checks..."
if (-not (Test-Path $LOCAL))   { Fail "Admin dir not found: $LOCAL" }
if (-not (Test-Path $SSH_KEY)) { Fail "SSH key not found: $SSH_KEY" }
$null = Invoke-Expression "$SSH 'echo ok'" 2>&1
if ($LASTEXITCODE -ne 0) { Fail "Cannot connect to $VM" }
Ok "Connection verified"

# ── Sync files via scp ──
Log "Syncing admin source files..."

# Key directories to sync
$dirs = @(
    @{ local = "$LOCAL\app";        remote = "$REMOTE/app" },
    @{ local = "$LOCAL\components"; remote = "$REMOTE/components" },
    @{ local = "$LOCAL\lib";        remote = "$REMOTE/lib" },
    @{ local = "$LOCAL\hooks";      remote = "$REMOTE/hooks" },
    @{ local = "$LOCAL\public";     remote = "$REMOTE/public" },
    @{ local = "$LOCAL\types";      remote = "$REMOTE/types" },
    @{ local = "$LOCAL\styles";     remote = "$REMOTE/styles" }
)

foreach ($d in $dirs) {
    if (Test-Path $d.local) {
        Invoke-Expression "$SSH 'mkdir -p $($d.remote)'"
        Invoke-Expression "$SCP -r $($d.local) ${VM_USER}@${VM}:$(Split-Path $d.remote -Parent)/"
        if ($LASTEXITCODE -ne 0) { Fail "Failed to copy $($d.local)" }
    }
}

# Copy root config files
$rootFiles = @(
    "package.json", "package-lock.json", "next.config.ts",
    "tailwind.config.ts", "postcss.config.mjs", "tsconfig.json",
    ".env.local", ".env.production", "middleware.ts"
)
foreach ($f in $rootFiles) {
    $fp = "$LOCAL\$f"
    if (Test-Path $fp) {
        Invoke-Expression "$SCP '$fp' ${VM_USER}@${VM}:$REMOTE/$f"
    }
}
Ok "Files synced"

# ── Install deps if package.json changed ──
Log "Installing dependencies..."
Invoke-Expression "$SSH 'cd $REMOTE && npm ci --production=false 2>&1'"
Ok "Dependencies installed"

# ── Build ──
Log "Building Next.js app (this may take 1–3 minutes)..."
Invoke-Expression "$SSH 'cd $REMOTE && npm run build 2>&1'"
if ($LASTEXITCODE -ne 0) {
    Fail "Next.js build failed"
}
Ok "Build succeeded"

# ── Restart PM2 ──
Log "Restarting PM2 process..."
$pm2Status = Invoke-Expression "$SSH 'pm2 list 2>&1'" 2>$null
if ($pm2Status -match "chizze-admin") {
    Invoke-Expression "$SSH 'pm2 restart chizze-admin 2>&1'"
    Ok "PM2 restarted (chizze-admin)"
} else {
    Invoke-Expression "$SSH 'cd $REMOTE && pm2 start npm --name chizze-admin -- start 2>&1'"
    Ok "PM2 started new process (chizze-admin)"
}

# ── Health check ──
Log "Waiting for admin panel..."
$retries = 0
$maxRetries = 15
do {
    Start-Sleep -Seconds 2
    $retries++
    $code = Invoke-Expression "$SSH 'curl -s -o /dev/null -w ""%{http_code}"" http://localhost:3000 2>/dev/null'" 2>$null
} while ($code -ne "200" -and $retries -lt $maxRetries)

if ($code -ne "200") {
    Warn "Health check returned $code. PM2 logs:"
    Invoke-Expression "$SSH 'pm2 logs chizze-admin --lines 20 --nostream 2>&1'"
    Fail "Admin deploy FAILED — panel not responding"
}
Ok "Admin panel healthy (took ~$($retries * 2)s)"

# ── Done ──
Write-Host ""
Invoke-Expression "$SSH 'pm2 list 2>&1'"
Write-Host ""
Write-Host "═══════════════════════════════════════" -ForegroundColor Green
Write-Host "  Admin deploy SUCCESS $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Green
Write-Host "═══════════════════════════════════════" -ForegroundColor Green
