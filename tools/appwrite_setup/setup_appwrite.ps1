# ╔══════════════════════════════════════════════════╗
# ║  🍕 CHIZZE — Appwrite Database Setup (CLI)      ║
# ╚══════════════════════════════════════════════════╝
#
# Usage:
#   cd tools/appwrite_setup
#   powershell -ExecutionPolicy Bypass -File setup_appwrite.ps1
#
# Prerequisites:
#   appwrite login
#   appwrite client --endpoint https://sgp.cloud.appwrite.io/v1 --project-id 6993347c0006ead7404d

$ErrorActionPreference = "Continue"
$DB = "chizze_db"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  🍕 CHIZZE — Appwrite Database Setup        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ─── 1. Create Database ──────────────────────────────────────────────────────
Write-Host "📦 Creating database: $DB ..." -ForegroundColor Yellow
appwrite databases create --database-id $DB --name "Chizze Database"

# ─── 2. USERS Collection ─────────────────────────────────────────────────────
Write-Host "`n👤 Creating collection: users ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id users --name Users --document-security true --permissions 'read("any")' 'create("users")' 'update("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id users --key name --size 128 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id users --key phone --size 20 --required true
appwrite databases create-email-attribute --database-id $DB --collection-id users --key email --required false
appwrite databases create-url-attribute --database-id $DB --collection-id users --key avatar_url --required false
appwrite databases create-string-attribute --database-id $DB --collection-id users --key role --size 20 --required false --default customer
appwrite databases create-boolean-attribute --database-id $DB --collection-id users --key is_veg --required false --default false
appwrite databases create-boolean-attribute --database-id $DB --collection-id users --key dark_mode --required false --default true
appwrite databases create-string-attribute --database-id $DB --collection-id users --key default_address_id --size 36 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id users --key fcm_token --size 256 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id users --key address --size 500 --required false
appwrite databases create-float-attribute --database-id $DB --collection-id users --key latitude --required false
appwrite databases create-float-attribute --database-id $DB --collection-id users --key longitude --required false
appwrite databases create-boolean-attribute --database-id $DB --collection-id users --key is_gold_member --required false --default false
appwrite databases create-string-attribute --database-id $DB --collection-id users --key referral_code --size 20 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id users --key referred_by --size 20 --required false

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id users --key idx_phone --type unique --attributes phone
appwrite databases create-index --database-id $DB --collection-id users --key idx_role --type key --attributes role
Write-Host "   ✅ users (15 attributes, 2 indexes)" -ForegroundColor Green

# ─── 3. ADDRESSES Collection ─────────────────────────────────────────────────
Write-Host "`n📍 Creating collection: addresses ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id addresses --name Addresses --document-security true --permissions 'read("users")' 'create("users")' 'update("users")' 'delete("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id addresses --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id addresses --key label --size 50 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id addresses --key full_address --size 500 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id addresses --key landmark --size 200 --required false
appwrite databases create-float-attribute --database-id $DB --collection-id addresses --key latitude --required false
appwrite databases create-float-attribute --database-id $DB --collection-id addresses --key longitude --required false
appwrite databases create-boolean-attribute --database-id $DB --collection-id addresses --key is_default --required false --default false

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id addresses --key idx_user --type key --attributes user_id
Write-Host "   ✅ addresses (7 attributes, 1 index)" -ForegroundColor Green

