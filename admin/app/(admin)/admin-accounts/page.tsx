"use client";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { adminsApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDate } from "@/lib/utils";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { Admin } from "@/types";
import { Plus, Shield, Trash2 } from "lucide-react";
import { getUser } from "@/lib/auth";

const ROLES = ["super_admin", "finance", "operations", "support", "read_only"];

export default function AdminAccountsPage() {
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ name: "", email: "", phone: "", permission: "support" });
  const qc = useQueryClient();
  const me = getUser();

  const { data, isLoading } = useQuery({
    queryKey: ["admin-accounts"],
    queryFn: () => adminsApi.list() as Promise<{ data: Admin[] }>,
  });

  const createMutation = useMutation({
    mutationFn: (body: typeof form) => adminsApi.create(body),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-accounts"] }); toast.success("Admin created"); setShowForm(false); },
    onError: () => toast.error("Failed"),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => adminsApi.delete(id),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-accounts"] }); toast.success("Admin removed"); },
    onError: () => toast.error("Cannot delete self or last super admin"),
  });

  const ROLE_COLORS: Record<string, string> = {
    super_admin: "text-brand-400 bg-brand-500/10",
    finance: "text-status-info bg-status-info/10",
    operations: "text-status-warning bg-status-warning/10",
    support: "text-status-success bg-status-success/10",
    read_only: "text-text-muted bg-white/5",
  };

  const columns: ColumnDef<Admin, unknown>[] = [
    {
      accessorKey: "name",
      header: "Admin",
      cell: ({ row: { original: a } }) => (
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-full bg-brand-500/20 flex items-center justify-center text-brand-400 text-xs font-bold">
            {a.name.charAt(0).toUpperCase()}
          </div>
          <div>
            <p className="text-white font-medium text-sm">{a.name}</p>
            <p className="text-text-muted text-xs">{a.email}</p>
          </div>
        </div>
      ),
    },
    {
      accessorKey: "permission",
      header: "Permission",
      cell: ({ getValue }) => (
        <span className={`text-xs px-2 py-0.5 rounded capitalize font-medium ${ROLE_COLORS[(getValue() as string)] ?? "text-text-muted bg-white/5"}`}>
          {(getValue() as string).replace("_", " ")}
        </span>
      ),
    },
    { accessorKey: "phone", header: "Phone", cell: ({ getValue }) => <span className="text-text-secondary text-xs">{getValue() as string ?? "—"}</span> },
    { accessorKey: "is_active", header: "Status", cell: ({ getValue }) => <StatusBadge status={getValue() ? "active" : "inactive"} /> },
    { accessorKey: "last_login", header: "Last Login", cell: ({ getValue }) => <span className="text-xs text-text-muted">{getValue() ? formatDate(getValue() as string) : "Never"}</span> },
    {
      id: "actions",
      header: "",
      cell: ({ row }) =>
        (row.original as any).$id !== (me as any)?.$id ? (
          <button onClick={() => deleteMutation.mutate(row.original.$id)} className="text-status-error/50 hover:text-status-error transition-colors">
            <Trash2 size={14} />
          </button>
        ) : <span className="text-xs text-text-muted italic">You</span>,
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <Shield size={20} className="text-brand-400" /> Admin Accounts
          </h1>
          <p className="text-sm text-text-muted">{data?.data?.length ?? 0} admins</p>
        </div>
        <button onClick={() => setShowForm(true)} className="flex items-center gap-2 px-3 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium transition-colors">
          <Plus size={14} /> Add Admin
        </button>
      </div>

      <DataTable columns={columns} data={data?.data ?? []} loading={isLoading} searchColumn="name" searchPlaceholder="Search admin…" />

      {showForm && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50" onClick={() => setShowForm(false)}>
          <div className="card w-full max-w-sm p-6 space-y-4" onClick={e => e.stopPropagation()}>
            <h2 className="text-lg font-bold text-white">New Admin</h2>
            {[
              { label: "Full Name", key: "name" },
              { label: "Email", key: "email" },
              { label: "Phone", key: "phone" },
            ].map(({ label, key }) => (
              <div key={key}>
                <label className="text-xs text-text-muted mb-1 block">{label}</label>
                <input
                  value={(form as any)[key]}
                  onChange={e => setForm(f => ({ ...f, [key]: e.target.value }))}
                  className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
                />
              </div>
            ))}
            <div>
              <label className="text-xs text-text-muted mb-1 block">Permission</label>
              <select value={form.permission} onChange={e => setForm(f => ({ ...f, permission: e.target.value }))} className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500">
                {ROLES.map(r => <option key={r} value={r}>{r.replace("_", " ")}</option>)}
              </select>
            </div>
            <div className="flex gap-3">
              <button onClick={() => createMutation.mutate(form)} disabled={!form.name || !form.email} className="flex-1 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium disabled:opacity-50 transition-colors">Create</button>
              <button onClick={() => setShowForm(false)} className="flex-1 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-text-secondary text-sm transition-colors">Cancel</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
