"use client";
import { useState } from "react";
import { useParams } from "next/navigation";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { ordersApi, deliveryApi } from "@/lib/api";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatCurrency, formatDateTime, timeAgo, parseOrderItems } from "@/lib/utils";
import { toast } from "sonner";
import type { Order, OrderStatus, DeliveryPartner } from "@/types";
import Link from "next/link";
import {
  ArrowLeft, Package, User, UtensilsCrossed, Bike,
  Clock, XCircle, RefreshCw, IndianRupee, CheckCircle,
  AlertTriangle, MapPin, Phone,
} from "lucide-react";

// ─── Timeline config ──────────────────────────────────────────────────────────
const TIMELINE: { status: OrderStatus; label: string; field: keyof Order | null }[] = [
  { status: "placed",         label: "Order Placed",      field: "placed_at" },
  { status: "confirmed",      label: "Confirmed",         field: "confirmed_at" },
  { status: "preparing",      label: "Preparing",         field: "prepared_at" },
  { status: "ready",          label: "Ready for Pickup",  field: null },
  { status: "pickedUp",       label: "Picked Up",         field: "picked_up_at" },
  { status: "outForDelivery", label: "Out for Delivery",  field: null },
  { status: "delivered",      label: "Delivered",         field: "delivered_at" },
];
const STATUS_ORDER: OrderStatus[] = [
  "placed","confirmed","preparing","ready","pickedUp","outForDelivery","delivered",
];

function InfoCard({ title, children, icon }: { title: string; children: React.ReactNode; icon: React.ReactNode }) {
  return (
    <div className="card p-4">
      <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-3 flex items-center gap-1.5">
        {icon} {title}
      </h3>
      {children}
    </div>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-4 py-1.5 border-b border-white/[0.04] last:border-0">
      <span className="text-xs text-text-muted flex-shrink-0">{label}</span>
      <span className="text-xs text-white text-right">{value}</span>
    </div>
  );
}

