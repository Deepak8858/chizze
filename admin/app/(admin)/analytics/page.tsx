"use client";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { analyticsApi } from "@/lib/api";
import { formatCurrency } from "@/lib/utils";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, LineChart, Line, PieChart, Pie, Cell } from "recharts";
import { Trophy, TrendingUp, ShoppingBag, ArrowUpDown } from "lucide-react";
import type { ItemAnalytics } from "@/types";

const LEADERBOARD_TABS = ["restaurants", "riders", "items"] as const;
const ITEM_SORT_KEYS = ["order_count", "revenue"] as const;

const CustomTooltip = ({ active, payload, label }: any) =>
  active && payload?.length ? (
    <div className="bg-surface-300 border border-white/10 rounded-lg px-3 py-2 text-xs">
      <p className="text-text-muted mb-1">{label}</p>
      {payload.map((p: any) => (
        <p key={p.dataKey} style={{ color: p.color }}>{p.name}: {p.value}</p>
      ))}
    </div>
  ) : null;

const MEDAL_COLORS = ["#F49D25", "#9CA3AF", "#CD7F32"];

export default function AnalyticsPage() {
  const [lbTab, setLbTab] = useState<typeof LEADERBOARD_TABS[number]>("restaurants");
  const [itemSort, setItemSort] = useState<typeof ITEM_SORT_KEYS[number]>("order_count");

  const { data: leaderboard, isLoading: lbLoading } = useQuery({
    queryKey: ["leaderboard", lbTab],
    queryFn: () => analyticsApi.getLeaderboard(lbTab) as Promise<{ data: { id: string; name: string; value: number; orders: number }[] }>,
  });

  const { data: retention, isLoading: retLoading } = useQuery({
    queryKey: ["retention"],
    queryFn: () => analyticsApi.getRetention() as Promise<{ data: { cohort: string; week_0: number; week_1: number; week_2: number; week_3: number; week_4: number }[] }>,
  });

  const { data: cities, isLoading: citiesLoading } = useQuery({
    queryKey: ["city-analytics"],
    queryFn: () => analyticsApi.getCities() as Promise<{ data: { city: string; orders: number; revenue: number; restaurants: number }[] }>,
  });

  const { data: itemsData, isLoading: itemsLoading } = useQuery({
    queryKey: ["items-analytics"],
    queryFn: () => analyticsApi.items() as Promise<{ data: ItemAnalytics[] }>,
  });

  const sortedItems = [...(itemsData?.data ?? [])]
    .sort((a, b) => b[itemSort] - a[itemSort])
    .slice(0, 20);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">Analytics</h1>
        <p className="text-sm text-text-muted">Leaderboards, retention, and city-level insights</p>
      </div>

      {/* Leaderboard */}
      <div className="card p-4">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-sm font-semibold text-white flex items-center gap-1.5">
            <Trophy size={14} className="text-rating" /> Leaderboards
          </h2>
          <div className="flex gap-1 bg-surface-200 rounded-lg p-1">
            {LEADERBOARD_TABS.map(t => (
              <button
                key={t}
                onClick={() => setLbTab(t)}
                className={`text-xs px-2.5 py-1 rounded-md capitalize transition-colors ${lbTab === t ? "bg-brand-500 text-white" : "text-text-muted hover:text-white"}`}
              >
                {t}
              </button>
            ))}
          </div>
        </div>
        {lbLoading ? (
          <div className="space-y-2">{[...Array(5)].map((_, i) => <div key={i} className="skeleton h-10 rounded-lg" />)}</div>
        ) : (
          <div className="space-y-2">
            {leaderboard?.data?.slice(0, 10).map((item, i) => (
              <div key={item.id} className="flex items-center gap-3 p-2.5 rounded-lg hover:bg-white/3 transition-colors">
                <span className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold ${i < 3 ? "bg-rating/20" : "bg-white/5 text-text-muted"}`} style={{ color: i < 3 ? MEDAL_COLORS[i] : undefined }}>
                  {i + 1}
                </span>
                <div className="flex-1 min-w-0">
                  <p className="text-white text-sm font-medium truncate">{item.name}</p>
                  <p className="text-text-muted text-xs">{item.orders} orders</p>
                </div>
                <span className="text-brand-400 font-semibold text-sm">{formatCurrency(item.value)}</span>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* City breakdown */}
      <div className="card p-4">
        <h2 className="text-sm font-semibold text-white mb-4">City Performance</h2>
        {citiesLoading ? (
          <div className="skeleton h-52 rounded-lg" />
        ) : (
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={cities?.data ?? []} layout="vertical">
              <CartesianGrid strokeDasharray="3 3" stroke="#ffffff08" />
              <XAxis type="number" tick={{ fontSize: 10, fill: "#6B7280" }} tickFormatter={(v) => `₹${(v / 1000).toFixed(0)}k`} />
              <YAxis type="category" dataKey="city" tick={{ fontSize: 10, fill: "#9CA3AF" }} width={80} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="revenue" fill="#F49D25" radius={[0, 4, 4, 0]} name="Revenue" />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Retention cohort */}
      <div className="card p-4 overflow-x-auto">
        <h2 className="text-sm font-semibold text-white mb-4 flex items-center gap-1.5">
          <TrendingUp size={14} className="text-brand-400" /> User Retention Cohorts
        </h2>
        {retLoading ? (
          <div className="skeleton h-40 rounded-lg" />
        ) : (
          <table className="w-full text-xs min-w-[500px]">
            <thead>
              <tr className="text-text-muted">
                <th className="text-left py-2 pr-4 font-medium">Cohort</th>
                {["Week 0", "Week 1", "Week 2", "Week 3", "Week 4"].map(w => (
                  <th key={w} className="text-center py-2 px-3 font-medium">{w}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {retention?.data?.map(row => (
                <tr key={row.cohort} className="hover:bg-white/2">
                  <td className="py-2.5 pr-4 text-text-secondary">{row.cohort}</td>
                  {[row.week_0, row.week_1, row.week_2, row.week_3, row.week_4].map((v, i) => {
                    const pct = v;
                    const opacity = Math.max(0.1, pct / 100);
                    return (
                      <td key={i} className="text-center py-2.5 px-3">
                        <span className="px-2 py-0.5 rounded text-xs font-medium" style={{ backgroundColor: `rgba(244,157,37,${opacity})`, color: pct > 30 ? "#fff" : "#F49D25" }}>
                          {pct}%
                        </span>
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Items analytics */}
      <div className="card p-4 overflow-x-auto">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-sm font-semibold text-white flex items-center gap-1.5">
            <ShoppingBag size={14} className="text-brand-400" /> Top Items
          </h2>
          <div className="flex gap-1 bg-surface-200 rounded-lg p-1">
            {ITEM_SORT_KEYS.map(k => (
              <button
                key={k}
                onClick={() => setItemSort(k)}
                className={`text-xs px-2.5 py-1 rounded-md capitalize transition-colors flex items-center gap-1 ${
                  itemSort === k ? "bg-brand-500 text-white" : "text-text-muted hover:text-white"
                }`}
              >
                <ArrowUpDown size={10} /> {k === "order_count" ? "Orders" : "Revenue"}
              </button>
            ))}
          </div>
        </div>
        {itemsLoading ? (
          <div className="space-y-2">{[...Array(5)].map((_, i) => <div key={i} className="skeleton h-9 rounded-lg" />)}</div>
        ) : (
          <table className="w-full text-xs min-w-[520px]">
            <thead>
              <tr className="text-text-muted border-b border-white/[0.06]">
                <th className="text-left py-2 pr-4 font-medium w-6">#</th>
                <th className="text-left py-2 pr-4 font-medium">Item</th>
                <th className="text-left py-2 pr-4 font-medium">Restaurant</th>
                <th className="text-left py-2 pr-4 font-medium">City</th>
                <th className="text-right py-2 pr-4 font-medium">Orders</th>
                <th className="text-right py-2 font-medium">Revenue</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/[0.04]">
              {sortedItems.map((item, i) => (
                <tr key={item.item_id} className="hover:bg-white/[0.02] transition-colors">
                  <td className="py-2.5 pr-4 text-text-muted">{i + 1}</td>
                  <td className="py-2.5 pr-4">
                    <span className="text-white font-medium">{item.item_name}</span>
                  </td>
                  <td className="py-2.5 pr-4 text-text-secondary">{item.restaurant_name}</td>
                  <td className="py-2.5 pr-4">
                    <span className="text-xs px-1.5 py-0.5 rounded bg-white/5 text-text-muted">{item.city}</span>
                  </td>
                  <td className="py-2.5 pr-4 text-right">
                    <span className={`font-medium ${itemSort === "order_count" ? "text-brand-400" : "text-text-secondary"}`}>
                      {item.order_count.toLocaleString()}
                    </span>
                  </td>
                  <td className="py-2.5 text-right">
                    <span className={`font-medium ${itemSort === "revenue" ? "text-brand-400" : "text-text-secondary"}`}>
                      {formatCurrency(item.revenue)}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* City orders bar */}
      <div className="card p-4">
        <h2 className="text-sm font-semibold text-white mb-4">Orders by City</h2>
        {citiesLoading ? <div className="skeleton h-48 rounded-lg" /> : (
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={cities?.data ?? []}>
              <CartesianGrid strokeDasharray="3 3" stroke="#ffffff08" />
              <XAxis dataKey="city" tick={{ fontSize: 10, fill: "#6B7280" }} />
              <YAxis tick={{ fontSize: 10, fill: "#6B7280" }} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="orders" fill="#3B82F6" radius={[4, 4, 0, 0]} name="Orders" />
              <Bar dataKey="restaurants" fill="#8B5CF6" radius={[4, 4, 0, 0]} name="Restaurants" />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  );
}
