@echo off
echo ======================================
echo  CHIZZE - Adding Attributes + Indexes
echo ======================================

REM ─── USERS ───
echo.
echo [USERS] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id users --key phone --size 20 --required true
appwrite databases create-email-attribute --database-id chizze_db --collection-id users --key email --required false
appwrite databases create-url-attribute --database-id chizze_db --collection-id users --key avatar_url --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id users --key role --size 20 --required false --default customer
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id users --key is_veg --required false --default false
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id users --key dark_mode --required false --default true
appwrite databases create-string-attribute --database-id chizze_db --collection-id users --key default_address_id --size 36 --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id users --key fcm_token --size 256 --required false
echo [USERS] Waiting for attributes to process...
timeout /t 5 /nobreak >nul
echo [USERS] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id users --key idx_phone --type unique --attributes phone
appwrite databases create-index --database-id chizze_db --collection-id users --key idx_role --type key --attributes role
echo [USERS] Done!

REM ─── ADDRESSES ───
echo.
echo [ADDRESSES] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id addresses --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id addresses --key label --size 50 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id addresses --key full_address --size 500 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id addresses --key landmark --size 200 --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id addresses --key latitude --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id addresses --key longitude --required false
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id addresses --key is_default --required false --default false
timeout /t 5 /nobreak >nul
echo [ADDRESSES] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id addresses --key idx_user --type key --attributes user_id
echo [ADDRESSES] Done!

REM ─── RESTAURANTS ───
echo.
echo [RESTAURANTS] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id restaurants --key owner_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id restaurants --key name --size 128 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id restaurants --key description --size 500 --required false
appwrite databases create-url-attribute --database-id chizze_db --collection-id restaurants --key cover_image_url --required false
appwrite databases create-url-attribute --database-id chizze_db --collection-id restaurants --key logo_url --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id restaurants --key address --size 500 --required true
appwrite databases create-float-attribute --database-id chizze_db --collection-id restaurants --key latitude --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id restaurants --key longitude --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id restaurants --key city --size 100 --required true
appwrite databases create-float-attribute --database-id chizze_db --collection-id restaurants --key rating --required false
appwrite databases create-integer-attribute --database-id chizze_db --collection-id restaurants --key total_ratings --required false
appwrite databases create-integer-attribute --database-id chizze_db --collection-id restaurants --key price_for_two --required false
appwrite databases create-integer-attribute --database-id chizze_db --collection-id restaurants --key avg_delivery_time_min --required false
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id restaurants --key is_veg_only --required false --default false
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id restaurants --key is_online --required false --default true
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id restaurants --key is_featured --required false --default false
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id restaurants --key is_promoted --required false --default false
appwrite databases create-string-attribute --database-id chizze_db --collection-id restaurants --key opening_time --size 10 --required false --default 09:00
appwrite databases create-string-attribute --database-id chizze_db --collection-id restaurants --key closing_time --size 10 --required false --default 23:00
timeout /t 8 /nobreak >nul
echo [RESTAURANTS] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id restaurants --key idx_owner --type key --attributes owner_id
appwrite databases create-index --database-id chizze_db --collection-id restaurants --key idx_city --type key --attributes city
appwrite databases create-index --database-id chizze_db --collection-id restaurants --key idx_online --type key --attributes is_online
appwrite databases create-index --database-id chizze_db --collection-id restaurants --key idx_featured --type key --attributes is_featured
appwrite databases create-index --database-id chizze_db --collection-id restaurants --key idx_rating --type key --attributes rating --orders DESC
appwrite databases create-index --database-id chizze_db --collection-id restaurants --key idx_name --type fulltext --attributes name
echo [RESTAURANTS] Done!

REM ─── MENU_CATEGORIES ───
echo.
echo [MENU_CATEGORIES] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id menu_categories --key restaurant_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id menu_categories --key name --size 100 --required true
appwrite databases create-integer-attribute --database-id chizze_db --collection-id menu_categories --key sort_order --required false
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id menu_categories --key is_active --required false --default true
timeout /t 5 /nobreak >nul
echo [MENU_CATEGORIES] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id menu_categories --key idx_restaurant --type key --attributes restaurant_id
echo [MENU_CATEGORIES] Done!

