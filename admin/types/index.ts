// ─── User & Address ─────────────────────────────────────────────────────────
export type UserRole = "customer" | "restaurant_owner" | "delivery_partner" | "admin";

export interface User {
  $id: string;
  name: string;
  email: string;
  phone: string;
  avatar_url: string;
  role: UserRole;
  default_address_id: string;
  is_veg: boolean;
  dark_mode: boolean;
  is_gold_member: boolean;
  referral_code: string;
  referred_by: string;
  fcm_token: string;
  address: string;
  latitude: number;
  longitude: number;
  is_blocked?: boolean;
  created_at: string;
}

export interface Address {
  $id: string;
  user_id: string;
  label: "home" | "work" | "other";
  full_address: string;
  landmark: string;
  latitude: number;
  longitude: number;
  is_default: boolean;
}

// ─── Restaurant & Menu ───────────────────────────────────────────────────────
export interface Restaurant {
  $id: string;
  owner_id: string;
  name: string;
  description: string;
  cover_image_url: string;
  logo_url: string;
  cuisines: string[];
  address: string;
  latitude: number;
  longitude: number;
  city: string;
  rating: number;
  total_ratings: number;
  price_for_two: number;
  avg_delivery_time_min: number;
  is_veg_only: boolean;
  is_online: boolean;
  is_featured: boolean;
  is_promoted: boolean;
  is_approved?: boolean;
  opening_time: string;
  closing_time: string;
  created_at: string;
}

export interface MenuCategory {
  $id: string;
  restaurant_id: string;
  name: string;
  sort_order: number;
  is_active: boolean;
}

export interface MenuItem {
  $id: string;
  restaurant_id: string;
  category_id: string;
  name: string;
  description: string;
  price: number;
  image_url: string;
  is_veg: boolean;
  is_available: boolean;
  is_bestseller: boolean;
  is_must_try: boolean;
  spice_level: "mild" | "medium" | "spicy";
  preparation_time_min: number;
  customizations: string;
  calories: number;
  allergens: string[];
  sort_order: number;
  created_at: string;
  updated_at: string;
}

// ─── Orders ──────────────────────────────────────────────────────────────────
export type OrderStatus =
  | "placed" | "confirmed" | "preparing" | "ready"
  | "pickedUp" | "outForDelivery" | "delivered" | "cancelled";

export type PaymentStatus = "pending" | "paid" | "refunded" | "failed";

export interface OrderItem {
  item_id: string;
  name: string;
  quantity: number;
  price: number;
  is_veg: boolean;
  customizations?: string;
}

export interface Order {
  $id: string;
  order_number: string;
  customer_id: string;
  restaurant_id: string;
  restaurant_name: string;
  delivery_partner_id?: string;
  delivery_partner_name?: string;
  delivery_partner_phone?: string;
  delivery_address_id: string;
  items: string; // JSON string → parse to OrderItem[]
  item_total: number;
  delivery_type: string;
  delivery_fee: number;
  platform_fee: number;
  gst: number;
  discount: number;
  coupon_code?: string;
  tip: number;
  grand_total: number;
  payment_method: string;
  payment_status: PaymentStatus;
  payment_id?: string;
  razorpay_order_id?: string;
  status: OrderStatus;
  special_instructions: string;
  delivery_instructions: string;
  estimated_delivery_min: number;
  placed_at: string;
  confirmed_at?: string;
  prepared_at?: string;
  picked_up_at?: string;
  delivered_at?: string;
  cancelled_at?: string;
  cancellation_reason?: string;
  cancelled_by?: string;
}

// ─── Delivery Partner ────────────────────────────────────────────────────────
export type VehicleType = "bike" | "scooter" | "bicycle" | "car";

export interface DeliveryPartner {
  $id: string;
  user_id: string;
  vehicle_type: VehicleType;
  vehicle_number: string;
  license_number: string;
  is_online: boolean;
  is_on_delivery: boolean;
  current_latitude: number;
  current_longitude: number;
  last_location_update: string;
  rating: number;
  total_ratings: number;
  total_deliveries: number;
  total_earnings: number;
  bank_account_id: string;
  documents_verified: boolean;
  created_at: string;
  updated_at: string;
  // joined fields
  name?: string;
  phone?: string;
}

export interface DeliveryLocation {
  $id: string;
  rider_id: string;
  latitude: number;
  longitude: number;
  heading: number;
  speed: number;
  is_online: boolean;
}

export type PayoutStatus = "pending" | "processing" | "completed" | "failed";
export type PayoutMethod = "bank_transfer" | "upi";

