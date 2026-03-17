"use client";
import { useQuery } from "@tanstack/react-query";
import { goldApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDate, formatCurrency } from "@/lib/utils";
import type { ColumnDef } from "@tanstack/react-table";
import type { GoldSubscription } from "@/types";
import { Crown } from "lucide-react";

export default function GoldPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["admin-gold"],
    queryFn: () => goldApi.list({ limit: 200 }) as Promise<{ data: GoldSubscription[] }>,
  });

  const { data: stats } = useQuery({
    queryKey: ["gold-stats"],
    queryFn: () => goldApi.getStats() as Promise<{ data: { active: number; total_revenue: number; monthly: number; yearly: number } }>,
  });

  const columns: ColumnDef<GoldSubscription, unknown>[] = [
    { accessorKey: "user_id", header: "User", cell: ({ getValue }) => <span className="font-mono text-xs text-brand-400">{(getValue() as string).slice(-10)}</span> },
    {
      accessorKey: "plan",
      header: "Plan",
      cell: ({ getValue }) => (
        <div className="flex items-center gap-1">
          <Crown size={12} className="text-rating" />
          <span className="text-white text-xs capitalize">{getValue() as string}</span>
        </div>
      ),
    },
    { accessorKey: "amount_paid", header: "Amount", cell: ({ getValue }) => <span className="text-white font-medium">{formatCurrency(getValue() as number)}</span> },
    { accessorKey: "started_at", header: "Started", cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDate(getValue() as string)}</span> },
    { accessorKey: "expires_at", header: "Expires", cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDate(getValue() as string)}</span> },
    { accessorKey: "is_active", header: "Status", cell: ({ getValue }) => <StatusBadge status={getValue() ? "active" : "expired"} /> },
    {
      accessorKey: "auto_renew",
      header: "Auto-Renew",
      cell: ({ getValue }) => <span className={`text-xs ${getValue() ? "text-status-success" : "text-text-muted"}`}>{getValue() ? "On" : "Off"}</span>,
    },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white flex items-center gap-2">
          <Crown size={20} className="text-rating" /> Gold Subscriptions
        </h1>
        <p className="text-sm text-text-muted">Chizze Gold member management</p>
      </div>

      <div className="grid grid-cols-4 gap-4">
        {[
          { label: "Active Members", value: stats?.data?.active ?? 0, accent: "text-status-success" },
          { label: "Total Revenue", value: formatCurrency(stats?.data?.total_revenue ?? 0), accent: "text-white" },
          { label: "Monthly Plans", value: stats?.data?.monthly ?? 0, accent: "text-brand-400" },
          { label: "Yearly Plans", value: stats?.data?.yearly ?? 0, accent: "text-rating" },
        ].map(({ label, value, accent }) => (
          <div key={label} className="card p-4">
            <p className="text-xs text-text-muted mb-1">{label}</p>
            <p className={`text-xl font-bold ${accent}`}>{value}</p>
          </div>
        ))}
      </div>

      <DataTable columns={columns} data={data?.data ?? []} loading={isLoading} searchColumn="user_id" searchPlaceholder="Search user ID…" />
    </div>
  );
}
