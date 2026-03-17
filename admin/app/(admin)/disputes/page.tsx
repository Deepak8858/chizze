"use client";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { disputesApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDateTime } from "@/lib/utils";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { Dispute } from "@/types";
import { MessageSquare, RefreshCw } from "lucide-react";

const TABS = ["all", "open", "investigating", "resolved", "closed"];

export default function DisputesPage() {
  const [tab, setTab] = useState("open");
  const [selected, setSelected] = useState<Dispute | null>(null);
  const [resolution, setResolution] = useState("");
  const [refund, setRefund] = useState(false);
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["admin-disputes", tab],
    queryFn: () => disputesApi.list({ status: tab === "all" ? undefined : tab, limit: 200 }) as Promise<{ data: Dispute[] }>,
  });

  const resolveMutation = useMutation({
    mutationFn: ({ id, body }: { id: string; body: Record<string, unknown> }) =>
      disputesApi.resolve(id, body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["admin-disputes"] });
      toast.success("Dispute resolved");
      setSelected(null);
      setResolution("");
      setRefund(false);
    },
    onError: () => toast.error("Failed to resolve"),
  });

  const columns: ColumnDef<Dispute, unknown>[] = [
    {
      accessorKey: "order_id",
      header: "Order",
      cell: ({ getValue }) => <span className="font-mono text-xs text-brand-400">#{(getValue() as string).slice(-8).toUpperCase()}</span>,
    },
    {
      accessorKey: "raised_by",
      header: "Raised By",
      cell: ({ row: { original: d } }) => (
        <div>
          <p className="text-white text-xs capitalize">{d.raised_by_role}</p>
          <p className="text-text-muted text-xs">{(d.raised_by as string).slice(-8)}</p>
        </div>
      ),
    },
    {
      accessorKey: "type",
      header: "Type",
      cell: ({ getValue }) => (
        <span className="text-xs text-text-secondary capitalize">{(getValue() as string).replace(/_/g, " ")}</span>
      ),
    },
    {
      accessorKey: "description",
      header: "Description",
      cell: ({ getValue }) => (
        <span className="text-xs text-text-muted line-clamp-2 max-w-48">{getValue() as string}</span>
      ),
    },
    {
      accessorKey: "refund_amount",
      header: "Refund",
      cell: ({ getValue }) => (
        <span className={`text-xs ${(getValue() as number) > 0 ? "text-status-success" : "text-text-muted"}`}>
          {(getValue() as number) > 0 ? `₹${(getValue() as number).toLocaleString()}` : "—"}
        </span>
      ),
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ getValue }) => <StatusBadge status={getValue() as string} />,
    },
    { accessorKey: "created_at", header: "Raised At", cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDateTime(getValue() as string)}</span> },
    {
      id: "actions",
      header: "",
      cell: ({ row }) =>
        row.original.status === "open" || row.original.status === "investigating" ? (
          <button
            onClick={() => setSelected(row.original)}
            className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-brand-500/10 text-brand-400 hover:bg-brand-500/20 transition-colors"
          >
            <MessageSquare size={12} /> Resolve
          </button>
        ) : null,
    },
  ];

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-white">Disputes</h1>
        <p className="text-sm text-text-muted">{data?.data?.length ?? 0} records</p>
      </div>

      <div className="flex gap-1 bg-surface-200 rounded-lg p-1 w-fit">
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`text-xs px-3 py-1.5 rounded-md capitalize transition-colors ${
              tab === t ? "bg-brand-500 text-white" : "text-text-muted hover:text-white"
            }`}
          >
            {t.replace("_", " ")}
          </button>
        ))}
      </div>

      <DataTable
        columns={columns}
        data={data?.data ?? []}
        loading={isLoading}
        searchColumn="order_id"
        searchPlaceholder="Search order ID…"
      />

      {/* Resolution modal */}
      {selected && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50" onClick={() => setSelected(null)}>
          <div className="card w-full max-w-md p-6 space-y-4" onClick={e => e.stopPropagation()}>
            <h2 className="text-lg font-bold text-white">Resolve Dispute</h2>
            <div className="bg-surface-200 rounded-lg p-3 text-xs text-text-secondary space-y-1">
              <p><span className="text-text-muted">Order:</span> #{selected.order_id.slice(-8).toUpperCase()}</p>
              <p><span className="text-text-muted">Type:</span> {selected.type.replace(/_/g, " ")}</p>
              <p><span className="text-text-muted">Description:</span> {selected.description}</p>
            </div>
            <div>
              <label className="text-xs text-text-muted mb-1 block">Resolution Note</label>
              <textarea
                value={resolution}
                onChange={e => setResolution(e.target.value)}
                rows={3}
                className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-text-muted focus:outline-none focus:border-brand-500 resize-none"
                placeholder="Describe the resolution…"
              />
            </div>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={refund}
                onChange={e => setRefund(e.target.checked)}
                className="rounded"
              />
              <span className="text-sm text-text-secondary">Trigger refund to customer</span>
            </label>
            <div className="flex gap-3">
              <button
                onClick={() => resolveMutation.mutate({ id: selected.$id, body: { resolution_note: resolution, issue_refund: refund, status: "resolved" } })}
                disabled={!resolution || resolveMutation.isPending}
                className="flex-1 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium disabled:opacity-50 transition-colors"
              >
                {resolveMutation.isPending ? "Saving…" : "Resolve"}
              </button>
              <button onClick={() => setSelected(null)} className="flex-1 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-text-secondary text-sm transition-colors">
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