# ─── 4. RESTAURANTS Collection ────────────────────────────────────────────────
Write-Host "`n🍽️  Creating collection: restaurants ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id restaurants --name Restaurants --document-security false --permissions 'read("any")' 'create("users")' 'update("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id restaurants --key owner_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id restaurants --key name --size 128 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id restaurants --key description --size 500 --required false
appwrite databases create-url-attribute --database-id $DB --collection-id restaurants --key cover_image_url --required false
appwrite databases create-url-attribute --database-id $DB --collection-id restaurants --key logo_url --required false
appwrite databases create-string-attribute --database-id $DB --collection-id restaurants --key cuisines --size 100 --required false --array true
appwrite databases create-string-attribute --database-id $DB --collection-id restaurants --key address --size 500 --required true
appwrite databases create-float-attribute --database-id $DB --collection-id restaurants --key latitude --required false
appwrite databases create-float-attribute --database-id $DB --collection-id restaurants --key longitude --required false
appwrite databases create-string-attribute --database-id $DB --collection-id restaurants --key city --size 100 --required true
appwrite databases create-float-attribute --database-id $DB --collection-id restaurants --key rating --required false
appwrite databases create-integer-attribute --database-id $DB --collection-id restaurants --key total_ratings --required false
appwrite databases create-integer-attribute --database-id $DB --collection-id restaurants --key price_for_two --required false
appwrite databases create-integer-attribute --database-id $DB --collection-id restaurants --key avg_delivery_time_min --required false
appwrite databases create-boolean-attribute --database-id $DB --collection-id restaurants --key is_veg_only --required false --default false
appwrite databases create-boolean-attribute --database-id $DB --collection-id restaurants --key is_online --required false --default true
appwrite databases create-boolean-attribute --database-id $DB --collection-id restaurants --key is_featured --required false --default false
appwrite databases create-boolean-attribute --database-id $DB --collection-id restaurants --key is_promoted --required false --default false
appwrite databases create-string-attribute --database-id $DB --collection-id restaurants --key opening_time --size 10 --required false --default "09:00"
appwrite databases create-string-attribute --database-id $DB --collection-id restaurants --key closing_time --size 10 --required false --default "23:00"
appwrite databases create-string-attribute --database-id $DB --collection-id restaurants --key bank_account_name --size 128 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id restaurants --key bank_account_number --size 50 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id restaurants --key bank_ifsc --size 20 --required false

Start-Sleep -Seconds 5
appwrite databases create-index --database-id $DB --collection-id restaurants --key idx_owner --type key --attributes owner_id
appwrite databases create-index --database-id $DB --collection-id restaurants --key idx_city --type key --attributes city
appwrite databases create-index --database-id $DB --collection-id restaurants --key idx_online --type key --attributes is_online
appwrite databases create-index --database-id $DB --collection-id restaurants --key idx_featured --type key --attributes is_featured
appwrite databases create-index --database-id $DB --collection-id restaurants --key idx_rating --type key --attributes rating --orders DESC
appwrite databases create-index --database-id $DB --collection-id restaurants --key idx_name --type fulltext --attributes name
Write-Host "   ✅ restaurants (23 attributes, 6 indexes)" -ForegroundColor Green

# ─── 5. MENU_CATEGORIES Collection ───────────────────────────────────────────
Write-Host "`n📂 Creating collection: menu_categories ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id menu_categories --name "Menu Categories" --document-security false --permissions 'read("any")' 'create("users")' 'update("users")' 'delete("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id menu_categories --key restaurant_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id menu_categories --key name --size 100 --required true
appwrite databases create-integer-attribute --database-id $DB --collection-id menu_categories --key sort_order --required false
appwrite databases create-boolean-attribute --database-id $DB --collection-id menu_categories --key is_active --required false --default true

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id menu_categories --key idx_restaurant --type key --attributes restaurant_id
Write-Host "   ✅ menu_categories (4 attributes, 1 index)" -ForegroundColor Green

