# Adds preparing_at + accepted_at datetime attributes to the orders collection.
# Idempotent: safe to re-run; Appwrite returns a 409 for existing attributes
# which we ignore.
#
# Prereqs (one-time):
#   appwrite login
#   appwrite client --endpoint https://sgp.cloud.appwrite.io/v1 --project-id 6993347c0006ead7404d
#
# Usage:
#   cd tools/appwrite_setup
#   powershell -ExecutionPolicy Bypass -File add_order_timestamps.ps1

$ErrorActionPreference = "Continue"
$DB = "chizze_db"
$COLL = "orders"

Write-Host "Adding preparing_at to ${COLL}..." -ForegroundColor Yellow
appwrite databases create-datetime-attribute --database-id $DB --collection-id $COLL --key preparing_at --required $false

Write-Host "Adding accepted_at to ${COLL}..." -ForegroundColor Yellow
appwrite databases create-datetime-attribute --database-id $DB --collection-id $COLL --key accepted_at --required $false

Write-Host ""
Write-Host "Done. Verify in Appwrite console -> Databases -> chizze_db -> orders." -ForegroundColor Green
Write-Host "If a 409 'attribute already exists' shows above, that is expected and safe." -ForegroundColor DarkGray
