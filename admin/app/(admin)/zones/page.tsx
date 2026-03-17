"use client";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { zonesApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { Zone } from "@/types";
import { Plus, MapPin, Trash2 } from "lucide-react";

export default function ZonesPage() {
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ name: "", city: "", is_active: true, delivery_fee_override: 0, polygon: "" });
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["admin-zones"],
    queryFn: () => zonesApi.list() as Promise<{ data: Zone[] }>,
  });

  const createMutation = useMutation({
    mutationFn: (body: typeof form) => zonesApi.create({ name: body.name, city: body.city, is_active: body.is_active, delivery_fee_override: (body as any).delivery_fee_override, geojson: body.polygon ? JSON.stringify({ type: "Polygon", coordinates: [JSON.parse(body.polygon)] }) : "" } as Record<string, unknown>),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-zones"] }); toast.success("Zone created"); setShowForm(false); },
    onError: () => toast.error("Failed"),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => zonesApi.delete(id),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-zones"] }); toast.success("Deleted"); },
  });

  const toggleMutation = useMutation({
    mutationFn: ({ id, is_active }: { id: string; is_active: boolean }) => zonesApi.update(id, { is_active }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-zones"] }); toast.success("Updated"); },
  });

  const columns: ColumnDef<Zone, unknown>[] = [
    {
      accessorKey: "name",
      header: "Zone",
      cell: ({ row: { original: z } }) => (
        <div className="flex items-center gap-2">
          <MapPin size={13} className="text-brand-400" />
          <div>
            <p className="text-white font-medium text-sm">{z.name}</p>
            <p className="text-text-muted text-xs">{z.city}</p>
          </div>
        </div>
      ),
    },
    { accessorKey: "delivery_fee_override", header: "Fee Override", cell: ({ getValue }) => <span className="text-white text-xs">{getValue() ? `₹${getValue()}` : "—"}</span> },
    { accessorKey: "is_active", header: "Status", cell: ({ getValue }) => <StatusBadge status={getValue() ? "active" : "inactive"} /> },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <div className="flex items-center gap-2">
          <button
            onClick={() => toggleMutation.mutate({ id: row.original.$id, is_active: !row.original.is_active })}
            className="text-xs px-2 py-0.5 rounded bg-white/5 hover:bg-white/10 text-text-muted transition-colors"
          >
            {row.original.is_active ? "Deactivate" : "Activate"}
          </button>
          <button onClick={() => deleteMutation.mutate(row.original.$id)} className="text-status-error/60 hover:text-status-error transition-colors">
            <Trash2 size={13} />
          </button>
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Zones</h1>
          <p className="text-sm text-text-muted">{data?.data?.length ?? 0} delivery zones</p>
        </div>
        <button onClick={() => setShowForm(true)} className="flex items-center gap-2 px-3 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium transition-colors">
          <Plus size={14} /> Add Zone
        </button>
      </div>

      <DataTable columns={columns} data={data?.data ?? []} loading={isLoading} searchColumn="name" searchPlaceholder="Search zone…" />

      {showForm && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50" onClick={() => setShowForm(false)}>
          <div className="card w-full max-w-md p-6 space-y-4" onClick={e => e.stopPropagation()}>
            <h2 className="text-lg font-bold text-white">New Delivery Zone</h2>
            {[
              { label: "Name", key: "name", type: "text" },
              { label: "City", key: "city", type: "text" },
            { label: "Delivery Fee Override (₹, optional)", key: "delivery_fee_override", type: "number" },
            ].map(({ label, key, type }) => (
              <div key={key}>
                <label className="text-xs text-text-muted mb-1 block">{label}</label>
                <input
                  type={type}
                  value={(form as any)[key]}
                  onChange={e => setForm(f => ({ ...f, [key]: type === "number" ? +e.target.value : e.target.value }))}
                  className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
                />
              </div>
            ))}
            <div>
              <label className="text-xs text-text-muted mb-1 block">Polygon (GeoJSON array, optional)</label>
              <textarea
                value={form.polygon}
                onChange={e => setForm(f => ({ ...f, polygon: e.target.value }))}
                rows={2}
                placeholder='[[lng, lat], ...]'
                className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-xs text-white font-mono focus:outline-none focus:border-brand-500 resize-none"
              />
            </div>
            <div className="flex gap-3">
              <button onClick={() => createMutation.mutate(form)} disabled={!form.name || !form.city} className="flex-1 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium disabled:opacity-50 transition-colors">Create</button>
              <button onClick={() => setShowForm(false)} className="flex-1 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-text-secondary text-sm transition-colors">Cancel</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