# ─── 6. MENU_ITEMS Collection ────────────────────────────────────────────────
Write-Host "`n🍔 Creating collection: menu_items ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id menu_items --name "Menu Items" --document-security false --permissions 'read("any")' 'create("users")' 'update("users")' 'delete("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id menu_items --key restaurant_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id menu_items --key category_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id menu_items --key name --size 200 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id menu_items --key description --size 1000 --required false
appwrite databases create-float-attribute --database-id $DB --collection-id menu_items --key price --required true
appwrite databases create-url-attribute --database-id $DB --collection-id menu_items --key image_url --required false
appwrite databases create-boolean-attribute --database-id $DB --collection-id menu_items --key is_veg --required true
appwrite databases create-boolean-attribute --database-id $DB --collection-id menu_items --key is_available --required false --default true
appwrite databases create-boolean-attribute --database-id $DB --collection-id menu_items --key is_bestseller --required false --default false
appwrite databases create-boolean-attribute --database-id $DB --collection-id menu_items --key is_must_try --required false --default false
appwrite databases create-enum-attribute --database-id $DB --collection-id menu_items --key spice_level --elements mild medium spicy extra_spicy --required false --default mild
appwrite databases create-integer-attribute --database-id $DB --collection-id menu_items --key preparation_time_min --required false
appwrite databases create-string-attribute --database-id $DB --collection-id menu_items --key customizations --size 5000 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id menu_items --key add_ons --size 5000 --required false --array true
appwrite databases create-string-attribute --database-id $DB --collection-id menu_items --key variants --size 5000 --required false --array true
appwrite databases create-integer-attribute --database-id $DB --collection-id menu_items --key calories --required false
appwrite databases create-string-attribute --database-id $DB --collection-id menu_items --key allergens --size 200 --required false --array true
appwrite databases create-integer-attribute --database-id $DB --collection-id menu_items --key sort_order --required false

Start-Sleep -Seconds 5
appwrite databases create-index --database-id $DB --collection-id menu_items --key idx_restaurant --type key --attributes restaurant_id
appwrite databases create-index --database-id $DB --collection-id menu_items --key idx_category --type key --attributes category_id
appwrite databases create-index --database-id $DB --collection-id menu_items --key idx_veg --type key --attributes is_veg
appwrite databases create-index --database-id $DB --collection-id menu_items --key idx_name --type fulltext --attributes name
Write-Host "   ✅ menu_items (18 attributes, 4 indexes)" -ForegroundColor Green

# ─── 7. ORDERS Collection ────────────────────────────────────────────────────
Write-Host "`n📋 Creating collection: orders ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id orders --name Orders --document-security true --permissions 'read("users")' 'create("users")' 'update("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id orders --key order_number --size 30 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key customer_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key restaurant_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key restaurant_name --size 128 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key delivery_partner_id --size 36 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key delivery_partner_name --size 128 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key delivery_partner_phone --size 20 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key delivery_address_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key items --size 10000 --required true
appwrite databases create-float-attribute --database-id $DB --collection-id orders --key item_total --required true
appwrite databases create-float-attribute --database-id $DB --collection-id orders --key delivery_fee --required false
appwrite databases create-float-attribute --database-id $DB --collection-id orders --key platform_fee --required false
appwrite databases create-float-attribute --database-id $DB --collection-id orders --key gst --required false
appwrite databases create-float-attribute --database-id $DB --collection-id orders --key discount --required false
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key coupon_code --size 30 --required false
appwrite databases create-float-attribute --database-id $DB --collection-id orders --key tip --required false
appwrite databases create-float-attribute --database-id $DB --collection-id orders --key grand_total --required true
appwrite databases create-enum-attribute --database-id $DB --collection-id orders --key payment_method --elements upi card cod wallet netbanking online --required true
appwrite databases create-enum-attribute --database-id $DB --collection-id orders --key payment_status --elements pending paid failed refunded --required true
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key payment_id --size 100 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key razorpay_order_id --size 100 --required false
appwrite databases create-enum-attribute --database-id $DB --collection-id orders --key status --elements placed confirmed preparing ready pickedUp outForDelivery delivered cancelled --required true --default placed
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key special_instructions --size 500 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key delivery_instructions --size 500 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key delivery_proof_url --size 500 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key delivery_otp --size 10 --required false
appwrite databases create-integer-attribute --database-id $DB --collection-id orders --key estimated_delivery_min --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id orders --key placed_at --required true
appwrite databases create-datetime-attribute --database-id $DB --collection-id orders --key confirmed_at --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id orders --key prepared_at --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id orders --key picked_up_at --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id orders --key delivered_at --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id orders --key cancelled_at --required false
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key cancellation_reason --size 500 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id orders --key cancelled_by --size 36 --required false

