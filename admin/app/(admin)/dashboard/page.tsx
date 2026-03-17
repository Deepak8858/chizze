"use client";
import { useQuery } from "@tanstack/react-query";
import {
  AreaChart, Area, BarChart, Bar, PieChart, Pie, Cell,
  XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid
} from "recharts";
import {
  ShoppingBag, DollarSign, Users, UtensilsCrossed, Bike, Activity
} from "lucide-react";
import { dashboardApi } from "@/lib/api";
import { KPICard } from "@/components/dashboard/kpi-card";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatCurrency, formatDateTime, timeAgo } from "@/lib/utils";
import type { DashboardStats, RevenueDataPoint, OrderStatusCount, Order } from "@/types";

const STATUS_COLORS: Record<string, string> = {
  placed: "#3B82F6", confirmed: "#F49D25", preparing: "#F49D25",
  ready: "#22C55E", pickedUp: "#22C55E", outForDelivery: "#22C55E",
  delivered: "#22C55E", cancelled: "#EF4444",
};

const CHART_TOOLTIP_STYLE = {
  contentStyle: { background: "#252525", border: "1px solid rgba(255,255,255,0.12)", borderRadius: 8 },
  labelStyle: { color: "#A0A0A0", fontSize: 12 },
  itemStyle: { color: "#FFFFFF", fontSize: 12 },
};

interface DashboardData {
  stats: DashboardStats;
  revenue_chart: RevenueDataPoint[];
  status_chart: OrderStatusCount[];
  recent_orders: Order[];
}

