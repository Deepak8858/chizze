"use client";
import { useLiveOrders } from "@/lib/sse";
import { cn, formatCurrency, slaClass, timeAgo } from "@/lib/utils";
import { StatusBadge } from "@/components/ui/status-badge";
import type { OrderStatus, LiveOrder } from "@/types";

const COLUMNS: { status: OrderStatus; label: string }[] = [
  { status: "placed", label: "Placed" },
  { status: "confirmed", label: "Confirmed" },
  { status: "preparing", label: "Preparing" },
  { status: "ready", label: "Ready" },
  { status: "pickedUp", label: "Picked Up" },
  { status: "outForDelivery", label: "Out for Delivery" },
];

function OrderCard({ order }: { order: LiveOrder }) {
  const sla = slaClass(order.status, order.placed_at);

  return (
    <div className={cn("rounded-lg p-3 bg-bg-elevated border-white/[0.06] border hover:border-white/[0.14] transition-all", sla)}>
      <div className="flex items-start justify-between gap-1 mb-1.5">
        <span className="text-xs font-mono font-bold text-brand-400">#{order.order_number}</span>
        <StatusBadge status={order.status} />
      </div>
      <p className="text-xs text-white font-medium truncate">{order.restaurant_name}</p>
      <p className="text-[11px] text-text-muted truncate">{order.customer_name}</p>
      <div className="flex items-center justify-between mt-2">
        <span className="text-xs font-semibold text-white">{formatCurrency(order.grand_total)}</span>
        <span className={cn("text-[10px]",
          sla === "sla-critical" ? "text-error" :
          sla === "sla-warning" ? "text-warning" : "text-text-muted"
        )}>
          {timeAgo(order.placed_at)}
        </span>
      </div>
    </div>
  );
}

export default function LiveOrdersPage() {
  const { orders, connected } = useLiveOrders();

  const ordersByStatus = COLUMNS.reduce<Record<string, LiveOrder[]>>((acc, col) => {
    acc[col.status] = orders.filter((o) => o.status === col.status);
    return acc;
  }, {});

  const totalActive = orders.length;
  const criticalCount = orders.filter(
    (o) => slaClass(o.status, o.placed_at) === "sla-critical"
  ).length;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Live Order Board</h1>
          <p className="text-sm text-text-muted">
            {totalActive} active orders
            {criticalCount > 0 && (
              <span className="ml-2 text-error font-medium">⚠ {criticalCount} critical</span>
            )}
          </p>
        </div>
        <div className="flex items-center gap-4 text-xs">
          <div className="flex items-center gap-1.5">
            <span className="w-3 h-3 rounded-sm bg-info" /> Normal
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-3 h-3 rounded-sm bg-warning" /> Slow
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-3 h-3 rounded-sm bg-error" /> Critical
          </div>
          {!connected && (
            <span className="text-error bg-error/10 px-2 py-1 rounded">Disconnected</span>
          )}
        </div>
      </div>

      {/* Kanban */}
      <div className="flex gap-3 overflow-x-auto pb-2">
        {COLUMNS.map((col) => {
          const colOrders = ordersByStatus[col.status] ?? [];
          return (
            <div
              key={col.status}
              className="flex-shrink-0 w-56 card !p-0 overflow-hidden"
            >
              {/* Column header */}
              <div className="px-3 py-2 border-b border-white/[0.06] bg-bg-elevated flex items-center justify-between">
                <span className="text-xs font-semibold text-white">{col.label}</span>
                <span className={cn(
                  "text-[10px] font-bold px-1.5 py-0.5 rounded-full",
                  colOrders.length > 0 ? "bg-brand-500/20 text-brand-400" : "bg-white/5 text-text-muted"
                )}>
                  {colOrders.length}
                </span>
              </div>

              {/* Cards */}
              <div className="p-2 space-y-2 min-h-[100px] max-h-[calc(100vh-280px)] overflow-y-auto">
                {colOrders.length === 0 ? (
                  <p className="text-center text-text-muted text-[11px] py-4">Empty</p>
                ) : (
                  colOrders.map((order) => (
                    <OrderCard key={order.order_id} order={order} />
                  ))
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
