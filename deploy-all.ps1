# ═══════════════════════════════════════════════════════
# Chizze Full Stack — One-Click Deploy (Backend + Admin)
# Usage: pwsh .\deploy-all.ps1
# ═══════════════════════════════════════════════════════
param(
    [switch]$BackendOnly,
    [switch]$AdminOnly
)

$ErrorActionPreference = "Stop"
$startTime = Get-Date

Write-Host ""
Write-Host "╔═══════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║     CHIZZE — Full Stack Deploy        ║" -ForegroundColor Magenta
Write-Host "╚═══════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

$backendScript = "$PSScriptRoot\deploy-backend.ps1"
$adminScript   = "$PSScriptRoot\deploy-admin.ps1"

# ── Backend ──
if (-not $AdminOnly) {
    Write-Host "━━━ STAGE 1: BACKEND ━━━" -ForegroundColor Yellow
    if (-not (Test-Path $backendScript)) {
        Write-Host "  ✘ deploy-backend.ps1 not found at $backendScript" -ForegroundColor Red
        exit 1
    }
    & $backendScript
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ✘ Backend deploy failed — aborting" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

# ── Admin ──
if (-not $BackendOnly) {
    Write-Host "━━━ STAGE 2: ADMIN PANEL ━━━" -ForegroundColor Yellow
    if (-not (Test-Path $adminScript)) {
        Write-Host "  ✘ deploy-admin.ps1 not found at $adminScript" -ForegroundColor Red
        exit 1
    }
    & $adminScript
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ✘ Admin deploy failed" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

# ── Summary ──
$elapsed = (Get-Date) - $startTime
Write-Host ""
Write-Host "╔═══════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   ALL DEPLOYMENTS COMPLETE            ║" -ForegroundColor Green
Write-Host "║   Total time: $($elapsed.Minutes)m $($elapsed.Seconds)s                    ║" -ForegroundColor Green
Write-Host "║                                       ║" -ForegroundColor Green
Write-Host "║   API:   https://api.devdeepak.me     ║" -ForegroundColor Green
Write-Host "║   Admin: https://admin.devdeepak.me   ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════╝" -ForegroundColor Green
