"use client";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { couponsApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDate, formatCurrency } from "@/lib/utils";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { Coupon } from "@/types";
import { Plus, Trash2, Tag } from "lucide-react";

type CouponFormData = { code: string; discount_type: string; discount_value: number; min_order_value: number; max_discount: number; usage_limit: number; valid_until: string; is_active: boolean; };
function CouponForm({ onClose, onSave }: { onClose: () => void; onSave: (body: CouponFormData) => void }) {
  const [form, setForm] = useState<CouponFormData>({
    code: "", discount_type: "percentage", discount_value: 10, min_order_value: 0, max_discount: 0, usage_limit: 0, valid_until: "", is_active: true,
  });
  const set = (k: string, v: unknown) => setForm(f => ({ ...f, [k]: v }));
  return (
    <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50" onClick={onClose}>
      <div className="card w-full max-w-md p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h2 className="text-lg font-bold text-white flex items-center gap-2"><Tag size={16} className="text-brand-400" /> New Coupon</h2>
        {[
          { label: "Code", key: "code", type: "text" },
          { label: "Discount Value", key: "discount_value", type: "number" },
          { label: "Min Order (₹)", key: "min_order_value", type: "number" },
          { label: "Max Discount (₹)", key: "max_discount", type: "number" },
          { label: "Usage Limit", key: "usage_limit", type: "number" },
          { label: "Valid Until", key: "valid_until", type: "date" },
        ].map(({ label, key, type }) => (
          <div key={key}>
            <label className="text-xs text-text-muted mb-1 block">{label}</label>
            <input
              type={type}
              value={(form as any)[key] as string | number}
              onChange={e => set(key, type === "number" ? +e.target.value : e.target.value)}
              className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
            />
          </div>
        ))}
        <div>
          <label className="text-xs text-text-muted mb-1 block">Discount Type</label>
          <select
            value={form.discount_type}
            onChange={e => set("discount_type", e.target.value)}
            className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
          >
            <option value="percentage">Percentage</option>
            <option value="flat">Flat</option>
            <option value="free_delivery">Free Delivery</option>
          </select>
        </div>
        <div className="flex gap-3">
          <button onClick={() => onSave(form)} className="flex-1 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium transition-colors">Create</button>
          <button onClick={onClose} className="flex-1 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-text-secondary text-sm transition-colors">Cancel</button>
        </div>
      </div>
    </div>
  );
}

export default function CouponsPage() {
  const [showForm, setShowForm] = useState(false);
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["admin-coupons"],
    queryFn: () => couponsApi.list({ limit: 200 }) as Promise<{ data: Coupon[] }>,
  });

  const createMutation = useMutation({
    mutationFn: (body: Record<string, unknown>) => couponsApi.create(body),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-coupons"] }); toast.success("Coupon created"); setShowForm(false); },
    onError: () => toast.error("Failed"),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => couponsApi.delete(id),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-coupons"] }); toast.success("Deleted"); },
  });

  const columns: ColumnDef<Coupon, unknown>[] = [
    { accessorKey: "code", header: "Code", cell: ({ getValue }) => <span className="font-mono text-brand-400 font-bold uppercase">{getValue() as string}</span> },
    {
      accessorKey: "discount_type",
      header: "Type",
      cell: ({ row: { original: c } }) => (
        <span className="text-xs text-text-secondary capitalize">
          {c.discount_type === "percentage" ? `${c.discount_value}%` : c.discount_type === "flat" ? `₹${c.discount_value}` : "Free Delivery"}
        </span>
      ),
    },
    { accessorKey: "min_order_value", header: "Min Order", cell: ({ getValue }) => <span className="text-text-secondary text-xs">{formatCurrency(getValue() as number)}</span> },
    { accessorKey: "used_count", header: "Used", cell: ({ row: { original: c } }) => <span className="text-white text-xs">{(c as any).used_count ?? 0} / {c.usage_limit ?? "∞"}</span> },
    { accessorKey: "valid_until", header: "Expires", cell: ({ getValue }) => <span className="text-xs text-text-muted">{getValue() ? formatDate(getValue() as string) : "—"}</span> },
    { accessorKey: "is_active", header: "Status", cell: ({ getValue }) => <StatusBadge status={getValue() ? "active" : "inactive"} /> },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <button
          onClick={() => deleteMutation.mutate(row.original.$id)}
          className="text-status-error/60 hover:text-status-error transition-colors"
        >
          <Trash2 size={14} />
        </button>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Coupons</h1>
          <p className="text-sm text-text-muted">{data?.data?.length ?? 0} total</p>
        </div>
        <button onClick={() => setShowForm(true)} className="flex items-center gap-2 px-3 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium transition-colors">
          <Plus size={14} /> New Coupon
        </button>
      </div>
      <DataTable columns={columns} data={data?.data ?? []} loading={isLoading} searchColumn="code" searchPlaceholder="Search code…" />
      {showForm && <CouponForm onClose={() => setShowForm(false)} onSave={body => createMutation.mutate(body as unknown as Record<string, unknown>)} />}
    </div>
  );
}
