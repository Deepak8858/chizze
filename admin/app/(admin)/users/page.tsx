"use client";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { usersApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDate, timeAgo } from "@/lib/utils";
import { useState } from "react";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { User } from "@/types";
import { Star, UserX, UserCheck } from "lucide-react";

export default function UsersPage() {
  const [role, setRole] = useState<string>("all");
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["admin-users", role],
    queryFn: () => usersApi.list({ role: role === "all" ? undefined : role, limit: 100 }) as Promise<{ data: User[] }>,
    refetchInterval: 30_000,
  });

  const blockMutation = useMutation({
    mutationFn: ({ id, blocked }: { id: string; blocked: boolean }) =>
      usersApi.update(id, { is_blocked: blocked }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-users"] }); toast.success("User updated"); },
    onError: () => toast.error("Failed to update user"),
  });

  const columns: ColumnDef<User, unknown>[] = [
    {
      accessorKey: "name",
      header: "Name",
      cell: ({ row }) => (
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-full bg-brand-500/20 flex items-center justify-center text-brand-400 text-xs font-bold flex-shrink-0">
            {row.original.name.charAt(0).toUpperCase()}
          </div>
          <div>
            <p className="font-medium text-white">{row.original.name}</p>
            <p className="text-xs text-text-muted">{row.original.phone}</p>
          </div>
        </div>
      ),
    },
    { accessorKey: "email", header: "Email", cell: ({ getValue }) => <span className="text-text-secondary">{getValue() as string || "—"}</span> },
    {
      accessorKey: "role",
      header: "Role",
      cell: ({ getValue }) => <StatusBadge status={getValue() as string} />,
    },
    {
      accessorKey: "is_gold_member",
      header: "Gold",
      cell: ({ getValue }) => getValue() ? <Star size={14} className="text-rating fill-rating" /> : <span className="text-text-muted">—</span>,
    },
    { accessorKey: "created_at", header: "Joined", cell: ({ getValue }) => <span className="text-text-muted text-xs">{formatDate(getValue() as string)}</span> },
    {
      id: "actions",
      header: "Actions",
      cell: ({ row }) => (
        <button
          onClick={() => blockMutation.mutate({ id: row.original.$id, blocked: !row.original.is_blocked })}
          className={`flex items-center gap-1 text-xs font-medium px-2 py-1 rounded transition-colors ${
            row.original.is_blocked
              ? "bg-success/10 text-success hover:bg-success/20"
              : "bg-error/10 text-error hover:bg-error/20"
          }`}
        >
          {row.original.is_blocked ? <><UserCheck size={12} />Unblock</> : <><UserX size={12} />Block</>}
        </button>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Users</h1>
          <p className="text-sm text-text-muted">{data?.data?.length ?? 0} total</p>
        </div>
        <div className="flex gap-2">
          {["all", "customer", "restaurant_owner", "delivery_partner"].map((r) => (
            <button
              key={r}
              onClick={() => setRole(r)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${
                role === r ? "bg-brand-500/20 text-brand-400 border border-brand-500/30" : "bg-bg-elevated text-text-muted border border-white/10 hover:text-white"
              }`}
            >
              {r === "all" ? "All" : r.replace("_", " ").replace(/\b\w/g, (c) => c.toUpperCase())}
            </button>
          ))}
        </div>
      </div>
      <DataTable
        columns={columns}
        data={data?.data ?? []}
        loading={isLoading}
        searchColumn="name"
        searchPlaceholder="Search by name…"
        emptyMessage="No users found."
      />
    </div>
  );
}