REM ─── MENU_ITEMS ───
echo.
echo [MENU_ITEMS] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id menu_items --key restaurant_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id menu_items --key category_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id menu_items --key name --size 200 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id menu_items --key description --size 1000 --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id menu_items --key price --required true
appwrite databases create-url-attribute --database-id chizze_db --collection-id menu_items --key image_url --required false
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id menu_items --key is_veg --required true
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id menu_items --key is_available --required false --default true
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id menu_items --key is_bestseller --required false --default false
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id menu_items --key is_must_try --required false --default false
appwrite databases create-enum-attribute --database-id chizze_db --collection-id menu_items --key spice_level --elements mild medium spicy extra_spicy --required false --default mild
appwrite databases create-integer-attribute --database-id chizze_db --collection-id menu_items --key preparation_time_min --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id menu_items --key customizations --size 5000 --required false
appwrite databases create-integer-attribute --database-id chizze_db --collection-id menu_items --key calories --required false
appwrite databases create-integer-attribute --database-id chizze_db --collection-id menu_items --key sort_order --required false
timeout /t 8 /nobreak >nul
echo [MENU_ITEMS] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id menu_items --key idx_restaurant --type key --attributes restaurant_id
appwrite databases create-index --database-id chizze_db --collection-id menu_items --key idx_category --type key --attributes category_id
appwrite databases create-index --database-id chizze_db --collection-id menu_items --key idx_veg --type key --attributes is_veg
appwrite databases create-index --database-id chizze_db --collection-id menu_items --key idx_name --type fulltext --attributes name
echo [MENU_ITEMS] Done!

REM ─── ORDERS ───
echo.
echo [ORDERS] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key order_number --size 30 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key customer_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key restaurant_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key restaurant_name --size 128 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key delivery_partner_id --size 36 --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key delivery_partner_name --size 128 --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key delivery_partner_phone --size 20 --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key delivery_address_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key items --size 10000 --required true
appwrite databases create-float-attribute --database-id chizze_db --collection-id orders --key item_total --required true
appwrite databases create-float-attribute --database-id chizze_db --collection-id orders --key delivery_fee --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id orders --key platform_fee --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id orders --key gst --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id orders --key discount --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key coupon_code --size 30 --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id orders --key tip --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id orders --key grand_total --required true
appwrite databases create-enum-attribute --database-id chizze_db --collection-id orders --key payment_method --elements upi card cod wallet netbanking --required true
appwrite databases create-enum-attribute --database-id chizze_db --collection-id orders --key payment_status --elements pending paid failed refunded --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key payment_id --size 100 --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key razorpay_order_id --size 100 --required false
appwrite databases create-enum-attribute --database-id chizze_db --collection-id orders --key status --elements placed confirmed preparing ready pickedUp outForDelivery delivered cancelled --required true --default placed
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key special_instructions --size 500 --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key delivery_instructions --size 500 --required false
appwrite databases create-integer-attribute --database-id chizze_db --collection-id orders --key estimated_delivery_min --required false
appwrite databases create-datetime-attribute --database-id chizze_db --collection-id orders --key placed_at --required true
appwrite databases create-datetime-attribute --database-id chizze_db --collection-id orders --key confirmed_at --required false
appwrite databases create-datetime-attribute --database-id chizze_db --collection-id orders --key prepared_at --required false
appwrite databases create-datetime-attribute --database-id chizze_db --collection-id orders --key picked_up_at --required false
appwrite databases create-datetime-attribute --database-id chizze_db --collection-id orders --key delivered_at --required false
appwrite databases create-datetime-attribute --database-id chizze_db --collection-id orders --key cancelled_at --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key cancellation_reason --size 500 --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id orders --key cancelled_by --size 36 --required false
timeout /t 10 /nobreak >nul
echo [ORDERS] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id orders --key idx_customer --type key --attributes customer_id
appwrite databases create-index --database-id chizze_db --collection-id orders --key idx_restaurant --type key --attributes restaurant_id
appwrite databases create-index --database-id chizze_db --collection-id orders --key idx_status --type key --attributes status
appwrite databases create-index --database-id chizze_db --collection-id orders --key idx_rider --type key --attributes delivery_partner_id
appwrite databases create-index --database-id chizze_db --collection-id orders --key idx_order_num --type unique --attributes order_number
appwrite databases create-index --database-id chizze_db --collection-id orders --key idx_placed --type key --attributes placed_at --orders DESC
echo [ORDERS] Done!

REM ─── COUPONS ───
echo.
echo [COUPONS] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id coupons --key code --size 30 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id coupons --key title --size 128 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id coupons --key description --size 500 --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id coupons --key discount_percent --required true
appwrite databases create-float-attribute --database-id chizze_db --collection-id coupons --key max_discount --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id coupons --key min_order --required false
appwrite databases create-datetime-attribute --database-id chizze_db --collection-id coupons --key expires_at --required true
appwrite databases create-integer-attribute --database-id chizze_db --collection-id coupons --key usage_limit --required false
appwrite databases create-integer-attribute --database-id chizze_db --collection-id coupons --key usage_count --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id coupons --key restaurant_id --size 36 --required false
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id coupons --key is_active --required false --default true
timeout /t 5 /nobreak >nul
echo [COUPONS] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id coupons --key idx_code --type unique --attributes code
appwrite databases create-index --database-id chizze_db --collection-id coupons --key idx_active --type key --attributes is_active
echo [COUPONS] Done!