Start-Sleep -Seconds 5
appwrite databases create-index --database-id $DB --collection-id orders --key idx_customer --type key --attributes customer_id
appwrite databases create-index --database-id $DB --collection-id orders --key idx_restaurant --type key --attributes restaurant_id
appwrite databases create-index --database-id $DB --collection-id orders --key idx_status --type key --attributes status
appwrite databases create-index --database-id $DB --collection-id orders --key idx_rider --type key --attributes delivery_partner_id
appwrite databases create-index --database-id $DB --collection-id orders --key idx_order_num --type unique --attributes order_number
appwrite databases create-index --database-id $DB --collection-id orders --key idx_placed --type key --attributes placed_at --orders DESC
Write-Host "   ✅ orders (35 attributes, 6 indexes)" -ForegroundColor Green

# ─── 8. COUPONS Collection ───────────────────────────────────────────────────
Write-Host "`n🎟️  Creating collection: coupons ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id coupons --name Coupons --document-security false --permissions 'read("any")' 'create("users")' 'update("users")' 'delete("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id coupons --key code --size 30 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id coupons --key title --size 128 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id coupons --key description --size 500 --required false
appwrite databases create-float-attribute --database-id $DB --collection-id coupons --key discount_percent --required true
appwrite databases create-float-attribute --database-id $DB --collection-id coupons --key max_discount --required false
appwrite databases create-float-attribute --database-id $DB --collection-id coupons --key min_order --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id coupons --key expires_at --required true
appwrite databases create-integer-attribute --database-id $DB --collection-id coupons --key usage_limit --required false
appwrite databases create-integer-attribute --database-id $DB --collection-id coupons --key usage_count --required false
appwrite databases create-string-attribute --database-id $DB --collection-id coupons --key restaurant_id --size 36 --required false
appwrite databases create-boolean-attribute --database-id $DB --collection-id coupons --key is_active --required false --default true

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id coupons --key idx_code --type unique --attributes code
appwrite databases create-index --database-id $DB --collection-id coupons --key idx_active --type key --attributes is_active
Write-Host "   ✅ coupons (11 attributes, 2 indexes)" -ForegroundColor Green

# ─── 9. NOTIFICATIONS Collection ─────────────────────────────────────────────
Write-Host "`n🔔 Creating collection: notifications ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id notifications --name Notifications --document-security true --permissions 'read("users")' 'create("users")' 'update("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id notifications --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id notifications --key title --size 200 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id notifications --key body --size 1000 --required true
appwrite databases create-enum-attribute --database-id $DB --collection-id notifications --key type --elements order promo system delivery_update --required true
appwrite databases create-boolean-attribute --database-id $DB --collection-id notifications --key is_read --required false --default false
appwrite databases create-string-attribute --database-id $DB --collection-id notifications --key data --size 2000 --required false

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id notifications --key idx_user --type key --attributes user_id
appwrite databases create-index --database-id $DB --collection-id notifications --key idx_read --type key --attributes is_read
Write-Host "   ✅ notifications (6 attributes, 2 indexes)" -ForegroundColor Green