export interface Payout {
  $id: string;
  partner_id: string;
  user_id: string;
  amount: number;
  status: PayoutStatus;
  method: PayoutMethod;
  reference: string;
  note: string;
  created_at: string;
  updated_at: string;
  // joined
  partner_name?: string;
}

// ─── Coupon ───────────────────────────────────────────────────────────────────
export type DiscountType = "percentage" | "flat";
export type CouponAudience = "all" | "new_users" | "gold_members";

export interface Coupon {
  $id: string;
  code: string;
  description: string;
  discount_type: DiscountType;
  discount_value: number;
  max_discount: number;
  min_order_value: number;
  valid_from: string;
  valid_until: string;
  usage_limit: number;
  used_count: number;
  restaurant_id?: string;
  is_active: boolean;
  applicable_to: CouponAudience;
  created_at: string;
}

// ─── Gold ─────────────────────────────────────────────────────────────────────
export type GoldPlanType = "monthly" | "quarterly" | "annual";
export type GoldStatus = "active" | "expired" | "cancelled";

export interface GoldSubscription {
  $id: string;
  user_id: string;
  plan_type: GoldPlanType;
  status: GoldStatus;
  start_date: string;
  end_date: string;
  amount: number;
  payment_id: string;
  created_at: string;
  // joined
  user_name?: string;
  user_phone?: string;
}

// ─── Referral ─────────────────────────────────────────────────────────────────
export type ReferralStatus = "pending" | "completed" | "rewarded";

export interface Referral {
  $id: string;
  referrer_user_id: string;
  referred_user_id: string;
  referral_code: string;
  status: ReferralStatus;
  reward_amount: number;
  created_at: string;
  // joined
  referrer_name?: string;
  referred_name?: string;
}

// ─── Review ───────────────────────────────────────────────────────────────────
export interface Review {
  $id: string;
  order_id: string;
  customer_id: string;
  restaurant_id: string;
  delivery_partner_id?: string;
  food_rating: number;
  delivery_rating: number;
  review_text: string;
  tags: string[];
  photos: string[];
  restaurant_reply?: string;
  is_visible: boolean;
  created_at: string;
  // joined
  customer_name?: string;
  restaurant_name?: string;
}

// ─── Notification ─────────────────────────────────────────────────────────────
export type NotificationType = "order_update" | "promo" | "system" | "review";

export interface Notification {
  $id: string;
  user_id: string;
  type: NotificationType;
  title: string;
  body: string;
  data: string;
  is_read: boolean;
  created_at: string;
}

// ─── Scheduled Order ──────────────────────────────────────────────────────────
export type ScheduledOrderStatus = "scheduled" | "processing" | "completed" | "cancelled";

export interface ScheduledOrder {
  $id: string;
  user_id: string;
  restaurant_id: string;
  items: unknown;
  scheduled_for: string;
  status: ScheduledOrderStatus;
  order_id: string;
  address_id: string;
  coupon_code: string;
  created_at: string;
}

// ─── Admin-specific types ─────────────────────────────────────────────────────

export interface DashboardStats {
  orders_today: number;
  orders_today_delta: number;
  revenue_today: number;
  revenue_today_delta: number;
  active_orders: number;
  new_users_today: number;
  online_restaurants: number;
  online_riders: number;
  orders_per_minute: number;
}

export interface LiveStats {
  active_orders: number;
  online_riders: number;
  connected_users: number;
  orders_per_minute: number;
  connected_by_role: {
    customer: number;
    restaurant_owner: number;
    delivery_partner: number;
  };
}

export interface LiveRider {
  rider_id: string;
  name: string;
  phone: string;
  vehicle_type: VehicleType;
  latitude: number;
  longitude: number;
  heading: number;
  is_on_delivery: boolean;
  current_order_id?: string;
  last_update: string;
}

export interface LiveOrder {
  order_id: string;
  order_number: string;
  customer_name: string;
  restaurant_name: string;
  restaurant_lat: number;
  restaurant_lng: number;
  customer_lat: number;
  customer_lng: number;
  rider_lat?: number;
  rider_lng?: number;
  status: OrderStatus;
  grand_total: number;
  placed_at: string;
}

export interface RevenueDataPoint {
  date: string;
  revenue: number;
  orders: number;
}

export interface OrderStatusCount {
  status: OrderStatus;
  count: number;
}