// ─── Main page ────────────────────────────────────────────────────────────────
export default function OrderDetailPage() {
  const { id } = useParams<{ id: string }>();
  const qc = useQueryClient();

  const [showCancel, setShowCancel] = useState(false);
  const [cancelReason, setCancelReason] = useState("");
  const [showReassign, setShowReassign] = useState(false);
  const [selectedRider, setSelectedRider] = useState("");

  const { data, isLoading } = useQuery({
    queryKey: ["order-detail", id],
    queryFn: () => ordersApi.get(id) as Promise<{ data: Order }>,
    enabled: !!id,
    refetchInterval: 30_000,
  });

  const { data: ridersData } = useQuery({
    queryKey: ["online-riders-reassign"],
    queryFn: () => deliveryApi.list({ is_online: true, limit: 50 }) as Promise<{ data: DeliveryPartner[] }>,
    enabled: showReassign,
  });

  const cancelMutation = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) => ordersApi.cancel(id, reason),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["order-detail", id] });
      toast.success("Order cancelled");
      setShowCancel(false);
      setCancelReason("");
    },
    onError: () => toast.error("Failed to cancel order"),
  });

  const reassignMutation = useMutation({
    mutationFn: ({ id, rider_id }: { id: string; rider_id: string }) => ordersApi.reassign(id, rider_id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["order-detail", id] });
      toast.success("Rider reassigned");
      setShowReassign(false);
      setSelectedRider("");
    },
    onError: () => toast.error("Failed to reassign rider"),
  });

  // ─── Loading ───────────────────────────────────────────────────────────────
  if (isLoading) {
    return (
      <div className="space-y-4">
        <div className="skeleton h-8 w-48 rounded-lg" />
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          {[...Array(6)].map((_, i) => <div key={i} className="skeleton h-40 rounded-xl" />)}
        </div>
      </div>
    );
  }

  const order = data?.data;
  if (!order) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4">
        <AlertTriangle size={32} className="text-status-warning" />
        <p className="text-white font-semibold">Order not found</p>
        <Link href="/orders" className="text-brand-400 hover:underline text-sm">← Back to Orders</Link>
      </div>
    );
  }

  const items = parseOrderItems(order.items);
  const currentIdx = STATUS_ORDER.indexOf(order.status);
  const isCancelled = order.status === "cancelled";
  const isFinal = ["delivered", "cancelled"].includes(order.status);

  return (
    <div className="space-y-5">
      {/* ─── Page header ─────────────────────────────────────────────────── */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <Link href="/orders" className="p-2 rounded-lg bg-white/5 hover:bg-white/10 text-text-muted hover:text-white transition-colors">
            <ArrowLeft size={16} />
          </Link>
          <div>
            <h1 className="text-xl font-bold text-white flex items-center gap-2">
              <Package size={18} className="text-brand-400" />
              Order #{order.order_number}
            </h1>
            <p className="text-xs text-text-muted mt-0.5">
              Placed {timeAgo(order.placed_at)} · {formatDateTime(order.placed_at)}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <StatusBadge status={order.status} />
          <StatusBadge status={order.payment_status} />
          {!isFinal && (
            <>
              <button
                onClick={() => setShowReassign(true)}
                className="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-text-secondary transition-colors"
              >
                <RefreshCw size={12} /> Reassign Rider
              </button>
              <button
                onClick={() => setShowCancel(true)}
                className="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-status-error/10 hover:bg-status-error/20 text-status-error transition-colors"
              >
                <XCircle size={12} /> Cancel Order
              </button>
            </>
          )}
        </div>
      </div>

      {/* ─── Timeline ─────────────────────────────────────────────────────── */}
      {!isCancelled ? (
        <div className="card p-4">
          <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-4">Timeline</h3>
          <div className="flex items-start gap-0 overflow-x-auto pb-1">
            {TIMELINE.map((step, i) => {
              const done = currentIdx >= STATUS_ORDER.indexOf(step.status);
              const active = order.status === step.status;
              const timestamp = step.field ? (order[step.field] as string | undefined) : null;
              return (
                <div key={step.status} className="flex items-center flex-shrink-0">
                  <div className="flex flex-col items-center gap-1.5 min-w-[80px] text-center">
                    <div className={`w-7 h-7 rounded-full flex items-center justify-center border-2 transition-colors ${
                      active   ? "bg-brand-500 border-brand-500" :
                      done     ? "bg-status-success/20 border-status-success" :
                                 "bg-white/5 border-white/10"
                    }`}>
                      {done
                        ? <CheckCircle size={14} className={active ? "text-white" : "text-status-success"} />
                        : <Clock size={14} className="text-text-muted" />
                      }
                    </div>
                    <p className={`text-[10px] font-medium leading-tight ${active ? "text-brand-400" : done ? "text-white" : "text-text-muted"}`}>
                      {step.label}
                    </p>
                    {timestamp && (
                      <p className="text-[9px] text-text-muted">{formatDateTime(timestamp).split(",")[1]?.trim()}</p>
                    )}
                  </div>
                  {i < TIMELINE.length - 1 && (
                    <div className={`h-0.5 w-8 flex-shrink-0 -mt-4 ${
                      currentIdx > STATUS_ORDER.indexOf(step.status) ? "bg-status-success/40" : "bg-white/10"
                    }`} />
                  )}
                </div>
              );
            })}
          </div>
        </div>
      ) : (
        <div className="card p-4 border-status-error/30 bg-status-error/5">
          <div className="flex items-center gap-2 text-status-error">
            <XCircle size={16} />
            <p className="font-semibold text-sm">Order Cancelled</p>
          </div>
          {order.cancellation_reason && (
            <p className="text-xs text-text-muted mt-1">Reason: {order.cancellation_reason}</p>
          )}
          {order.cancelled_at && (
            <p className="text-xs text-text-muted">At: {formatDateTime(order.cancelled_at)}</p>
          )}
        </div>
      )}

      {/* ─── Main grid ────────────────────────────────────────────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        {/* Left 2/3 */}
        <div className="lg:col-span-2 space-y-4">
          {/* Items */}
          <div className="card p-4">
            <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-3 flex items-center gap-1.5">
              <Package size={12} /> Items Ordered
            </h3>
            <div className="space-y-2">
              {items.length > 0 ? items.map((item: { name: string; quantity: number; price: number; is_veg?: boolean }, i: number) => (
                <div key={i} className="flex items-center justify-between py-2 border-b border-white/[0.04] last:border-0">
                  <div className="flex items-center gap-2">
                    <span className={`w-3 h-3 rounded-sm border flex-shrink-0 ${item.is_veg ? "border-status-success" : "border-status-error"}`}>
                      <span className={`block w-1.5 h-1.5 rounded-full m-auto mt-[2px] ${item.is_veg ? "bg-status-success" : "bg-status-error"}`} />
                    </span>
                    <span className="text-sm text-white">{item.name}</span>
                    <span className="text-xs text-text-muted">×{item.quantity}</span>
                  </div>
                  <span className="text-sm font-medium text-white">{formatCurrency(item.price * item.quantity)}</span>
                </div>
              )) : (
                <p className="text-text-muted text-xs py-2">No item details available</p>
              )}
            </div>
            {order.special_instructions && (
              <div className="mt-3 p-2.5 rounded-lg bg-white/[0.03] border border-white/[0.06]">
                <p className="text-[10px] text-text-muted mb-0.5">Special instructions</p>
                <p className="text-xs text-text-secondary">{order.special_instructions}</p>
              </div>
            )}
          </div>

          {/* Pricing breakdown */}
          <InfoCard title="Pricing Breakdown" icon={<IndianRupee size={12} />}>
            <Row label="Item Total"    value={formatCurrency(order.item_total)} />
            <Row label="Delivery Fee"  value={formatCurrency(order.delivery_fee)} />
            <Row label="Platform Fee"  value={formatCurrency(order.platform_fee)} />
            <Row label="GST"           value={formatCurrency(order.gst)} />
            {order.tip > 0 && <Row label="Tip" value={formatCurrency(order.tip)} />}
            {order.discount > 0 && (
              <Row label={`Discount${order.coupon_code ? ` (${order.coupon_code})` : ""}`}
                   value={<span className="text-status-success">−{formatCurrency(order.discount)}</span>} />
            )}
            <div className="flex items-center justify-between pt-2 mt-1 border-t border-white/10">
              <span className="text-sm font-bold text-white">Grand Total</span>
              <span className="text-sm font-bold text-white">{formatCurrency(order.grand_total)}</span>
            </div>
            <Row label="Payment Method" value={<span className="capitalize">{order.payment_method.replace("_", " ")}</span>} />
            {order.payment_id && <Row label="Payment ID" value={<span className="font-mono text-[10px]">{order.payment_id}</span>} />}
          </InfoCard>
        </div>

        {/* Right 1/3 */}
        <div className="space-y-4">
          {/* Customer */}
          <InfoCard title="Customer" icon={<User size={12} />}>
            <Row label="Customer ID"  value={<span className="font-mono text-brand-400">{order.customer_id.slice(-12)}</span>} />
            <Row label="Delivery Type" value={<span className="capitalize">{order.delivery_type.replace("_", " ")}</span>} />
            {order.delivery_instructions && (
              <div className="mt-2 p-2 rounded bg-white/[0.03] border border-white/[0.04]">
                <p className="text-[10px] text-text-muted">Delivery note</p>
                <p className="text-xs text-text-secondary mt-0.5">{order.delivery_instructions}</p>
              </div>
            )}
          </InfoCard>

          {/* Restaurant */}
          <InfoCard title="Restaurant" icon={<UtensilsCrossed size={12} />}>
            <Row label="Name" value={order.restaurant_name} />
            <Row label="ID"   value={<span className="font-mono text-brand-400 text-[10px]">{order.restaurant_id.slice(-12)}</span>} />
            <Row label="Est. Time" value={`${order.estimated_delivery_min} min`} />
          </InfoCard>

          {/* Delivery Partner */}
          {order.delivery_partner_id ? (
            <InfoCard title="Delivery Rider" icon={<Bike size={12} />}>
              {order.delivery_partner_name && <Row label="Name"  value={order.delivery_partner_name} />}
              {order.delivery_partner_phone && (
                <Row label="Phone" value={
                  <a href={`tel:${order.delivery_partner_phone}`} className="flex items-center gap-1 text-brand-400 hover:underline">
                    <Phone size={10} /> {order.delivery_partner_phone}
                  </a>
                } />
              )}
              <Row label="Partner ID" value={<span className="font-mono text-[10px]">{order.delivery_partner_id.slice(-12)}</span>} />
            </InfoCard>
          ) : (
            <InfoCard title="Delivery Rider" icon={<Bike size={12} />}>
              <p className="text-xs text-text-muted">No rider assigned yet</p>
            </InfoCard>
          )}

          {/* Order meta */}
          <InfoCard title="Order Meta" icon={<Clock size={12} />}>
            <Row label="Order ID" value={<span className="font-mono text-[10px]">{order.$id}</span>} />
            <Row label="Placed"   value={formatDateTime(order.placed_at)} />
            {order.delivered_at && <Row label="Delivered" value={formatDateTime(order.delivered_at)} />}
          </InfoCard>
        </div>
      </div>

      {/* ─── Cancel modal ──────────────────────────────────────────────────── */}
      {showCancel && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50" onClick={() => setShowCancel(false)}>
          <div className="card w-full max-w-sm p-6 space-y-4" onClick={e => e.stopPropagation()}>
            <h2 className="text-lg font-bold text-white flex items-center gap-2">
              <XCircle size={18} className="text-status-error" /> Cancel Order
            </h2>
            <p className="text-text-secondary text-sm">
              This will cancel order <strong className="text-white">#{order.order_number}</strong>. This action cannot be undone.
            </p>
            <div>
              <label className="text-xs text-text-muted mb-1 block">Cancellation reason</label>
              <textarea
                value={cancelReason}
                onChange={e => setCancelReason(e.target.value)}
                rows={3}
                placeholder="e.g. Restaurant closed, Customer request…"
                className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-text-muted focus:outline-none focus:border-brand-500 resize-none"
              />
            </div>
            <div className="flex gap-3">
              <button
                onClick={() => cancelMutation.mutate({ id: order.$id, reason: cancelReason })}
                disabled={!cancelReason || cancelMutation.isPending}
                className="flex-1 py-2 rounded-lg bg-status-error hover:bg-red-600 text-white text-sm font-medium disabled:opacity-50 transition-colors"
              >
                {cancelMutation.isPending ? "Cancelling…" : "Cancel Order"}
              </button>
              <button onClick={() => setShowCancel(false)} className="flex-1 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-text-secondary text-sm transition-colors">
                Back
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ─── Reassign modal ────────────────────────────────────────────────── */}
      {showReassign && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50" onClick={() => setShowReassign(false)}>
          <div className="card w-full max-w-sm p-6 space-y-4" onClick={e => e.stopPropagation()}>
            <h2 className="text-lg font-bold text-white flex items-center gap-2">
              <RefreshCw size={18} className="text-brand-400" /> Reassign Rider
            </h2>
            <div>
              <label className="text-xs text-text-muted mb-1 block">Select online rider</label>
              <select
                value={selectedRider}
                onChange={e => setSelectedRider(e.target.value)}
                className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
              >
                <option value="">— Choose a rider —</option>
                {ridersData?.data?.map(r => (
                  <option key={r.$id} value={r.$id}>
                    {r.name ?? r.$id.slice(-8)} · {r.vehicle_type}
                  </option>
                ))}
              </select>
            </div>
            <div className="flex gap-3">
              <button
                onClick={() => reassignMutation.mutate({ id: order.$id, rider_id: selectedRider })}
                disabled={!selectedRider || reassignMutation.isPending}
                className="flex-1 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium disabled:opacity-50 transition-colors"
              >
                {reassignMutation.isPending ? "Reassigning…" : "Reassign"}
              </button>
              <button onClick={() => setShowReassign(false)} className="flex-1 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-text-secondary text-sm transition-colors">
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