# ─── 10. DELIVERY_REQUESTS Collection ────────────────────────────────────────
Write-Host "`n🛵 Creating collection: delivery_requests ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id delivery_requests --name "Delivery Requests" --document-security true --permissions 'read("users")' 'create("users")' 'update("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id delivery_requests --key order_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_requests --key rider_id --size 36 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_requests --key restaurant_name --size 128 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_requests --key restaurant_address --size 500 --required false
appwrite databases create-float-attribute --database-id $DB --collection-id delivery_requests --key restaurant_latitude --required false
appwrite databases create-float-attribute --database-id $DB --collection-id delivery_requests --key restaurant_longitude --required false
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_requests --key customer_address --size 500 --required false
appwrite databases create-float-attribute --database-id $DB --collection-id delivery_requests --key customer_latitude --required false
appwrite databases create-float-attribute --database-id $DB --collection-id delivery_requests --key customer_longitude --required false
appwrite databases create-float-attribute --database-id $DB --collection-id delivery_requests --key distance_km --required false
appwrite databases create-float-attribute --database-id $DB --collection-id delivery_requests --key estimated_earning --required false
appwrite databases create-enum-attribute --database-id $DB --collection-id delivery_requests --key status --elements pending accepted rejected expired --required false --default pending
appwrite databases create-datetime-attribute --database-id $DB --collection-id delivery_requests --key expires_at --required true

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id delivery_requests --key idx_rider --type key --attributes rider_id
appwrite databases create-index --database-id $DB --collection-id delivery_requests --key idx_order --type key --attributes order_id
appwrite databases create-index --database-id $DB --collection-id delivery_requests --key idx_status --type key --attributes status
Write-Host "   ✅ delivery_requests (13 attributes, 3 indexes)" -ForegroundColor Green

# ─── 11. RIDER_LOCATIONS Collection ──────────────────────────────────────────
Write-Host "`n📡 Creating collection: rider_locations ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id rider_locations --name "Rider Locations" --document-security true --permissions 'read("users")' 'create("users")' 'update("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id rider_locations --key rider_id --size 36 --required true
appwrite databases create-float-attribute --database-id $DB --collection-id rider_locations --key latitude --required true
appwrite databases create-float-attribute --database-id $DB --collection-id rider_locations --key longitude --required true
appwrite databases create-float-attribute --database-id $DB --collection-id rider_locations --key heading --required false
appwrite databases create-float-attribute --database-id $DB --collection-id rider_locations --key speed --required false
appwrite databases create-boolean-attribute --database-id $DB --collection-id rider_locations --key is_online --required false --default false

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id rider_locations --key idx_rider --type key --attributes rider_id
appwrite databases create-index --database-id $DB --collection-id rider_locations --key idx_online --type key --attributes is_online
Write-Host "   ✅ rider_locations (6 attributes, 2 indexes)" -ForegroundColor Green

# ─── 12. REVIEWS Collection ──────────────────────────────────────────────────
Write-Host "`n⭐ Creating collection: reviews ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id reviews --name Reviews --document-security true --permissions 'read("any")' 'create("users")' 'update("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id reviews --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id reviews --key order_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id reviews --key restaurant_id --size 36 --required true
appwrite databases create-float-attribute --database-id $DB --collection-id reviews --key rating --required true
appwrite databases create-string-attribute --database-id $DB --collection-id reviews --key comment --size 2000 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id reviews --key reply --size 1000 --required false

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id reviews --key idx_restaurant --type key --attributes restaurant_id
appwrite databases create-index --database-id $DB --collection-id reviews --key idx_user --type key --attributes user_id
appwrite databases create-index --database-id $DB --collection-id reviews --key idx_order --type unique --attributes order_id
Write-Host "   ✅ reviews (6 attributes, 3 indexes)" -ForegroundColor Green

# ─── 13. PAYMENTS Collection ─────────────────────────────────────────────────
Write-Host "`n💳 Creating collection: payments ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id payments --name Payments --document-security true --permissions 'read("users")' 'create("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id payments --key order_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id payments --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id payments --key razorpay_order_id --size 100 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id payments --key razorpay_payment_id --size 100 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id payments --key razorpay_signature --size 256 --required false
appwrite databases create-float-attribute --database-id $DB --collection-id payments --key amount --required true
appwrite databases create-enum-attribute --database-id $DB --collection-id payments --key status --elements pending success failed refunded --required true --default pending
appwrite databases create-enum-attribute --database-id $DB --collection-id payments --key method --elements upi card cod wallet netbanking online --required true

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id payments --key idx_order --type key --attributes order_id
appwrite databases create-index --database-id $DB --collection-id payments --key idx_user --type key --attributes user_id
appwrite databases create-index --database-id $DB --collection-id payments --key idx_status --type key --attributes status
Write-Host "   ✅ payments (8 attributes, 3 indexes)" -ForegroundColor Green

