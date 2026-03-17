"use client";
import { useState, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import { analyticsApi } from "@/lib/api";
import { formatCurrency, formatDate } from "@/lib/utils";
import { exportCSV, exportPDF } from "@/lib/export";
import { AreaChart, Area, BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";
import { Download, FileText } from "lucide-react";

const RANGES = ["7d", "30d", "90d", "1y"] as const;
type Range = typeof RANGES[number];

const CustomTooltip = ({ active, payload, label }: any) =>
  active && payload?.length ? (
    <div className="bg-surface-300 border border-white/10 rounded-lg px-3 py-2 text-xs">
      <p className="text-text-muted mb-1">{label}</p>
      {payload.map((p: any) => (
        <p key={p.dataKey} style={{ color: p.color }}>{p.name}: {typeof p.value === "number" && p.dataKey.includes("revenue") ? formatCurrency(p.value) : p.value}</p>
      ))}
    </div>
  ) : null;

export default function ReportsPage() {
  const [range, setRange] = useState<Range>("30d");
  const reportRef = useRef<HTMLDivElement>(null);

  const { data: revenue, isLoading: revLoading } = useQuery({
    queryKey: ["report-revenue", range],
    queryFn: () => analyticsApi.getRevenue({ range }) as Promise<{ data: { date: string; revenue: number; orders: number; avg_order: number }[] }>,
  });

  const totals = revenue?.data?.reduce(
    (acc, d) => ({ revenue: acc.revenue + d.revenue, orders: acc.orders + d.orders }),
    { revenue: 0, orders: 0 }
  ) ?? { revenue: 0, orders: 0 };

  return (
    <div className="space-y-6" ref={reportRef}>
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Reports</h1>
          <p className="text-sm text-text-muted">Financial & operational reports</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => exportCSV(revenue?.data ?? [], `revenue-${range}`)}
            className="flex items-center gap-2 text-xs px-3 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-text-secondary transition-colors"
          >
            <Download size={14} /> CSV
          </button>
          <button
            onClick={() => reportRef.current && exportPDF(reportRef.current as unknown as string, `report-${range}`)}
            className="flex items-center gap-2 text-xs px-3 py-2 rounded-lg bg-brand-500/10 hover:bg-brand-500/20 text-brand-400 transition-colors"
          >
            <FileText size={14} /> PDF
          </button>
        </div>
      </div>

      {/* Range toggle */}
      <div className="flex gap-1 bg-surface-200 rounded-lg p-1 w-fit">
        {RANGES.map(r => (
          <button
            key={r}
            onClick={() => setRange(r)}
            className={`text-xs px-3 py-1.5 rounded-md uppercase transition-colors ${
              range === r ? "bg-brand-500 text-white" : "text-text-muted hover:text-white"
            }`}
          >
            {r}
          </button>
        ))}
      </div>

      {/* KPI row */}
      <div className="grid grid-cols-3 gap-4">
        <div className="card p-4">
          <p className="text-xs text-text-muted mb-1">Total Revenue</p>
          <p className="text-2xl font-bold text-white">{formatCurrency(totals.revenue)}</p>
        </div>
        <div className="card p-4">
          <p className="text-xs text-text-muted mb-1">Total Orders</p>
          <p className="text-2xl font-bold text-white">{totals.orders.toLocaleString()}</p>
        </div>
        <div className="card p-4">
          <p className="text-xs text-text-muted mb-1">Avg Order Value</p>
          <p className="text-2xl font-bold text-white">
            {totals.orders > 0 ? formatCurrency(totals.revenue / totals.orders) : "—"}
          </p>
        </div>
      </div>

      {/* Revenue chart */}
      <div className="card p-4">
        <h2 className="text-sm font-semibold text-white mb-4">Revenue Over Time</h2>
        {revLoading ? (
          <div className="skeleton h-56 rounded-lg" />
        ) : (
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={revenue?.data ?? []}>
              <defs>
                <linearGradient id="rev-grad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#F49D25" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#F49D25" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#ffffff08" />
              <XAxis dataKey="date" tick={{ fontSize: 10, fill: "#6B7280" }} tickFormatter={(v) => formatDate(v)} />
              <YAxis tick={{ fontSize: 10, fill: "#6B7280" }} tickFormatter={(v) => `₹${(v / 1000).toFixed(0)}k`} />
              <Tooltip content={<CustomTooltip />} />
              <Area type="monotone" dataKey="revenue" stroke="#F49D25" fill="url(#rev-grad)" strokeWidth={2} dot={false} name="Revenue" />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Orders chart */}
      <div className="card p-4">
        <h2 className="text-sm font-semibold text-white mb-4">Orders Per Day</h2>
        {revLoading ? (
          <div className="skeleton h-48 rounded-lg" />
        ) : (
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={revenue?.data ?? []}>
              <CartesianGrid strokeDasharray="3 3" stroke="#ffffff08" />
              <XAxis dataKey="date" tick={{ fontSize: 10, fill: "#6B7280" }} tickFormatter={(v) => formatDate(v)} />
              <YAxis tick={{ fontSize: 10, fill: "#6B7280" }} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="orders" fill="#F49D25" radius={[4, 4, 0, 0]} name="Orders" />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Raw data table */}
      <div className="card overflow-hidden">
        <table className="w-full text-xs">
          <thead className="bg-surface-200">
            <tr>
              {["Date", "Revenue", "Orders", "Avg Order"].map(h => (
                <th key={h} className="px-4 py-2.5 text-left text-text-muted font-medium">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {revLoading
              ? [...Array(7)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(4)].map((_, j) => <td key={j} className="px-4 py-3"><div className="skeleton h-3 rounded w-16" /></td>)}
                  </tr>
                ))
              : revenue?.data?.map((row, i) => (
                  <tr key={i} className="hover:bg-white/2 transition-colors">
                    <td className="px-4 py-3 text-text-secondary">{formatDate(row.date)}</td>
                    <td className="px-4 py-3 font-medium text-white">{formatCurrency(row.revenue)}</td>
                    <td className="px-4 py-3 text-white">{row.orders.toLocaleString()}</td>
                    <td className="px-4 py-3 text-text-secondary">{row.orders > 0 ? formatCurrency(row.revenue / row.orders) : "—"}</td>
                  </tr>
                ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
