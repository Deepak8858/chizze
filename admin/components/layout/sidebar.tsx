"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { cn } from "@/lib/utils";
import {
  LayoutDashboard, Map, Users, UtensilsCrossed, Package, Bike,
  DollarSign, CheckSquare, AlertTriangle, Ticket, Star, Link2,
  Bell, Image, BarChart2, TrendingUp, MessageSquare, Layers, Zap, Flag, ClipboardList,
  HeadphonesIcon, Settings, Shield, ChevronLeft, ChevronRight,
  Radio, MonitorPlay, KanbanSquare
} from "lucide-react";

interface NavItem {
  label: string;
  href: string;
  icon: React.ReactNode;
  badge?: number;
}

interface NavGroup {
  title: string;
  items: NavItem[];
}

const NAV_GROUPS: NavGroup[] = [
  {
    title: "Real-time",
    items: [
      { label: "Live Map", href: "/live-map", icon: <Map size={16} /> },
      { label: "Live Users", href: "/live-users", icon: <Radio size={16} /> },
      { label: "Live Orders", href: "/live-orders", icon: <KanbanSquare size={16} /> },
    ],
  },
  {
    title: "Dashboard",
    items: [
      { label: "Overview", href: "/dashboard", icon: <LayoutDashboard size={16} /> },
    ],
  },
  {
    title: "Management",
    items: [
      { label: "Users", href: "/users", icon: <Users size={16} /> },
      { label: "Restaurants", href: "/restaurants", icon: <UtensilsCrossed size={16} /> },
      { label: "Orders", href: "/orders", icon: <Package size={16} /> },
      { label: "Delivery Partners", href: "/delivery-partners", icon: <Bike size={16} /> },
      { label: "Payouts", href: "/payouts", icon: <DollarSign size={16} /> },
      { label: "Restaurant Queue", href: "/approvals/restaurants", icon: <CheckSquare size={16} /> },
      { label: "Rider Queue", href: "/approvals/delivery-partners", icon: <CheckSquare size={16} /> },
      { label: "Disputes", href: "/disputes", icon: <AlertTriangle size={16} /> },
    ],
  },
  {
    title: "Marketing",
    items: [
      { label: "Coupons", href: "/coupons", icon: <Ticket size={16} /> },
      { label: "Gold", href: "/gold", icon: <Star size={16} /> },
      { label: "Referrals", href: "/referrals", icon: <Link2 size={16} /> },
      { label: "Notifications", href: "/notifications", icon: <Bell size={16} /> },
      { label: "Content", href: "/content", icon: <Image size={16} /> },
    ],
  },
  {
    title: "Analytics",
    items: [
      { label: "SLA Monitor", href: "/sla", icon: <MonitorPlay size={16} /> },
      { label: "Reports", href: "/reports", icon: <TrendingUp size={16} /> },
      { label: "Analytics", href: "/analytics", icon: <BarChart2 size={16} /> },
      { label: "Reviews", href: "/reviews", icon: <MessageSquare size={16} /> },
    ],
  },
  {
    title: "Platform",
    items: [
      { label: "Zones", href: "/zones", icon: <Layers size={16} /> },
      { label: "Surge Pricing", href: "/surge", icon: <Zap size={16} /> },
      { label: "Feature Flags", href: "/flags", icon: <Flag size={16} /> },
      { label: "Audit Log", href: "/audit-log", icon: <ClipboardList size={16} /> },
      { label: "Support", href: "/support", icon: <HeadphonesIcon size={16} /> },
    ],
  },
  {
    title: "Settings",
    items: [
      { label: "Settings", href: "/settings", icon: <Settings size={16} /> },
      { label: "Admin Accounts", href: "/admin-accounts", icon: <Shield size={16} /> },
    ],
  },
];

export function Sidebar() {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);

  const isActive = (href: string) => {
    if (href === "/") return pathname === "/";
    return pathname.startsWith(href);
  };

  return (
    <aside
      className={cn(
        "flex flex-col h-screen bg-bg-card border-r border-white/[0.06] transition-all duration-200 flex-shrink-0",
        collapsed ? "w-[72px]" : "w-[240px]"
      )}
    >
      {/* Logo */}
      <div className="flex items-center gap-2 h-[60px] px-4 border-b border-white/[0.06] flex-shrink-0">
        {!collapsed && (
          <>
            <span className="text-brand-500 font-extrabold text-xl tracking-tight">chizze</span>
            <span className="text-[10px] font-semibold bg-brand-500/20 text-brand-400 px-1.5 py-0.5 rounded uppercase tracking-widest">
              admin
            </span>
          </>
        )}
        {collapsed && (
          <span className="text-brand-500 font-extrabold text-lg mx-auto">C</span>
        )}
      </div>

      {/* Nav */}
      <nav className="flex-1 overflow-y-auto py-3 px-2">
        {NAV_GROUPS.map((group) => (
          <div key={group.title} className="mb-4">
            {!collapsed && (
              <p className="px-2 mb-1 text-[10px] font-semibold text-text-muted uppercase tracking-widest">
                {group.title}
              </p>
            )}
            {group.items.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                title={collapsed ? item.label : undefined}
                className={cn(
                  "flex items-center gap-2.5 px-2 py-2 rounded-lg text-sm transition-colors duration-100 mb-0.5 relative group",
                  isActive(item.href)
                    ? "bg-brand-500/10 text-brand-400 font-medium"
                    : "text-text-secondary hover:bg-bg-hover hover:text-white"
                )}
              >
                {/* Active left bar */}
                {isActive(item.href) && (
                  <span className="absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-5 bg-brand-500 rounded-r" />
                )}
                <span className={cn(isActive(item.href) ? "text-brand-400" : "text-text-muted group-hover:text-white")}>
                  {item.icon}
                </span>
                {!collapsed && <span>{item.label}</span>}
                {!collapsed && item.badge != null && item.badge > 0 && (
                  <span className="ml-auto text-[10px] bg-error/20 text-error font-semibold px-1.5 py-0.5 rounded-full">
                    {item.badge}
                  </span>
                )}
                {/* Tooltip when collapsed */}
                {collapsed && (
                  <span className="absolute left-full ml-2 px-2 py-1 bg-bg-elevated border border-white/10 text-white text-xs rounded whitespace-nowrap opacity-0 group-hover:opacity-100 pointer-events-none z-50 transition-opacity">
                    {item.label}
                  </span>
                )}
              </Link>
            ))}
          </div>
        ))}
      </nav>

      {/* Collapse toggle */}
      <div className="border-t border-white/[0.06] p-2">
        <button
          onClick={() => setCollapsed(!collapsed)}
          className="flex items-center justify-center w-full h-9 rounded-lg text-text-muted hover:bg-bg-hover hover:text-white transition-colors"
          title={collapsed ? "Expand sidebar" : "Collapse sidebar"}
        >
          {collapsed ? <ChevronRight size={16} /> : <ChevronLeft size={16} />}
          {!collapsed && <span className="ml-2 text-xs">Collapse</span>}
        </button>
      </div>
    </aside>
  );
}