# ─── 14. DELIVERY_PARTNERS Collection ─────────────────────────────────────────
Write-Host "`n🚴 Creating collection: delivery_partners ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id delivery_partners --name "Delivery Partners" --document-security true --permissions 'read("users")' 'create("users")' 'update("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key name --size 128 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key phone --size 20 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key email --size 256 --required false
appwrite databases create-url-attribute --database-id $DB --collection-id delivery_partners --key avatar_url --required false
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key vehicle_type --size 20 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key vehicle_number --size 20 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key license_number --size 50 --required false
appwrite databases create-boolean-attribute --database-id $DB --collection-id delivery_partners --key is_verified --required false --default false
appwrite databases create-boolean-attribute --database-id $DB --collection-id delivery_partners --key is_online --required false --default false
appwrite databases create-float-attribute --database-id $DB --collection-id delivery_partners --key rating --required false
appwrite databases create-integer-attribute --database-id $DB --collection-id delivery_partners --key total_deliveries --required false
appwrite databases create-float-attribute --database-id $DB --collection-id delivery_partners --key current_latitude --required false
appwrite databases create-float-attribute --database-id $DB --collection-id delivery_partners --key current_longitude --required false
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key current_order_id --size 36 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key status --size 20 --required false --default available
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key fcm_token --size 256 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key bank_account_name --size 128 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key bank_account_number --size 50 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key bank_ifsc --size 20 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id delivery_partners --key kyc_document_url --size 500 --required false
appwrite databases create-float-attribute --database-id $DB --collection-id delivery_partners --key heading --required false
appwrite databases create-float-attribute --database-id $DB --collection-id delivery_partners --key speed --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id delivery_partners --key last_location_at --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id delivery_partners --key login_at --required false

Start-Sleep -Seconds 5
appwrite databases create-index --database-id $DB --collection-id delivery_partners --key idx_user_id --type key --attributes user_id
Write-Host "   ✅ delivery_partners (25 attributes, 1 index)" -ForegroundColor Green

# ─── 15. FAVORITES Collection ─────────────────────────────────────────────────
Write-Host "`n❤️  Creating collection: favorites ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id favorites --name Favorites --document-security true --permissions 'read("users")' 'create("users")' 'delete("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id favorites --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id favorites --key restaurant_id --size 36 --required true
appwrite databases create-datetime-attribute --database-id $DB --collection-id favorites --key created_at --required false

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id favorites --key idx_user_id --type key --attributes user_id
appwrite databases create-index --database-id $DB --collection-id favorites --key idx_user_restaurant --type unique --attributes user_id restaurant_id
Write-Host "   ✅ favorites (3 attributes, 2 indexes)" -ForegroundColor Green

# ─── 16. GOLD_SUBSCRIPTIONS Collection ────────────────────────────────────────
Write-Host "`n👑 Creating collection: gold_subscriptions ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id gold_subscriptions --name "Gold Subscriptions" --document-security true --permissions 'read("users")' 'create("users")' 'update("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id gold_subscriptions --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id gold_subscriptions --key plan_type --size 20 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id gold_subscriptions --key plan_name --size 50 --required true
appwrite databases create-float-attribute --database-id $DB --collection-id gold_subscriptions --key amount --required true
appwrite databases create-integer-attribute --database-id $DB --collection-id gold_subscriptions --key duration_days --required true
appwrite databases create-string-attribute --database-id $DB --collection-id gold_subscriptions --key payment_id --size 100 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id gold_subscriptions --key status --size 20 --required false --default active
appwrite databases create-datetime-attribute --database-id $DB --collection-id gold_subscriptions --key started_at --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id gold_subscriptions --key expires_at --required false
appwrite databases create-boolean-attribute --database-id $DB --collection-id gold_subscriptions --key auto_renew --required false --default false
appwrite databases create-datetime-attribute --database-id $DB --collection-id gold_subscriptions --key created_at --required false

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id gold_subscriptions --key idx_user_id --type key --attributes user_id
Write-Host "   ✅ gold_subscriptions (11 attributes, 1 index)" -ForegroundColor Green

