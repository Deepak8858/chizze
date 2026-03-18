"use client";
import { usePathname, useRouter } from "next/navigation";
import { LogOut, ChevronRight } from "lucide-react";
import { useLiveStats } from "@/lib/sse";
import { clearAuth, getUser } from "@/lib/auth";
import { authApi } from "@/lib/api";
import { account } from "@/lib/appwrite";
import { cn } from "@/lib/utils";

function LiveCounter({
  value,
  label,
  color = "text-success",
}: {
  value: number;
  label: string;
  color?: string;
}) {
  return (
    <div className="flex items-center gap-1.5 text-xs">
      <span className={cn("live-dot", color === "text-success" ? "" : color === "text-brand-400" ? "!bg-brand-400" : "!bg-info")} />
      <span className={cn("font-bold tabular-nums", color)}>{value}</span>
      <span className="text-text-muted">{label}</span>
    </div>
  );
}

function Breadcrumbs() {
  const pathname = usePathname();
  const segments = pathname.split("/").filter(Boolean);

  const labelMap: Record<string, string> = {
    "live-map": "Live Map",
    "live-users": "Live Users",
    "live-orders": "Live Orders",
    users: "Users",
    restaurants: "Restaurants",
    orders: "Orders",
    "delivery-partners": "Delivery Partners",
    payouts: "Payouts",
    approvals: "Approvals",
    disputes: "Disputes",
    coupons: "Coupons",
    gold: "Gold",
    referrals: "Referrals",
    notifications: "Notifications",
    content: "Content",
    sla: "SLA Monitor",
    reports: "Reports",
    leaderboards: "Leaderboards",
    analytics: "Analytics",
    items: "Items",
    cities: "Cities",
    retention: "Retention",
    reviews: "Reviews",
    zones: "Zones",
    surge: "Surge Pricing",
    flags: "Feature Flags",
    "audit-log": "Audit Log",
    "admin-accounts": "Admin Accounts",
    support: "Support",
    settings: "Settings",
    admins: "Admins",
  };

  // Resolve dynamic segments like /orders/[id] to "Order Detail"
  const resolveLabel = (seg: string, i: number): string => {
    if (labelMap[seg]) return labelMap[seg];
    // If previous segment is a known parent, this is a detail page
    const parent = segments[i - 1];
    if (parent === "orders") return `#${seg.slice(-8).toUpperCase()}`;
    if (parent === "users" || parent === "restaurants" || parent === "delivery-partners" || parent === "disputes" || parent === "support") return "Detail";
    return seg;
  };

  return (
    <div className="flex items-center gap-1 text-sm text-text-muted">
      <span className="text-text-secondary">Chizze</span>
      {segments.map((seg, i) => (
        <span key={i} className="flex items-center gap-1">
          <ChevronRight size={12} />
          <span className={i === segments.length - 1 ? "text-white font-medium" : ""}>
            {resolveLabel(seg, i)}
          </span>
        </span>
      ))}
      {segments.length === 0 && (
        <span className="flex items-center gap-1">
          <ChevronRight size={12} />
          <span className="text-white font-medium">Overview</span>
        </span>
      )}
    </div>
  );
}

export function Header() {
  const router = useRouter();
  const user = getUser();
  const { stats, connected } = useLiveStats();

  const handleLogout = async () => {
    try { await authApi.logout(); } catch { /* ignore */ }
    try { await account.deleteSession("current"); } catch { /* ignore */ }
    clearAuth();
    router.replace("/login");
  };

  return (
    <header className="h-[60px] flex items-center justify-between px-6 bg-bg-card border-b border-white/[0.06] flex-shrink-0">
      {/* Breadcrumbs */}
      <Breadcrumbs />

      {/* Live Stats Bar */}
      <div className="flex items-center gap-5 absolute left-1/2 -translate-x-1/2">
        <LiveCounter value={stats.active_orders} label="Orders Active" color="text-brand-400" />
        <div className="w-px h-4 bg-white/10" />
        <LiveCounter value={stats.online_riders} label="Riders Online" color="text-success" />
        <div className="w-px h-4 bg-white/10" />
        <LiveCounter value={stats.connected_users} label="Users Live" color="text-info" />
        {!connected && (
          <span className="text-[10px] text-error bg-error/10 px-1.5 py-0.5 rounded">Reconnecting…</span>
        )}
      </div>

      {/* Right — user */}
      <div className="flex items-center gap-3">
        {/* Admin avatar + name */}
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-full bg-brand-500/20 flex items-center justify-center text-brand-400 font-bold text-sm">
            {user?.name?.charAt(0)?.toUpperCase() ?? "A"}
          </div>
          <div className="hidden sm:block">
            <p className="text-xs font-medium text-white">{user?.name ?? "Admin"}</p>
            <p className="text-[10px] text-text-muted capitalize">{user?.permission ?? "super_admin"}</p>
          </div>
        </div>

        {/* Logout */}
        <button
          onClick={handleLogout}
          className="p-2 rounded-lg text-text-muted hover:bg-error/10 hover:text-error transition-colors"
          title="Logout"
        >
          <LogOut size={16} />
        </button>
      </div>
    </header>
  );
}
