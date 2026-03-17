"use client";
import { useQuery } from "@tanstack/react-query";
import { referralsApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDate, formatCurrency } from "@/lib/utils";
import type { ColumnDef } from "@tanstack/react-table";
import type { Referral } from "@/types";
import { Users2 } from "lucide-react";

export default function ReferralsPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["admin-referrals"],
    queryFn: () => referralsApi.list({ limit: 200 }) as Promise<{ data: Referral[] }>,
  });

  const { data: stats } = useQuery({
    queryKey: ["referral-stats"],
    queryFn: () => referralsApi.getStats() as Promise<{ data: { total: number; completed: number; total_rewarded: number } }>,
  });

  const columns: ColumnDef<Referral, unknown>[] = [
    { accessorKey: "referrer_id", header: "Referrer", cell: ({ getValue }) => <span className="font-mono text-xs text-brand-400">{(getValue() as string).slice(-10)}</span> },
    { accessorKey: "referred_id", header: "Referred", cell: ({ getValue }) => <span className="font-mono text-xs text-text-secondary">{(getValue() as string).slice(-10)}</span> },
    { accessorKey: "code", header: "Code", cell: ({ getValue }) => <span className="font-mono text-xs text-white uppercase">{getValue() as string}</span> },
    { accessorKey: "reward_amount", header: "Reward", cell: ({ getValue }) => <span className="text-status-success text-xs">{formatCurrency(getValue() as number)}</span> },
    { accessorKey: "status", header: "Status", cell: ({ getValue }) => <StatusBadge status={getValue() as string} /> },
    { accessorKey: "completed_at", header: "Completed", cell: ({ getValue }) => <span className="text-xs text-text-muted">{getValue() ? formatDate(getValue() as string) : "—"}</span> },
    { accessorKey: "created_at", header: "Created", cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDate(getValue() as string)}</span> },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white flex items-center gap-2">
          <Users2 size={20} className="text-brand-400" /> Referrals
        </h1>
        <p className="text-sm text-text-muted">Referral program overview</p>
      </div>

      <div className="grid grid-cols-3 gap-4">
        <div className="card p-4">
          <p className="text-xs text-text-muted mb-1">Total Referrals</p>
          <p className="text-xl font-bold text-white">{stats?.data?.total ?? 0}</p>
        </div>
        <div className="card p-4">
          <p className="text-xs text-text-muted mb-1">Completed</p>
          <p className="text-xl font-bold text-status-success">{stats?.data?.completed ?? 0}</p>
        </div>
        <div className="card p-4">
          <p className="text-xs text-text-muted mb-1">Total Rewarded</p>
          <p className="text-xl font-bold text-brand-400">{formatCurrency(stats?.data?.total_rewarded ?? 0)}</p>
        </div>
      </div>

      <DataTable columns={columns} data={data?.data ?? []} loading={isLoading} searchColumn="code" searchPlaceholder="Search referral code…" />
    </div>
  );
}