export default function DashboardPage() {
  const { data, isLoading } = useQuery<DashboardData>({
    queryKey: ["admin-dashboard"],
    queryFn: () => dashboardApi.stats() as Promise<DashboardData>,
    refetchInterval: 30_000,
  });

  const { data: analyticsData } = useQuery({
    queryKey: ["admin-analytics", "month"],
    queryFn: () => dashboardApi.analytics("month"),
    refetchInterval: 60_000,
  });

  const stats = data?.stats;
  const revenueData = (analyticsData as { revenue_chart?: RevenueDataPoint[] })?.revenue_chart ?? [];
  const statusData = data?.status_chart ?? [];
  const recentOrders = data?.recent_orders ?? [];

  return (
    <div className="space-y-6">
      {/* Page title */}
      <div>
        <h1 className="text-2xl font-bold text-white">Overview</h1>
        <p className="text-sm text-text-muted mt-0.5">Platform-wide metrics and activity</p>
      </div>

      {/* KPI Grid */}
      <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-4">
        <KPICard label="Orders Today" value={stats?.orders_today ?? 0} delta={stats?.orders_today_delta} icon={ShoppingBag} format="number" loading={isLoading} />
        <KPICard label="Revenue Today" value={stats?.revenue_today ?? 0} delta={stats?.revenue_today_delta} icon={DollarSign} iconColor="text-success" format="currency" loading={isLoading} />
        <KPICard label="Active Orders" value={stats?.active_orders ?? 0} icon={Activity} iconColor="text-brand-400" loading={isLoading} />
        <KPICard label="New Users Today" value={stats?.new_users_today ?? 0} icon={Users} iconColor="text-info" loading={isLoading} />
        <KPICard label="Online Restaurants" value={stats?.online_restaurants ?? 0} icon={UtensilsCrossed} iconColor="text-warning" loading={isLoading} />
        <KPICard label="Online Riders" value={stats?.online_riders ?? 0} icon={Bike} iconColor="text-success" loading={isLoading} />
      </div>

      {/* Charts Row */}
      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        {/* Revenue Chart — 2/3 width */}
        <div className="xl:col-span-2 card">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-white">Revenue — Last 30 Days</h2>
            <span className="text-xs text-text-muted">INR</span>
          </div>
          {isLoading ? (
            <div className="skeleton h-48 w-full" />
          ) : (
            <ResponsiveContainer width="100%" height={200}>
              <AreaChart data={revenueData}>
                <defs>
                  <linearGradient id="revenueGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#F49D25" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#F49D25" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
                <XAxis dataKey="date" tick={{ fill: "#666", fontSize: 11 }} tickLine={false} axisLine={false} />
                <YAxis tick={{ fill: "#666", fontSize: 11 }} tickLine={false} axisLine={false} tickFormatter={(v) => `₹${(v / 1000).toFixed(0)}K`} />
                <Tooltip {...CHART_TOOLTIP_STYLE} formatter={(v: number) => [formatCurrency(v), "Revenue"]} />
                <Area type="monotone" dataKey="revenue" stroke="#F49D25" strokeWidth={2} fill="url(#revenueGrad)" />
              </AreaChart>
            </ResponsiveContainer>
          )}
        </div>

        {/* Order Status Pie — 1/3 width */}
        <div className="card">
          <h2 className="text-sm font-semibold text-white mb-4">Order Status</h2>
          {isLoading ? (
            <div className="skeleton h-48 w-full" />
          ) : (
            <>
              <ResponsiveContainer width="100%" height={160}>
                <PieChart>
                  <Pie
                    data={statusData}
                    dataKey="count"
                    nameKey="status"
                    cx="50%"
                    cy="50%"
                    innerRadius={40}
                    outerRadius={70}
                    strokeWidth={0}
                  >
                    {statusData.map((entry, i) => (
                      <Cell key={i} fill={STATUS_COLORS[entry.status] ?? "#666"} />
                    ))}
                  </Pie>
                  <Tooltip {...CHART_TOOLTIP_STYLE} />
                </PieChart>
              </ResponsiveContainer>
              <div className="space-y-1 mt-2">
                {statusData.slice(0, 4).map((s) => (
                  <div key={s.status} className="flex items-center justify-between text-xs">
                    <div className="flex items-center gap-1.5">
                      <span className="w-2 h-2 rounded-full" style={{ background: STATUS_COLORS[s.status] ?? "#666" }} />
                      <span className="text-text-secondary capitalize">{s.status}</span>
                    </div>
                    <span className="text-white font-medium tabular-nums">{s.count}</span>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
      </div>

      {/* Orders per day bar chart */}
      {revenueData.length > 0 && (
        <div className="card">
          <h2 className="text-sm font-semibold text-white mb-4">Orders per Day</h2>
          <ResponsiveContainer width="100%" height={140}>
            <BarChart data={revenueData} barSize={8}>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
              <XAxis dataKey="date" tick={{ fill: "#666", fontSize: 11 }} tickLine={false} axisLine={false} />
              <YAxis tick={{ fill: "#666", fontSize: 11 }} tickLine={false} axisLine={false} />
              <Tooltip {...CHART_TOOLTIP_STYLE} />
              <Bar dataKey="orders" fill="#F49D25" radius={[3, 3, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Recent orders */}
      <div className="card !p-0 overflow-hidden">
        <div className="px-5 py-4 border-b border-white/[0.06]">
          <h2 className="text-sm font-semibold text-white">Recent Orders</h2>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b border-white/[0.06] bg-bg-elevated">
                {["Order #", "Customer", "Restaurant", "Total", "Status", "Time"].map((h) => (
                  <th key={h} className="px-4 py-3 text-left text-[11px] font-semibold text-text-secondary uppercase tracking-wider">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {isLoading
                ? Array.from({ length: 5 }).map((_, i) => (
                    <tr key={i} className="border-b border-white/[0.04]">
                      {Array.from({ length: 6 }).map((_, j) => (
                        <td key={j} className="px-4 py-3"><div className="skeleton h-4 w-full" /></td>
                      ))}
                    </tr>
                  ))
                : recentOrders.map((order) => (
                    <tr key={order.$id} className="border-b border-white/[0.04] hover:bg-bg-hover transition-colors">
                      <td className="px-4 py-3 text-sm font-mono text-brand-400">#{order.order_number}</td>
                      <td className="px-4 py-3 text-sm text-white">{order.customer_id.slice(0, 8)}…</td>
                      <td className="px-4 py-3 text-sm text-text-secondary">{order.restaurant_name}</td>
                      <td className="px-4 py-3 text-sm font-medium text-white">{formatCurrency(order.grand_total)}</td>
                      <td className="px-4 py-3"><StatusBadge status={order.status} /></td>
                      <td className="px-4 py-3 text-xs text-text-muted">{timeAgo(order.placed_at)}</td>
                    </tr>
                  ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
