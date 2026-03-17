"use client";
import { useLiveStats, useRiderLocations } from "@/lib/sse";
import { Users, Bike, UtensilsCrossed, ShoppingCart, Wifi, WifiOff } from "lucide-react";
import { cn, timeAgo } from "@/lib/utils";
import { LineChart, Line, ResponsiveContainer, Tooltip } from "recharts";
import { useState, useEffect } from "react";

interface SparkPoint { time: string; customers: number; partners: number; riders: number; }

export default function LiveUsersPage() {
  const { stats, connected } = useLiveStats();
  const { riders } = useRiderLocations();
  const [history, setHistory] = useState<SparkPoint[]>([]);

  // Keep last 24 data points for sparklines
  useEffect(() => {
    setHistory((prev) => {
      const point: SparkPoint = {
        time: new Date().toISOString(),
        customers: stats.connected_by_role.customer,
        partners: stats.connected_by_role.restaurant_owner,
        riders: stats.connected_by_role.delivery_partner,
      };
      const next = [...prev, point];
      return next.slice(-24);
    });
  }, [stats]);

  const totalSessions =
    stats.connected_by_role.customer +
    stats.connected_by_role.restaurant_owner +
    stats.connected_by_role.delivery_partner;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Live Users</h1>
          <p className="text-sm text-text-muted mt-0.5">Active WebSocket sessions in real-time</p>
        </div>
        <div className={cn("flex items-center gap-1.5 text-xs font-medium px-2.5 py-1.5 rounded-lg", connected ? "bg-success/10 text-success" : "bg-error/10 text-error")}>
          {connected ? <Wifi size={12} /> : <WifiOff size={12} />}
          {connected ? "Live" : "Reconnecting…"}
        </div>
      </div>

      {/* Presence Summary Cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {[
          { label: "Total Sessions", value: totalSessions, icon: Users, color: "text-white" },
          { label: "Customers", value: stats.connected_by_role.customer, icon: ShoppingCart, color: "text-info" },
          { label: "Restaurant Partners", value: stats.connected_by_role.restaurant_owner, icon: UtensilsCrossed, color: "text-brand-400" },
          { label: "Delivery Partners", value: stats.connected_by_role.delivery_partner, icon: Bike, color: "text-success" },
        ].map((item) => (
          <div key={item.label} className="card flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <p className="text-xs text-text-secondary">{item.label}</p>
              <item.icon size={14} className={item.color} />
            </div>
            <p className={cn("text-3xl font-bold tabular-nums", item.color)}>{item.value}</p>
          </div>
        ))}
      </div>

      {/* Sparklines */}
      <div className="grid grid-cols-3 gap-4">
        {[
          { label: "Customers", key: "customers" as const, color: "#3B82F6" },
          { label: "Restaurant Partners", key: "partners" as const, color: "#F49D25" },
          { label: "Delivery Partners", key: "riders" as const, color: "#22C55E" },
        ].map((item) => (
          <div key={item.label} className="card">
            <p className="text-xs text-text-secondary mb-3">{item.label} — 24 data points</p>
            <ResponsiveContainer width="100%" height={60}>
              <LineChart data={history}>
                <Line type="monotone" dataKey={item.key} stroke={item.color} strokeWidth={2} dot={false} />
                <Tooltip
                  contentStyle={{ background: "#252525", border: "1px solid rgba(255,255,255,0.1)", borderRadius: 6, fontSize: 11 }}
                  itemStyle={{ color: "#fff" }}
                  labelFormatter={() => ""}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        ))}
      </div>

      {/* Online Riders Grid */}
      <div>
        <h2 className="text-sm font-semibold text-white mb-3">Online Riders ({riders.length})</h2>
        {riders.length === 0 ? (
          <div className="card text-center text-text-muted text-sm py-8">No riders online right now</div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
            {riders.map((rider) => (
              <div key={rider.rider_id} className="card flex flex-col gap-2">
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-2">
                    <div className={cn(
                      "w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-xs",
                      rider.is_on_delivery ? "bg-brand-500" : "bg-success"
                    )}>
                      {rider.name.charAt(0).toUpperCase()}
                    </div>
                    <div>
                      <p className="text-sm font-medium text-white">{rider.name}</p>
                      <p className="text-xs text-text-muted">{rider.phone}</p>
                    </div>
                  </div>
                  <span className={cn(
                    "text-[10px] font-semibold px-1.5 py-0.5 rounded",
                    rider.is_on_delivery
                      ? "bg-brand-500/20 text-brand-400"
                      : "bg-success/20 text-success"
                  )}>
                    {rider.is_on_delivery ? "Active" : "Idle"}
                  </span>
                </div>
                <div className="grid grid-cols-2 gap-1 text-[11px]">
                  <div>
                    <p className="text-text-muted">Vehicle</p>
                    <p className="text-white capitalize">{rider.vehicle_type}</p>
                  </div>
                  <div>
                    <p className="text-text-muted">Last seen</p>
                    <p className="text-white">{timeAgo(rider.last_update)}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
