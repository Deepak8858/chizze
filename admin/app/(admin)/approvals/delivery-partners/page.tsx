"use client";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { deliveryApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { formatDate } from "@/lib/utils";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { DeliveryPartner } from "@/types";
import { CheckCircle, XCircle } from "lucide-react";

export default function RiderApprovalsPage() {
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ["rider-approvals"],
    queryFn: () => deliveryApi.getPendingPartners() as Promise<{ data: DeliveryPartner[] }>,
  });

  const approveMutation = useMutation({
    mutationFn: ({ id, approved }: { id: string; approved: boolean }) =>
      deliveryApi.approvePartner(id, approved),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["rider-approvals"] }); toast.success("Action completed"); },
    onError: () => toast.error("Failed"),
  });

  const columns: ColumnDef<DeliveryPartner, unknown>[] = [
    {
      accessorKey: "name",
      header: "Rider",
      cell: ({ row: { original: r } }) => (
        <div>
          <p className="font-medium text-white">{r.name}</p>
          <p className="text-xs text-text-muted">{r.phone}</p>
        </div>
      ),
    },
    {
      accessorKey: "vehicle_type",
      header: "Vehicle",
      cell: ({ getValue }) => <span className="capitalize text-text-secondary text-xs">{(getValue() as string).replace("_", " ")}</span>,
    },
    {
      accessorKey: "vehicle_number",
      header: "Reg. No",
      cell: ({ getValue }) => <span className="font-mono text-xs text-text-secondary">{getValue() as string ?? "—"}</span>,
    },
    {
      accessorKey: "license_number",
      header: "License",
      cell: ({ getValue }) => <span className="font-mono text-xs text-text-secondary">{getValue() as string ?? "—"}</span>,
    },
    { accessorKey: "created_at", header: "Applied", cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDate(getValue() as string)}</span> },
    {
      id: "actions",
      header: "Actions",
      cell: ({ row }) => (
        <div className="flex items-center gap-2">
          <button
            onClick={() => approveMutation.mutate({ id: row.original.$id, approved: true })}
            className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-status-success/10 text-status-success hover:bg-status-success/20 transition-colors"
          >
            <CheckCircle size={12} /> Approve
          </button>
          <button
            onClick={() => approveMutation.mutate({ id: row.original.$id, approved: false })}
            className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-status-error/10 text-status-error hover:bg-status-error/20 transition-colors"
          >
            <XCircle size={12} /> Reject
          </button>
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-white">Rider Approvals</h1>
        <p className="text-sm text-text-muted">{data?.data?.length ?? 0} pending</p>
      </div>
      <DataTable
        columns={columns}
        data={data?.data ?? []}
        loading={isLoading}
        searchColumn="name"
        searchPlaceholder="Search rider…"
      />
    </div>
  );
}
