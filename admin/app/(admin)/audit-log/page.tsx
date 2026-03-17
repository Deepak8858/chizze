"use client";
import { useQuery } from "@tanstack/react-query";
import { auditApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { formatDateTime } from "@/lib/utils";
import type { ColumnDef } from "@tanstack/react-table";
import type { AuditLog } from "@/types";
import { ShieldCheck } from "lucide-react";

export default function AuditLogPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["audit-log"],
    queryFn: () => auditApi.list({ limit: 500 }) as Promise<{ data: AuditLog[] }>,
  });

  const columns: ColumnDef<AuditLog, unknown>[] = [
    {
      accessorKey: "admin_id",
      header: "Admin",
      cell: ({ getValue }) => <span className="font-mono text-xs text-brand-400">{(getValue() as string).slice(-8)}</span>,
    },
    {
      accessorKey: "action",
      header: "Action",
      cell: ({ getValue }) => (
        <span className="text-xs px-2 py-0.5 rounded bg-brand-500/10 text-brand-400 font-mono">{getValue() as string}</span>
      ),
    },
    {
      accessorKey: "resource_type",
      header: "Resource",
      cell: ({ row: { original: l } }) => (
        <div>
          <span className="text-white text-xs capitalize">{l.resource_type}</span>
          <span className="text-text-muted text-xs ml-1">#{l.resource_id.slice(-6)}</span>
        </div>
      ),
    },
    {
      accessorKey: "description",
      header: "Description",
      cell: ({ getValue }) => <span className="text-text-secondary text-xs">{getValue() as string}</span>,
    },
    {
      accessorKey: "ip_address",
      header: "IP",
      cell: ({ getValue }) => <span className="font-mono text-xs text-text-muted">{getValue() as string}</span>,
    },
    {
      accessorKey: "created_at",
      header: "Time",
      cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDateTime(getValue() as string)}</span>,
    },
  ];

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-white flex items-center gap-2">
          <ShieldCheck size={22} className="text-brand-400" /> Audit Log
        </h1>
        <p className="text-sm text-text-muted">All admin actions are recorded here</p>
      </div>
      <DataTable
        columns={columns}
        data={data?.data ?? []}
        loading={isLoading}
        searchColumn="action"
        searchPlaceholder="Search action…"
      />
    </div>
  );
}
