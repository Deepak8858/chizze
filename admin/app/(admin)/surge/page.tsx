"use client";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { surgeApi, zonesApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDateTime } from "@/lib/utils";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { SurgePricing } from "@/types";
import { Plus, Zap, Trash2 } from "lucide-react";

export default function SurgePage() {
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ zone_id: "", multiplier: 1.5, reason: "high_demand", is_active: true, start_time: "", end_time: "" });
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["admin-surge"],
    queryFn: () => surgeApi.list() as Promise<{ data: SurgePricing[] }>,
  });

  const { data: zones } = useQuery({
    queryKey: ["admin-zones-select"],
    queryFn: () => zonesApi.list() as Promise<{ data: { $id: string; name: string }[] }>,
  });

  const createMutation = useMutation({
    mutationFn: (body: typeof form) => surgeApi.create(body),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-surge"] }); toast.success("Surge pricing added"); setShowForm(false); },
    onError: () => toast.error("Failed"),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => surgeApi.delete(id),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-surge"] }); toast.success("Removed"); },
  });

  const toggleMutation = useMutation({
    mutationFn: ({ id, is_active }: { id: string; is_active: boolean }) => surgeApi.update(id, { is_active }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-surge"] }); toast.success("Updated"); },
  });

  const columns: ColumnDef<SurgePricing, unknown>[] = [
    {
      accessorKey: "zone_name",
      header: "Zone",
      cell: ({ getValue }) => <span className="text-white text-sm">{getValue() as string}</span>,
    },
    {
      accessorKey: "multiplier",
      header: "Multiplier",
      cell: ({ getValue }) => (
        <div className="flex items-center gap-1">
          <Zap size={12} className="text-rating" />
          <span className="text-rating font-bold">{getValue() as number}x</span>
        </div>
      ),
    },
    {
      accessorKey: "reason",
      header: "Reason",
      cell: ({ getValue }) => <span className="text-text-secondary text-xs capitalize">{(getValue() as string).replace(/_/g, " ")}</span>,
    },
    {
      accessorKey: "start_time",
      header: "Active Window",
      cell: ({ row: { original: s } }) => (
        <span className="text-xs text-text-muted">
          {s.start_time ? formatDateTime(s.start_time) : "—"} → {s.end_time ? formatDateTime(s.end_time) : "—"}
        </span>
      ),
    },
    { accessorKey: "is_active", header: "Status", cell: ({ getValue }) => <StatusBadge status={getValue() ? "active" : "inactive"} /> },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <div className="flex items-center gap-2">
          <button onClick={() => toggleMutation.mutate({ id: row.original.$id, is_active: !row.original.is_active })} className="text-xs px-2 py-0.5 rounded bg-white/5 hover:bg-white/10 text-text-muted transition-colors">
            {row.original.is_active ? "Stop" : "Start"}
          </button>
          <button onClick={() => deleteMutation.mutate(row.original.$id)} className="text-status-error/60 hover:text-status-error transition-colors"><Trash2 size={13} /></button>
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Surge Pricing</h1>
          <p className="text-sm text-text-muted">{data?.data?.filter(s => s.is_active).length ?? 0} active surges</p>
        </div>
        <button onClick={() => setShowForm(true)} className="flex items-center gap-2 px-3 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium transition-colors">
          <Plus size={14} /> Add Surge
        </button>
      </div>

      <DataTable columns={columns} data={data?.data ?? []} loading={isLoading} searchColumn="zone_id" searchPlaceholder="Search zone…" />

      {showForm && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50" onClick={() => setShowForm(false)}>
          <div className="card w-full max-w-sm p-6 space-y-4" onClick={e => e.stopPropagation()}>
            <h2 className="text-lg font-bold text-white flex items-center gap-2"><Zap size={16} className="text-rating" /> New Surge</h2>
            <div>
              <label className="text-xs text-text-muted mb-1 block">Zone</label>
              <select value={form.zone_id} onChange={e => setForm(f => ({ ...f, zone_id: e.target.value }))} className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500">
                <option value="">Select zone…</option>
                {zones?.data?.map(z => <option key={z.$id} value={z.$id}>{z.name}</option>)}
              </select>
            </div>
            <div>
              <label className="text-xs text-text-muted mb-1 block">Multiplier</label>
              <input type="number" step="0.1" min="1" max="5" value={form.multiplier} onChange={e => setForm(f => ({ ...f, multiplier: +e.target.value }))} className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500" />
            </div>
            <div>
              <label className="text-xs text-text-muted mb-1 block">Reason</label>
              <select value={form.reason} onChange={e => setForm(f => ({ ...f, reason: e.target.value }))} className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500">
                {["high_demand", "bad_weather", "festival", "peak_hours", "low_riders"].map(r => <option key={r} value={r}>{r.replace(/_/g, " ")}</option>)}
              </select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-text-muted mb-1 block">Start (optional)</label>
                <input type="datetime-local" value={form.start_time} onChange={e => setForm(f => ({ ...f, start_time: e.target.value }))} className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-brand-500" />
              </div>
              <div>
                <label className="text-xs text-text-muted mb-1 block">End (optional)</label>
                <input type="datetime-local" value={form.end_time} onChange={e => setForm(f => ({ ...f, end_time: e.target.value }))} className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-brand-500" />
              </div>
            </div>
            <div className="flex gap-3">
              <button onClick={() => createMutation.mutate(form)} disabled={!form.zone_id} className="flex-1 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium disabled:opacity-50 transition-colors">Create</button>
              <button onClick={() => setShowForm(false)} className="flex-1 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-text-secondary text-sm transition-colors">Cancel</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
