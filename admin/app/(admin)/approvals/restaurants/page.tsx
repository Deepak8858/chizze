"use client";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { restaurantsApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDate } from "@/lib/utils";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { Restaurant } from "@/types";
import { CheckCircle, XCircle, MapPin } from "lucide-react";

export default function RestaurantApprovalsPage() {
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ["restaurant-approvals"],
    queryFn: () => restaurantsApi.getPending() as Promise<{ data: Restaurant[] }>,
  });

  const approveMutation = useMutation({
    mutationFn: ({ id, approved }: { id: string; approved: boolean }) =>
      restaurantsApi.approve(id, approved),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["restaurant-approvals"] }); toast.success("Action completed"); },
    onError: () => toast.error("Failed"),
  });

  const columns: ColumnDef<Restaurant, unknown>[] = [
    {
      accessorKey: "name",
      header: "Restaurant",
      cell: ({ row: { original: r } }) => (
        <div>
          <p className="font-medium text-white">{r.name}</p>
          <p className="text-xs text-text-muted">{(r as any).email ?? r.owner_id?.slice(-8)}</p>
        </div>
      ),
    },
    {
      accessorKey: "owner_id",
      header: "Owner ID",
      cell: ({ getValue }) => <span className="text-text-secondary text-xs font-mono">{(getValue() as string).slice(-8)}</span>,
    },
    { accessorKey: "cuisines", header: "Cuisines", cell: ({ getValue }) => <span className="text-text-secondary text-xs">{(getValue() as string[]).join(", ")}</span> },
    {
      accessorKey: "city",
      header: "Location",
      cell: ({ row: { original: r } }) => (
        <div className="flex items-center gap-1 text-xs text-text-muted">
          <MapPin size={11} /> {r.city}
        </div>
      ),
    },
    {
      accessorKey: "is_approved",
      header: "Approved",
      cell: ({ getValue }) => <StatusBadge status={getValue() ? "active" : "pending"} label={getValue() ? "Approved" : "Pending"} />,
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
        <h1 className="text-2xl font-bold text-white">Restaurant Approvals</h1>
        <p className="text-sm text-text-muted">{data?.data?.length ?? 0} pending</p>
      </div>
      <DataTable
        columns={columns}
        data={data?.data ?? []}
        loading={isLoading}
        searchColumn="name"
        searchPlaceholder="Search restaurant…"
      />
    </div>
  );
}