REM ─── NOTIFICATIONS ───
echo.
echo [NOTIFICATIONS] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id notifications --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id notifications --key title --size 200 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id notifications --key body --size 1000 --required true
appwrite databases create-enum-attribute --database-id chizze_db --collection-id notifications --key type --elements order promo system --required true
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id notifications --key is_read --required false --default false
appwrite databases create-string-attribute --database-id chizze_db --collection-id notifications --key data --size 2000 --required false
timeout /t 5 /nobreak >nul
echo [NOTIFICATIONS] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id notifications --key idx_user --type key --attributes user_id
appwrite databases create-index --database-id chizze_db --collection-id notifications --key idx_read --type key --attributes is_read
echo [NOTIFICATIONS] Done!

REM ─── DELIVERY_REQUESTS ───
echo.
echo [DELIVERY_REQUESTS] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id delivery_requests --key order_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id delivery_requests --key rider_id --size 36 --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id delivery_requests --key restaurant_name --size 128 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id delivery_requests --key restaurant_address --size 500 --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id delivery_requests --key restaurant_latitude --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id delivery_requests --key restaurant_longitude --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id delivery_requests --key customer_address --size 500 --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id delivery_requests --key customer_latitude --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id delivery_requests --key customer_longitude --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id delivery_requests --key distance_km --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id delivery_requests --key estimated_earning --required false
appwrite databases create-enum-attribute --database-id chizze_db --collection-id delivery_requests --key status --elements pending accepted rejected expired --required false --default pending
appwrite databases create-datetime-attribute --database-id chizze_db --collection-id delivery_requests --key expires_at --required true
timeout /t 5 /nobreak >nul
echo [DELIVERY_REQUESTS] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id delivery_requests --key idx_rider --type key --attributes rider_id
appwrite databases create-index --database-id chizze_db --collection-id delivery_requests --key idx_order --type key --attributes order_id
appwrite databases create-index --database-id chizze_db --collection-id delivery_requests --key idx_status --type key --attributes status
echo [DELIVERY_REQUESTS] Done!

REM ─── RIDER_LOCATIONS ───
echo.
echo [RIDER_LOCATIONS] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id rider_locations --key rider_id --size 36 --required true
appwrite databases create-float-attribute --database-id chizze_db --collection-id rider_locations --key latitude --required true
appwrite databases create-float-attribute --database-id chizze_db --collection-id rider_locations --key longitude --required true
appwrite databases create-float-attribute --database-id chizze_db --collection-id rider_locations --key heading --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id rider_locations --key speed --required false
appwrite databases create-boolean-attribute --database-id chizze_db --collection-id rider_locations --key is_online --required false --default false
timeout /t 5 /nobreak >nul
echo [RIDER_LOCATIONS] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id rider_locations --key idx_rider --type unique --attributes rider_id
appwrite databases create-index --database-id chizze_db --collection-id rider_locations --key idx_online --type key --attributes is_online
echo [RIDER_LOCATIONS] Done!

REM ─── REVIEWS ───
echo.
echo [REVIEWS] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id reviews --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id reviews --key order_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id reviews --key restaurant_id --size 36 --required true
appwrite databases create-float-attribute --database-id chizze_db --collection-id reviews --key rating --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id reviews --key comment --size 2000 --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id reviews --key reply --size 1000 --required false
timeout /t 5 /nobreak >nul
echo [REVIEWS] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id reviews --key idx_restaurant --type key --attributes restaurant_id
appwrite databases create-index --database-id chizze_db --collection-id reviews --key idx_user --type key --attributes user_id
appwrite databases create-index --database-id chizze_db --collection-id reviews --key idx_order --type unique --attributes order_id
echo [REVIEWS] Done!

REM ─── PAYMENTS ───
echo.
echo [PAYMENTS] Adding attributes...
appwrite databases create-string-attribute --database-id chizze_db --collection-id payments --key order_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id payments --key user_id --size 36 --required true
appwrite databases create-string-attribute --database-id chizze_db --collection-id payments --key razorpay_order_id --size 100 --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id payments --key razorpay_payment_id --size 100 --required false
appwrite databases create-string-attribute --database-id chizze_db --collection-id payments --key razorpay_signature --size 256 --required false
appwrite databases create-float-attribute --database-id chizze_db --collection-id payments --key amount --required true
appwrite databases create-enum-attribute --database-id chizze_db --collection-id payments --key status --elements pending success failed refunded --required true --default pending
appwrite databases create-enum-attribute --database-id chizze_db --collection-id payments --key method --elements upi card cod wallet netbanking --required true
timeout /t 5 /nobreak >nul
echo [PAYMENTS] Adding indexes...
appwrite databases create-index --database-id chizze_db --collection-id payments --key idx_order --type key --attributes order_id
appwrite databases create-index --database-id chizze_db --collection-id payments --key idx_user --type key --attributes user_id
appwrite databases create-index --database-id chizze_db --collection-id payments --key idx_status --type key --attributes status
echo [PAYMENTS] Done!

echo.
echo ======================================
echo  ALL DONE! 12 collections configured.
echo ======================================
