import axios, { AxiosError } from "axios";

const BASE_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "https://api.devdeepak.me/api/v1";

export const api = axios.create({
  baseURL: BASE_URL,
  timeout: 15_000,
  headers: { "Content-Type": "application/json" },
  withCredentials: true, // send cookies for httpOnly JWT
});

// ─── Request interceptor — attach Bearer token ────────────────────────────────
api.interceptors.request.use((config) => {
  if (typeof window !== "undefined") {
    const token = localStorage.getItem("chizze_admin_token");
    if (token) config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// ─── Response interceptor — handle 401 globally ──────────────────────────────
api.interceptors.response.use(
  (res) => res,
  async (err: AxiosError) => {
    if (err.response?.status === 401) {
      if (typeof window !== "undefined") {
        localStorage.removeItem("chizze_admin_token");
        window.location.href = "/login";
      }
    }
    return Promise.reject(err);
  }
);

// ─── Response unwrapper ───────────────────────────────────────────────────────────────────────────────
// Backend wraps all responses in { success: bool, data: T, meta?: ... }
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function unwrap<T>(body: any): T {
  if (body && typeof body === "object" && "success" in body && "data" in body) {
    return body.data as T;
  }
  return body as T;
}

// ─── Typed convenience methods ────────────────────────────────────────────────────────────────────────
export async function GET<T>(path: string, params?: Record<string, unknown>): Promise<T> {
  const res = await api.get(path, { params });
  return unwrap<T>(res.data);
}

export async function POST<T>(path: string, body?: unknown): Promise<T> {
  const res = await api.post(path, body);
  return unwrap<T>(res.data);
}

export async function PUT<T>(path: string, body?: unknown): Promise<T> {
  const res = await api.put(path, body);
  return unwrap<T>(res.data);
}

export async function DELETE<T>(path: string): Promise<T> {
  const res = await api.delete(path);
  return unwrap<T>(res.data);
}

// ─── Admin-specific API helpers ───────────────────────────────────────────────

// Auth
export const authApi = {
  sendOtp: (phone: string) => POST("/auth/send-otp", { phone }),
  /** Exchange an Appwrite JWT for a Chizze API token */
  exchange: (appwriteJwt: string) =>
    POST<{ token: string; user_id: string; role: string; is_new: boolean }>("/auth/exchange", { jwt: appwriteJwt }),
  /** Fetch current user profile (requires auth token in header) */
  me: () => GET<{ $id: string; name: string; phone: string; role: string }>("/users/me"),
  logout: () => api.delete("/auth/logout"),
};

// Dashboard
export const dashboardApi = {
  stats: () => GET("/admin/dashboard"),
  analytics: (period: "day" | "week" | "month" = "month") =>
    GET("/admin/analytics", { period }),
};

// Users
export const usersApi = {
  list: (p: { page?: number; limit?: number; role?: string; search?: string }) =>
    GET("/admin/users", p),
  get: (id: string) => GET(`/admin/users/${id}`),
  update: (id: string, body: Record<string, unknown>) => PUT(`/admin/users/${id}`, body),
  remove: (id: string) => DELETE(`/admin/users/${id}`),
};

// Restaurants
export const restaurantsApi = {
  list: (p?: Record<string, unknown>) => GET("/admin/restaurants", p),
  pending: () => GET("/admin/restaurants/pending"),
  getPending: () => GET("/admin/restaurants/pending"),
  get: (id: string) => GET(`/admin/restaurants/${id}`),
  getMenu: (id: string) => GET(`/admin/restaurants/${id}/menu`),
  update: (id: string, body: Record<string, unknown>) => PUT(`/admin/restaurants/${id}`, body),
  approve: (id: string, approved?: boolean) =>
    approved !== false
      ? PUT(`/admin/restaurants/${id}/approve`)
      : PUT(`/admin/restaurants/${id}/reject`, {}),
  reject: (id: string, reason: string) => PUT(`/admin/restaurants/${id}/reject`, { reason }),
  remove: (id: string) => DELETE(`/admin/restaurants/${id}`),
};

// Orders
export const ordersApi = {
  list: (p?: Record<string, unknown>) => GET("/admin/orders", p),
  get: (id: string) => GET(`/admin/orders/${id}`),
  getActive: (p?: Record<string, unknown>) => GET("/admin/orders/active", p),
  cancel: (id: string, reason: string) => PUT(`/admin/orders/${id}/cancel`, { reason }),
  reassign: (id: string, rider_id: string) =>
    PUT(`/admin/orders/${id}/reassign`, { rider_id }),
};

// Delivery partners
export const deliveryApi = {
  list: (p?: Record<string, unknown>) => GET("/admin/delivery-partners", p),
  listPartners: (p?: Record<string, unknown>) => GET("/admin/delivery-partners", p),
  pending: () => GET("/admin/delivery-partners/pending"),
  getPendingPartners: () => GET("/admin/delivery-partners/pending"),
  get: (id: string) => GET(`/admin/delivery-partners/${id}`),
  update: (id: string, body: Record<string, unknown>) =>
    PUT(`/admin/delivery-partners/${id}`, body),
  updatePartner: (id: string, body: Record<string, unknown>) =>
    PUT(`/admin/delivery-partners/${id}`, body),
  verify: (id: string, approved: boolean, reason?: string) =>
    PUT(`/admin/delivery-partners/${id}/verify`, { approved, reason }),
  approvePartner: (id: string, approved: boolean) =>
    PUT(`/admin/delivery-partners/${id}/verify`, { approved }),
  payouts: (id: string) => GET(`/admin/delivery-partners/${id}/payouts`),
};

// Payouts
export const payoutsApi = {
  list: (p?: Record<string, unknown>) => GET("/admin/payouts", p),
  update: (id: string, status: string) => PUT(`/admin/payouts/${id}`, { status }),
  approve: (id: string, approved: boolean, reason?: string) =>
    PUT(`/admin/payouts/${id}`, { status: approved ? "processing" : "failed", reason }),
};

// Coupons
export const couponsApi = {
  list: (p?: Record<string, unknown>) => GET("/admin/coupons", p),
  create: (body: Record<string, unknown>) => POST("/admin/coupons", body),
  update: (id: string, body: Record<string, unknown>) => PUT(`/admin/coupons/${id}`, body),
  remove: (id: string) => DELETE(`/admin/coupons/${id}`),
  delete: (id: string) => DELETE(`/admin/coupons/${id}`),
};

// Reviews
export const reviewsApi = {
  list: (p?: Record<string, unknown>) => GET("/admin/reviews", p),
  update: (id: string, body: Record<string, unknown>) => PUT(`/admin/reviews/${id}`, body),
  moderate: (id: string, action: "approve" | "reject") =>
    PUT(`/admin/reviews/${id}`, { is_visible: action === "approve" }),
  remove: (id: string) => DELETE(`/admin/reviews/${id}`),
};

// Gold
export const goldApi = {
  subscriptions: (p?: Record<string, unknown>) =>
    GET("/admin/gold/subscriptions", p),
  list: (p?: Record<string, unknown>) => GET("/admin/gold/subscriptions", p),
  stats: () => GET("/admin/gold/stats"),
  getStats: () => GET("/admin/gold/stats"),
};

// Referrals
export const referralsApi = {
  list: (p?: Record<string, unknown>) => GET("/admin/referrals", p),
  getStats: () => GET("/admin/referrals/stats"),
};

// Notifications
export const notificationsApi = {
  broadcast: (body: Record<string, unknown>) =>
    POST("/admin/notifications/broadcast", body),
  send: (body: Record<string, unknown>) =>
    POST("/admin/notifications/broadcast", body),
  history: () => GET("/admin/notifications/history"),
  list: (p?: Record<string, unknown>) => GET("/admin/notifications/history", p),
};

// Disputes
export const disputesApi = {
  list: (p?: Record<string, unknown>) => GET("/admin/disputes", p),
  get: (id: string) => GET(`/admin/disputes/${id}`),
  update: (id: string, body: Record<string, unknown>) =>
    PUT(`/admin/disputes/${id}`, body),
  resolve: (id: string, body: Record<string, unknown>) =>
    PUT(`/admin/disputes/${id}`, body),
};

// Analytics
export const analyticsApi = {
  sla: () => GET("/admin/analytics/sla"),
  financial: (p: { from: string; to: string }) =>
    GET("/admin/reports/financial", p),
  cancellations: (p?: Record<string, unknown>) =>
    GET("/admin/reports/cancellations", p),
  leaderboards: (p?: Record<string, unknown>) =>
    GET("/admin/leaderboards", p),
  getLeaderboard: (type: string, p?: Record<string, unknown>) =>
    GET("/admin/leaderboards", { type, ...p }),
  items: (p?: Record<string, unknown>) => GET("/admin/analytics/items", p),
  cities: () => GET("/admin/analytics/cities"),
  getCities: () => GET("/admin/analytics/cities"),
  retention: () => GET("/admin/analytics/retention"),
  getRetention: () => GET("/admin/analytics/retention"),
  getRevenue: (p?: Record<string, unknown>) => GET("/admin/analytics/revenue", p),
};

// Content
export const contentApi = {
  banners: () => GET("/admin/content/banners"),
  getBanners: () => GET("/admin/content/banners"),
  createBanner: (body: Record<string, unknown>) =>
    POST("/admin/content/banners", body),
  updateBanner: (id: string, body: Record<string, unknown>) =>
    PUT(`/admin/content/banners/${id}`, body),
  deleteBanner: (id: string) => DELETE(`/admin/content/banners/${id}`),
  getCategories: () => GET("/admin/content/categories"),
};

// Zones
export const zonesApi = {
  list: () => GET("/admin/zones"),
  create: (body: Record<string, unknown>) => POST("/admin/zones", body),
  update: (id: string, body: Record<string, unknown>) =>
    PUT(`/admin/zones/${id}`, body),
  remove: (id: string) => DELETE(`/admin/zones/${id}`),
  delete: (id: string) => DELETE(`/admin/zones/${id}`),
};

// Surge
export const surgeApi = {
  list: () => GET("/admin/surge"),
  create: (body: Record<string, unknown>) => POST("/admin/surge", body),
  update: (id: string, body: Record<string, unknown>) =>
    PUT(`/admin/surge/${id}`, body),
  remove: (id: string) => DELETE(`/admin/surge/${id}`),
  delete: (id: string) => DELETE(`/admin/surge/${id}`),
};

// Feature flags
export const flagsApi = {
  list: () => GET("/admin/feature-flags"),
  update: (key: string, value: unknown) =>
    PUT(`/admin/feature-flags/${key}`, { value }),
};

// Audit log
export const auditApi = {
  list: (p?: Record<string, unknown>) => GET("/admin/audit-log", p),
};

// Support
export const supportApi = {
  list: (p?: Record<string, unknown>) => GET("/admin/support/issues", p),
  get: (id: string) => GET(`/admin/support/issues/${id}`),
  update: (id: string, body: Record<string, unknown>) =>
    PUT(`/admin/support/issues/${id}`, body),
  getMessages: (id: string) => GET(`/admin/support/issues/${id}/messages`),
  reply: (id: string, message: string) =>
    POST(`/admin/support/issues/${id}/reply`, { message }),
  close: (id: string) => PUT(`/admin/support/issues/${id}`, { status: "resolved" }),
};

// Admin accounts
export const adminsApi = {
  list: () => GET("/admin/admins"),
  create: (body: Record<string, unknown>) => POST("/admin/admins", body),
  update: (id: string, body: Record<string, unknown>) =>
    PUT(`/admin/admins/${id}`, body),
  remove: (id: string) => DELETE(`/admin/admins/${id}`),
  delete: (id: string) => DELETE(`/admin/admins/${id}`),
};

// Settings
export const settingsApi = {
  get: () => GET("/admin/settings"),
  update: (body: Record<string, unknown>) => PUT("/admin/settings", body),
};

// Live
export const liveApi = {
  sessions: () => GET("/admin/live/sessions"),
  ridersSnapshot: () => GET("/admin/live/riders"),
  ordersSnapshot: () => GET("/admin/live/orders"),
};
