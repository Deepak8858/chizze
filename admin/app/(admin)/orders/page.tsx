"use client";
import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ordersApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDateTime, formatCurrency } from "@/lib/utils";
import type { ColumnDef } from "@tanstack/react-table";
import type { Order, OrderStatus, StuckOrderCleanupDeleteResult } from "@/types";
import Link from "next/link";
import { ExternalLink } from "lucide-react";
import { toast } from "sonner";

const allCleanupStatuses: OrderStatus[] = [
  "placed",
  "confirmed",
  "preparing",
  "ready",
  "pickedUp",
  "outForDelivery",
  "delivered",
  "cancelled",
];

const defaultCleanupStatuses: OrderStatus[] = ["delivered", "cancelled"];

function statusLabel(status: OrderStatus): string {
  if (status === "pickedUp") return "picked up";
  if (status === "outForDelivery") return "out for delivery";
  return status;
}

function isActiveStatus(status: OrderStatus): boolean {
  return status !== "delivered" && status !== "cancelled";
}

export default function OrdersPage() {
  const qc = useQueryClient();
  const [selectedStatuses, setSelectedStatuses] = useState<OrderStatus[]>(defaultCleanupStatuses);
  const [minAgeMinutes, setMinAgeMinutes] = useState(180);
  const [deleteLimit, setDeleteLimit] = useState(200);
  const [confirmationText, setConfirmationText] = useState("");
  const [deleteResult, setDeleteResult] = useState<StuckOrderCleanupDeleteResult | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ["admin-orders"],
    queryFn: () => ordersApi.list({ limit: 200 }) as Promise<{ data: Order[] }>,
    refetchInterval: 30_000,
  });

  const previewFilters = useMemo(
    () => ({
      statuses: selectedStatuses,
      min_age_minutes: minAgeMinutes,
      page: 1,
      per_page: 100,
    }),
    [selectedStatuses, minAgeMinutes]
  );

  const {
    data: previewResponse,
    isFetching: isPreviewLoading,
    refetch: refetchPreview,
  } = useQuery({
    queryKey: ["admin-orders-stuck-preview", previewFilters],
    queryFn: () => ordersApi.previewStuck(previewFilters),
    enabled: false,
  });

  const preview = previewResponse?.data;

  const deleteMutation = useMutation({
    mutationFn: () =>
      ordersApi.deleteStuck({
        statuses: selectedStatuses,
        min_age_minutes: minAgeMinutes,
        limit: deleteLimit,
      }),
    onSuccess: (response) => {
      setDeleteResult(response.data);
      setConfirmationText("");
      qc.invalidateQueries({ queryKey: ["admin-orders"] });
      qc.invalidateQueries({ queryKey: ["admin-orders-stuck-preview"] });
      toast.success(
        `Cleanup complete: ${response.data.deleted_count} deleted, ${response.data.failed_count} failed, ${response.data.blocked_count} blocked`
      );
    },
    onError: () => {
      toast.error("Failed to delete stuck orders");
    },
  });

  const expectedConfirmation = `DELETE ${preview?.eligible_count ?? 0}`;
  const canDelete =
    (preview?.eligible_count ?? 0) > 0 &&
    confirmationText.trim() === expectedConfirmation &&
    !deleteMutation.isPending;

  function toggleStatus(status: OrderStatus): void {
    setDeleteResult(null);
    setConfirmationText("");
    setSelectedStatuses((current) => {
      if (current.includes(status)) {
        return current.filter((value) => value !== status);
      }
      return [...current, status];
    });
  }

  const columns: ColumnDef<Order, unknown>[] = [
    {
      accessorKey: "order_number",
      header: "Order #",
      cell: ({ row }) => (
        <Link href={`/orders/${row.original.$id}`} className="text-brand-400 hover:underline font-mono text-xs flex items-center gap-1">
          #{row.original.order_number} <ExternalLink size={11} />
        </Link>
      ),
    },
    {
      accessorKey: "customer_id",
      header: "Customer",
      cell: ({ getValue }) => <span className="text-text-secondary text-xs font-mono">{(getValue() as string).slice(-10)}</span>,
    },
    {
      accessorKey: "restaurant_name",
      header: "Restaurant",
      cell: ({ getValue }) => <span className="text-white text-xs">{getValue() as string}</span>,
    },
    {
      accessorKey: "grand_total",
      header: "Total",
      cell: ({ getValue }) => <span className="font-semibold text-white">{formatCurrency(getValue() as number)}</span>,
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ getValue }) => <StatusBadge status={getValue() as string} />,
    },
    {
      accessorKey: "payment_method",
      header: "Payment",
      cell: ({ getValue }) => (
        <span className="text-xs px-2 py-0.5 rounded bg-white/5 text-text-secondary capitalize">
          {(getValue() as string).replace("_", " ")}
        </span>
      ),
    },
    {
      accessorKey: "placed_at",
      header: "Placed At",
      cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDateTime(getValue() as string)}</span>,
    },
  ];

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-white">Orders</h1>
        <p className="text-sm text-text-muted">{data?.data?.length ?? 0} total</p>
      </div>

      <div className="card space-y-4">
        <div className="flex flex-col gap-1">
          <h2 className="text-lg font-semibold text-white">Stuck Order Cleanup</h2>
          <p className="text-xs text-text-muted">
            Preview stale orders first, then confirm with an exact phrase before hard deletion.
          </p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div>
            <p className="text-xs text-text-muted mb-2">Statuses to target</p>
            <div className="grid grid-cols-2 gap-2">
              {allCleanupStatuses.map((status) => (
                <label key={status} className="flex items-center gap-2 text-xs text-text-secondary">
                  <input
                    type="checkbox"
                    checked={selectedStatuses.includes(status)}
                    onChange={() => toggleStatus(status)}
                    className="h-3.5 w-3.5 rounded border-white/20 bg-bg-elevated"
                  />
                  <span className="capitalize">
                    {statusLabel(status)}
                    {isActiveStatus(status) ? " (guarded)" : ""}
                  </span>
                </label>
              ))}
            </div>
          </div>

          <div className="space-y-3">
            <div>
              <label className="text-xs text-text-muted mb-1 block">Minimum age (minutes)</label>
              <input
                type="number"
                min={1}
                value={minAgeMinutes}
                onChange={(event) => {
                  setDeleteResult(null);
                  setMinAgeMinutes(Math.max(1, Number(event.target.value) || 1));
                }}
                className="w-full bg-bg-elevated border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
              />
            </div>

            <div>
              <label className="text-xs text-text-muted mb-1 block">Delete limit</label>
              <input
                type="number"
                min={1}
                max={500}
                value={deleteLimit}
                onChange={(event) => {
                  setDeleteResult(null);
                  const nextLimit = Number(event.target.value) || 1;
                  setDeleteLimit(Math.min(500, Math.max(1, nextLimit)));
                }}
                className="w-full bg-bg-elevated border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
              />
            </div>

            <button
              onClick={() => {
                setDeleteResult(null);
                setConfirmationText("");
                refetchPreview();
              }}
              disabled={isPreviewLoading || selectedStatuses.length === 0}
              className="w-full px-3 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {isPreviewLoading ? "Previewing..." : "Preview Candidates"}
            </button>
          </div>
        </div>

        {preview && (
          <div className="rounded-lg border border-white/10 bg-bg-elevated p-3 space-y-3">
            <div className="flex flex-wrap items-center gap-3 text-xs">
              <span className="text-white">Eligible: {preview.eligible_count}</span>
              <span className="text-status-warning">Blocked: {preview.blocked_count}</span>
              <span className="text-text-muted">Min age: {preview.min_age_minutes} min</span>
              <span className="text-text-muted">Cutoff: {formatDateTime(preview.cutoff_time)}</span>
            </div>

            <div className="text-xs text-text-muted">
              Effective statuses: {preview.filters.effective_statuses.join(", ") || "none"}
              {preview.filters.blocked_statuses.length > 0 && (
                <span> | Guarded statuses: {preview.filters.blocked_statuses.join(", ")}</span>
              )}
            </div>

            {preview.orders.length > 0 && (
              <div className="max-h-40 overflow-y-auto rounded border border-white/10">
                {preview.orders.map((order) => (
                  <div key={order.$id} className="px-3 py-2 border-b border-white/5 last:border-b-0 text-xs flex items-center justify-between gap-3">
                    <div className="text-text-secondary font-mono">#{order.order_number}</div>
                    <div className="text-white capitalize">{statusLabel(order.status)}</div>
                    <div className="text-text-muted">{formatDateTime(order.placed_at)}</div>
                  </div>
                ))}
              </div>
            )}

            <div className="grid grid-cols-1 lg:grid-cols-[1fr_auto] gap-3 items-end">
              <div>
                <label className="text-xs text-text-muted mb-1 block">
                  Type <span className="font-mono text-white">{expectedConfirmation}</span> to confirm hard delete
                </label>
                <input
                  type="text"
                  value={confirmationText}
                  onChange={(event) => setConfirmationText(event.target.value)}
                  placeholder={expectedConfirmation}
                  className="w-full bg-bg-base border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-status-error"
                />
              </div>

              <button
                onClick={() => deleteMutation.mutate()}
                disabled={!canDelete}
                className="px-4 py-2 rounded-lg bg-status-error/90 hover:bg-status-error text-white text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                {deleteMutation.isPending ? "Deleting..." : "Delete Stuck Orders"}
              </button>
            </div>
          </div>
        )}

        {deleteResult && (
          <div className="rounded-lg border border-status-success/30 bg-status-success/10 p-3 text-xs text-text-secondary space-y-1">
            <p className="text-white font-medium">Latest cleanup result</p>
            <p>Examined: {deleteResult.examined_count}</p>
            <p>Eligible: {deleteResult.eligible_count}</p>
            <p>Deleted: {deleteResult.deleted_count}</p>
            <p>Failed: {deleteResult.failed_count}</p>
            <p>Blocked: {deleteResult.blocked_count}</p>
          </div>
        )}
      </div>

      <DataTable
        columns={columns}
        data={data?.data ?? []}
        loading={isLoading}
        searchColumn="order_number"
        searchPlaceholder="Search order #…"
      />
    </div>
  );
}