# ─── 17. REFERRALS Collection ─────────────────────────────────────────────────
Write-Host "`n🤝 Creating collection: referrals ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id referrals --name Referrals --document-security true --permissions 'read("users")' 'create("users")' 'update("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id referrals --key referrer_user_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id referrals --key referred_user_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id referrals --key referral_code --size 20 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id referrals --key status --size 20 --required false --default pending
appwrite databases create-float-attribute --database-id $DB --collection-id referrals --key reward_amount --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id referrals --key created_at --required false

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id referrals --key idx_referrer --type key --attributes referrer_user_id
Write-Host "   ✅ referrals (6 attributes, 1 index)" -ForegroundColor Green

# ─── 18. SCHEDULED_ORDERS Collection ──────────────────────────────────────────
Write-Host "`n⏰ Creating collection: scheduled_orders ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id scheduled_orders --name "Scheduled Orders" --document-security true --permissions 'read("users")' 'create("users")' 'update("users")' 'delete("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id scheduled_orders --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id scheduled_orders --key restaurant_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id scheduled_orders --key items --size 10000 --required true
appwrite databases create-datetime-attribute --database-id $DB --collection-id scheduled_orders --key scheduled_for --required true
appwrite databases create-string-attribute --database-id $DB --collection-id scheduled_orders --key status --size 20 --required false --default pending
appwrite databases create-string-attribute --database-id $DB --collection-id scheduled_orders --key order_id --size 36 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id scheduled_orders --key address_id --size 36 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id scheduled_orders --key coupon_code --size 30 --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id scheduled_orders --key created_at --required false

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id scheduled_orders --key idx_user_id --type key --attributes user_id
Write-Host "   ✅ scheduled_orders (9 attributes, 1 index)" -ForegroundColor Green

# ─── 19. PAYOUTS Collection ───────────────────────────────────────────────────
Write-Host "`n💰 Creating collection: payouts ..." -ForegroundColor Yellow
appwrite databases create-collection --database-id $DB --collection-id payouts --name Payouts --document-security true --permissions 'read("users")' 'create("users")' 'update("users")'

appwrite databases create-string-attribute --database-id $DB --collection-id payouts --key partner_id --size 36 --required true
appwrite databases create-string-attribute --database-id $DB --collection-id payouts --key user_id --size 36 --required false
appwrite databases create-float-attribute --database-id $DB --collection-id payouts --key amount --required true
appwrite databases create-string-attribute --database-id $DB --collection-id payouts --key status --size 20 --required false --default pending
appwrite databases create-string-attribute --database-id $DB --collection-id payouts --key method --size 20 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id payouts --key reference --size 100 --required false
appwrite databases create-string-attribute --database-id $DB --collection-id payouts --key note --size 500 --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id payouts --key created_at --required false
appwrite databases create-datetime-attribute --database-id $DB --collection-id payouts --key updated_at --required false

Start-Sleep -Seconds 3
appwrite databases create-index --database-id $DB --collection-id payouts --key idx_user_id --type key --attributes user_id
Write-Host "   ✅ payouts (9 attributes, 1 index)" -ForegroundColor Green

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ All 18 collections created successfully!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 Collections:" -ForegroundColor White
Write-Host "   users, addresses, restaurants, menu_categories,"
Write-Host "   menu_items, orders, coupons, notifications,"
Write-Host "   delivery_requests, rider_locations, reviews, payments,"
Write-Host "   delivery_partners, favorites, gold_subscriptions,"
Write-Host "   referrals, scheduled_orders, payouts"
Write-Host ""
Write-Host "🔗 Database ID: $DB" -ForegroundColor White
Write-Host ""
