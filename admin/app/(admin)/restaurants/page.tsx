"use client";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { restaurantsApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDate, formatCurrency } from "@/lib/utils";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { Restaurant } from "@/types";
import { Star, CheckCircle, XCircle, Sparkles } from "lucide-react";

export default function RestaurantsPage() {
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["admin-restaurants"],
    queryFn: () => restaurantsApi.list({ limit: 200 }) as Promise<{ data: Restaurant[] }>,
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, body }: { id: string; body: Record<string, unknown> }) =>
      restaurantsApi.update(id, body),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-restaurants"] }); toast.success("Restaurant updated"); },
    onError: () => toast.error("Failed to update"),
  });

  const columns: ColumnDef<Restaurant, unknown>[] = [
    {
      accessorKey: "name",
      header: "Restaurant",
      cell: ({ row: { original: r } }) => (
        <div className="flex items-center gap-2">
          {r.logo_url ? (
            <img src={r.logo_url} className="w-7 h-7 rounded-lg object-cover" alt={r.name} />
          ) : (
            <div className="w-7 h-7 rounded-lg bg-brand-500/20 flex items-center justify-center text-brand-400 text-xs font-bold">
              {r.name.charAt(0)}
            </div>
          )}
          <div>
            <p className="font-medium text-white">{r.name}</p>
            <p className="text-xs text-text-muted">{r.city}</p>
          </div>
        </div>
      ),
    },
    { accessorKey: "cuisines", header: "Cuisines", cell: ({ getValue }) => <span className="text-text-secondary text-xs">{(getValue() as string[]).slice(0, 2).join(", ")}</span> },
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
      accessorKey: "is_online",
      header: "Status",
      cell: ({ getValue }) => <StatusBadge status={getValue() ? "active" : "inactive"} />,
    },
    {
      accessorKey: "is_featured",
      header: "Featured",
      cell: ({ row }) => (
        <button
          onClick={() => updateMutation.mutate({ id: row.original.$id, body: { is_featured: !row.original.is_featured } })}
          className={`flex items-center gap-1 text-xs px-2 py-0.5 rounded transition-colors ${row.original.is_featured ? "text-rating bg-rating/10" : "text-text-muted bg-white/5 hover:text-rating"}`}
        >
          <Sparkles size={11} /> {row.original.is_featured ? "Featured" : "Feature"}
        </button>
      ),
    },
    { accessorKey: "avg_delivery_time_min", header: "Avg Delivery", cell: ({ getValue }) => <span className="text-text-secondary">{getValue() as number} min</span> },
    { accessorKey: "created_at", header: "Since", cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDate(getValue() as string)}</span> },
  ];

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-white">Restaurants</h1>
        <p className="text-sm text-text-muted">{data?.data?.length ?? 0} total</p>
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