export interface SLAMetrics {
  avg_accept_time_min: number;
  avg_prep_time_min: number;
  avg_pickup_time_min: number;
  avg_delivery_time_min: number;
  on_time_percent: number;
  breach_count: number;
  breaches: Array<{
    order_id: string;
    order_number: string;
    status: OrderStatus;
    elapsed_min: number;
    expected_min: number;
    restaurant_name: string;
  }>;
}

export interface FinancialReport {
  period: { from: string; to: string };
  gross_revenue: number;
  platform_fees: number;
  delivery_fees: number;
  total_discounts: number;
  gst_collected: number;
  net_revenue: number;
  restaurant_commissions: number;
  rider_payouts_pending: number;
  rider_payouts_processed: number;
  chart_data: Array<{
    date: string;
    gross: number;
    net: number;
    fees: number;
    discounts: number;
  }>;
}

export interface Dispute {
  $id: string;
  order_id: string;
  order_number: string;
  type: "wrong_item" | "late_delivery" | "payment" | "other";
  raised_by: string;
  raised_by_role: UserRole;
  status: "open" | "investigating" | "resolved" | "closed";
  description: string;
  resolution_note?: string;
  assigned_to?: string;
  refund_amount?: number;
  refund_status?: string;
  notes: Array<{ admin: string; text: string; at: string }>;
  created_at: string;
  updated_at: string;
}

export interface Banner {
  $id: string;
  title: string;
  image_url: string;
  deeplink: string;
  target_segment: "all" | "customers" | "gold_members" | "new_users";
  is_active: boolean;
  valid_from: string;
  valid_until: string;
  sort_order: number;
}

export interface Zone {
  $id: string;
  name: string;
  city: string;
  geojson: string; // GeoJSON polygon
  is_active: boolean;
  delivery_fee_override?: number;
  created_at: string;
}

export interface SurgeRule {
  $id: string;
  zone_id: string;
  zone_name: string;
  multiplier: number;
  start_time: string;
  end_time: string;
  is_active: boolean;
  trigger: "manual" | "auto";
  created_at: string;
}

export interface FeatureFlag {
  key: string;
  description: string;
  value: boolean | string | number;
  type: "boolean" | "string" | "number";
  last_changed_by: string;
  last_changed_at: string;
}

export interface AuditLog {
  $id: string;
  admin_id: string;
  admin_name: string;
  action: "create" | "update" | "delete" | "approve" | "reject" | "verify" | "broadcast" | "export";
  resource_type: string;
  resource_id: string;
  summary: string;
  before?: Record<string, unknown>;
  after?: Record<string, unknown>;
  created_at: string;
}

export interface SupportIssue {
  $id: string;
  reporter_id: string;
  reporter_name: string;
  order_id: string;
  order_number: string;
  category: string;
  description: string;
  status: "open" | "investigating" | "resolved";
  assigned_to?: string;
  notes: Array<{ admin: string; text: string; at: string }>;
  created_at: string;
}

export interface AdminAccount {
  $id: string;
  name: string;
  email: string;
  phone: string;
  permission: "super_admin" | "finance" | "operations" | "support" | "read_only";
  is_active: boolean;
  last_login?: string;
  created_at: string;
}

export interface LeaderboardEntry {
  rank: number;
  id: string;
  name: string;
  value: number;
  secondary_value?: number;
  avatar_url?: string;
}

export interface CohortRow {
  week: string;
  signups: number;
  w0: number; // % ordered week 0
  w1: number;
  w2: number;
  w3: number;
  w4: number;
}

export interface CityStats {
  city: string;
  orders: number;
  revenue: number;
  active_restaurants: number;
  active_riders: number;
  avg_delivery_time_min: number;
}

export interface ItemAnalytics {
  item_id: string;
  item_name: string;
  restaurant_id: string;
  restaurant_name: string;
  city: string;
  order_count: number;
  revenue: number;
  last_ordered: string;
}

// ─── Convenience type aliases ────────────────────────────────────────────────
export type Admin = AdminAccount;
export type SurgePricing = SurgeRule;
export type SupportTicket = SupportIssue;

// ─── API response wrapper ─────────────────────────────────────────────────────
export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
  has_more: boolean;
}

export interface ApiError {
  error: string;
  code?: string;
}

// Platform settings
export interface PlatformSettings {
  platform_fee_percent: number;
  gst_rate_percent: number;
  base_delivery_fee: number;
  per_km_delivery_fee: number;
  restaurant_commission_percent: number;
  referral_reward_amount: number;
  gold_plans: {
    monthly_price: number;
    quarterly_price: number;
    annual_price: number;
  };
}
