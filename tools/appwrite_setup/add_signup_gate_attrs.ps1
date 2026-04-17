# ╔═══════════════════════════════════════════════════════════╗
# ║ Add admin-controlled partner-signup gate attributes to    ║
# ║ the `settings` collection in Appwrite.                    ║
# ╚═══════════════════════════════════════════════════════════╝
#
# The backend's `isPartnerSignupAllowed` reads these two booleans from the
# `settings` collection; if the attributes don't exist, admin toggle saves
# are silently dropped by the UpdateSettings fallback chain and new
# restaurant/delivery-partner signups are NOT blocked.
#
# Usage:
#   appwrite login   # (once per machine)
#   appwrite client --endpoint https://sgp.cloud.appwrite.io/v1 --project-id 6993347c0006ead7404d
#   powershell -ExecutionPolicy Bypass -File add_signup_gate_attrs.ps1

$ErrorActionPreference = "Continue"
$DB   = "chizze_db"
$COLL = "settings"

Write-Host "`nAdding partner-signup gate attributes to settings collection..." -ForegroundColor Cyan

# Create the collection if missing (idempotent; silently fails if present).
appwrite databases create-collection `
    --database-id $DB `
    --collection-id $COLL `
    --name Settings `
    --document-security true `
    --permissions 'read("any")' 2>&1 | Out-Null

# Boolean attributes for the admin signup toggles.
# `--default true` matches the backend's default-allow behavior so a newly
# seeded doc does not lock out partner signups.
appwrite databases create-boolean-attribute `
    --database-id $DB `
    --collection-id $COLL `
    --key allow_restaurant_partner_signup `
    --required false `
    --default true 2>&1 | Tee-Object -Variable r1

appwrite databases create-boolean-attribute `
    --database-id $DB `
    --collection-id $COLL `
    --key allow_delivery_partner_signup `
    --required false `
    --default true 2>&1 | Tee-Object -Variable r2

# Also ensure maintenance_mode exists since admin UI writes it.
appwrite databases create-boolean-attribute `
    --database-id $DB `
    --collection-id $COLL `
    --key maintenance_mode `
    --required false `
    --default false 2>&1 | Out-Null

Start-Sleep -Seconds 3

Write-Host "`nSeeding a default settings doc if none exists..." -ForegroundColor Cyan
$existing = appwrite databases list-documents --database-id $DB --collection-id $COLL --queries 'limit(1)' 2>&1
if ($LASTEXITCODE -ne 0 -or $existing -notmatch '"total":\s*[1-9]') {
    appwrite databases create-document `
        --database-id $DB `
        --collection-id $COLL `
        --document-id platform_settings `
        --data '{"allow_restaurant_partner_signup":true,"allow_delivery_partner_signup":true,"maintenance_mode":false}' 2>&1 | Out-Null
    Write-Host "  seeded platform_settings doc" -ForegroundColor Green
} else {
    Write-Host "  settings doc already exists — skipping seed" -ForegroundColor Yellow
}

Write-Host "`nDone. Re-test the admin toggle; it should persist and the gate should block new partner signups." -ForegroundColor Green
