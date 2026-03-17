"use client";
import { useQuery } from "@tanstack/react-query";
import { ordersApi } from "@/lib/api";
import { formatDateTime } from "@/lib/utils";

function slaClass(minutes: number): string {
  if (minutes >= 45) return "sla-critical";
  if (minutes >= 30) return "sla-warning";
  return "sla-normal";
}
import type { Order } from "@/types";
import { AlertTriangle, Clock, CheckCircle } from "lucide-react";

function SLACard({ order }: { order: Order & { elapsed_min: number } }) {
  const cls = slaClass(order.elapsed_min);
  return (
    <div className={`card p-4 border ${cls === "sla-critical" ? "border-status-error/40" : cls === "sla-warning" ? "border-status-warning/40" : "border-white/5"}`}>
      <div className="flex items-center justify-between mb-2">
        <span className="font-mono text-xs text-brand-400">#{order.$id.slice(-8).toUpperCase()}</span>
        <span className={`text-xs font-bold ${cls === "sla-critical" ? "text-status-error" : cls === "sla-warning" ? "text-status-warning" : "text-status-success"}`}>
          {order.elapsed_min}m elapsed
        </span>
      </div>
      <p className="text-white text-sm font-medium truncate">{order.restaurant_id}</p>
      <p className="text-text-muted text-xs mt-1 capitalize">{order.status.replace(/_/g, " ")}</p>
      <div className="mt-2 bg-surface-200 rounded-full h-1.5 overflow-hidden">
        <div
          className={`h-full rounded-full transition-all ${cls === "sla-critical" ? "bg-status-error" : cls === "sla-warning" ? "bg-status-warning" : "bg-status-success"}`}
          style={{ width: `${Math.min((order.elapsed_min / 60) * 100, 100)}%` }}
        />
      </div>
    </div>
  );
}

export default function SLAPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["sla-active-orders"],
    queryFn: () => ordersApi.getActive() as Promise<{ data: (Order & { elapsed_min: number })[] }>,
    refetchInterval: 30_000,
  });

  const critical = data?.data?.filter(o => o.elapsed_min >= 45) ?? [];
  const warning = data?.data?.filter(o => o.elapsed_min >= 30 && o.elapsed_min < 45) ?? [];
  const normal = data?.data?.filter(o => o.elapsed_min < 30) ?? [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">SLA Monitor</h1>
        <p className="text-sm text-text-muted">Real-time delivery SLA tracking · auto-refresh every 30s</p>
      </div>

      {/* Summary row */}
      <div className="grid grid-cols-3 gap-4">
        <div className="card p-4 border border-status-error/20">
          <div className="flex items-center gap-2 mb-1">
            <AlertTriangle size={14} className="text-status-error" />
            <p className="text-xs text-text-muted">Critical (&gt;45m)</p>
          </div>
          <p className="text-2xl font-bold text-status-error">{critical.length}</p>
        </div>
        <div className="card p-4 border border-status-warning/20">
          <div className="flex items-center gap-2 mb-1">
            <Clock size={14} className="text-status-warning" />
            <p className="text-xs text-text-muted">Warning (30–45m)</p>
          </div>
          <p className="text-2xl font-bold text-status-warning">{warning.length}</p>
        </div>
        <div className="card p-4 border border-status-success/20">
          <div className="flex items-center gap-2 mb-1">
            <CheckCircle size={14} className="text-status-success" />
            <p className="text-xs text-text-muted">On Track (&lt;30m)</p>
          </div>
          <p className="text-2xl font-bold text-status-success">{normal.length}</p>
        </div>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
          {[...Array(8)].map((_, i) => <div key={i} className="skeleton rounded-xl h-28" />)}
        </div>
      ) : (
        <>
          {critical.length > 0 && (
            <div>
              <h2 className="text-sm font-semibold text-status-error mb-3 flex items-center gap-1.5">
                <AlertTriangle size={14} /> Critical Orders
              </h2>
              <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
                {critical.map(o => <SLACard key={o.$id} order={o} />)}
              </div>
            </div>
          )}
          {warning.length > 0 && (
            <div>
              <h2 className="text-sm font-semibold text-status-warning mb-3 flex items-center gap-1.5">
                <Clock size={14} /> Warning Orders
              </h2>
              <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
                {warning.map(o => <SLACard key={o.$id} order={o} />)}
              </div>
            </div>
          )}
          {normal.length > 0 && (
            <div>
              <h2 className="text-sm font-semibold text-text-secondary mb-3">On Track</h2>
              <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
                {normal.map(o => <SLACard key={o.$id} order={o} />)}
              </div>
            </div>
          )}
          {(data?.data?.length ?? 0) === 0 && (
            <div className="text-center py-16 text-text-muted">
              <CheckCircle size={32} className="mx-auto mb-2 text-status-success/50" />
              <p>No active orders right now</p>
            </div>
          )}
        </>
      )}
    </div>
  );
}
