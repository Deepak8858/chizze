"use client";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { deliveryApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDate, formatCurrency } from "@/lib/utils";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { DeliveryPartner } from "@/types";
import { Star, MapPin, IndianRupee } from "lucide-react";

export default function DeliveryPartnersPage() {
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ["admin-riders"],
    queryFn: () => deliveryApi.listPartners({ limit: 200 }) as Promise<{ data: DeliveryPartner[] }>,
    refetchInterval: 30_000,
  });

  const blockMutation = useMutation({
    mutationFn: ({ id, block }: { id: string; block: boolean }) =>
      deliveryApi.updatePartner(id, { is_blocked: block } as Record<string, unknown>),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-riders"] }); toast.success("Updated"); },
    onError: () => toast.error("Failed"),
  });

  const columns: ColumnDef<DeliveryPartner, unknown>[] = [
    {
      accessorKey: "name",
      header: "Partner",
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
      cell: ({ getValue }) => (
        <span className="capitalize text-text-secondary text-xs">{(getValue() as string).replace("_", " ")}</span>
      ),
    },
    {
      accessorKey: "rating",
      header: "Rating",
      cell: ({ getValue }) => (
        <div className="flex items-center gap-1">
          <Star size={12} className="text-rating fill-rating" />
          <span className="text-white text-xs">{(getValue() as number).toFixed(1)}</span>
        </div>
      ),
    },
    {
      accessorKey: "total_deliveries",
      header: "Deliveries",
      cell: ({ getValue }) => <span className="text-white">{getValue() as number}</span>,
    },
    {
      accessorKey: "total_earnings",
      header: "Earnings",
      cell: ({ getValue }) => (
        <div className="flex items-center gap-1 text-status-success text-xs">
          <IndianRupee size={11} />
          {(getValue() as number).toLocaleString()}
        </div>
      ),
    },
    {
      accessorKey: "is_online",
      header: "Online",
      cell: ({ getValue }) => <StatusBadge status={getValue() ? "active" : "inactive"} label={getValue() ? "Online" : "Offline"} />,
    },
    {
      id: "block_action",
      header: "Block",
      cell: ({ row }) => {
        const r = row.original as any;
        return (
          <button
            onClick={() => blockMutation.mutate({ id: row.original.$id, block: !r.is_blocked })}
            className={`text-xs px-2 py-0.5 rounded transition-colors ${
              r.is_blocked
                ? "bg-status-error/20 text-status-error hover:bg-status-error/30"
                : "bg-white/5 text-text-muted hover:bg-status-error/10 hover:text-status-error"
            }`}
          >
            {r.is_blocked ? "Unblock" : "Block"}
          </button>
        );
      },
    },
    { accessorKey: "created_at", header: "Joined", cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDate(getValue() as string)}</span> },
  ];

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-white">Delivery Partners</h1>
        <p className="text-sm text-text-muted">{data?.data?.length ?? 0} total</p>
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
