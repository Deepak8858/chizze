"use client";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { payoutsApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDateTime, formatCurrency } from "@/lib/utils";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { Payout } from "@/types";
import { CheckCircle, XCircle, IndianRupee, Download } from "lucide-react";
import { exportCSV } from "@/lib/export";

const TABS = ["all", "pending", "processing", "completed", "failed"];

export default function PayoutsPage() {
  const [tab, setTab] = useState("pending");
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["admin-payouts", tab],
    queryFn: () => payoutsApi.list({ status: tab === "all" ? undefined : tab, limit: 200 }) as Promise<{ data: Payout[] }>,
    refetchInterval: 60_000,
  });

  const approveMutation = useMutation({
    mutationFn: ({ id, approved, reason }: { id: string; approved: boolean; reason?: string }) =>
      payoutsApi.approve(id, approved, reason),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-payouts"] }); toast.success("Payout updated"); },
    onError: () => toast.error("Failed"),
  });

  const totals = data?.data?.reduce(
    (acc, p) => ({ ...acc, total: acc.total + p.amount, pending: acc.pending + (p.status === "pending" ? p.amount : 0) }),
    { total: 0, pending: 0 }
  ) ?? { total: 0, pending: 0 };

  const columns: ColumnDef<Payout, unknown>[] = [
    {
      accessorKey: "partner_name",
      header: "Recipient",
      cell: ({ row: { original: p } }) => (
        <div>
          <p className="font-medium text-white">{p.partner_name ?? "Partner"}</p>
          <p className="text-xs text-text-muted">{p.partner_id?.slice(-8) ?? p.user_id?.slice(-8)}</p>
        </div>
      ),
    },
    {
      accessorKey: "amount",
      header: "Amount",
      cell: ({ getValue }) => (
        <div className="flex items-center gap-1 font-semibold text-white">
          <IndianRupee size={12} /> {(getValue() as number).toLocaleString()}
        </div>
      ),
    },
    {
      accessorKey: "method",
      header: "Method",
      cell: ({ getValue }) => <span className="text-xs text-text-secondary capitalize">{(getValue() as string).replace("_", " ")}</span>,
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ getValue }) => <StatusBadge status={getValue() as string} />,
    },
    {
      accessorKey: "note",
      header: "Note",
      cell: ({ getValue }) => <span className="text-xs text-text-muted truncate max-w-32">{getValue() as string || "—"}</span>,
    },
    {
      accessorKey: "reference",
      header: "Reference",
      cell: ({ getValue }) => <span className="font-mono text-xs text-text-muted">{getValue() as string || "—"}</span>,
    },
    {
      id: "actions",
      header: "Actions",
      cell: ({ row }) =>
        row.original.status === "pending" ? (
          <div className="flex items-center gap-2">
            <button
              onClick={() => approveMutation.mutate({ id: row.original.$id, approved: true, reason: undefined })}
              className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-status-success/10 text-status-success hover:bg-status-success/20"
            >
              <CheckCircle size={12} /> Approve
            </button>
            <button
              onClick={() => approveMutation.mutate({ id: row.original.$id, approved: false, reason: undefined })}
              className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-status-error/10 text-status-error hover:bg-status-error/20"
            >
              <XCircle size={12} /> Reject
            </button>
          </div>
        ) : null,
    },
  ];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Payouts</h1>
          <p className="text-sm text-text-muted">{data?.data?.length ?? 0} records</p>
        </div>
        <button
          onClick={() => exportCSV((data?.data ?? []) as unknown as Record<string, unknown>[], "payouts")}
          className="flex items-center gap-2 text-xs px-3 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-text-secondary transition-colors"
        >
          <Download size={14} /> Export CSV
        </button>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 gap-4">
        <div className="card p-4">
          <p className="text-xs text-text-muted mb-1">Total Volume</p>
          <p className="text-xl font-bold text-white">{formatCurrency(totals.total)}</p>
        </div>
        <div className="card p-4">
          <p className="text-xs text-text-muted mb-1">Pending</p>
          <p className="text-xl font-bold text-status-warning">{formatCurrency(totals.pending)}</p>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 bg-surface-200 rounded-lg p-1 w-fit">
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`text-xs px-3 py-1.5 rounded-md capitalize transition-colors ${
              tab === t ? "bg-brand-500 text-white" : "text-text-muted hover:text-white"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      <DataTable
        columns={columns}
        data={data?.data ?? []}
        loading={isLoading}
        searchColumn="partner_id"
        searchPlaceholder="Search payout…"
      />
    </div>
  );
}
