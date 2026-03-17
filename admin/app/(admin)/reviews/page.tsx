"use client";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { reviewsApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDateTime } from "@/lib/utils";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { Review } from "@/types";
import { Star, CheckCircle, Flag } from "lucide-react";

export default function ReviewsPage() {
  const [tab, setTab] = useState("all");
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["admin-reviews", tab],
    queryFn: () => reviewsApi.list({ status: tab === "all" ? undefined : tab, limit: 200 }) as Promise<{ data: Review[] }>,
  });

  const moderateMutation = useMutation({
    mutationFn: ({ id, action }: { id: string; action: "approve" | "reject" }) => reviewsApi.moderate(id, action),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-reviews"] }); toast.success("Review moderated"); },
    onError: () => toast.error("Failed"),
  });

  const columns: ColumnDef<Review, unknown>[] = [
    {
      accessorKey: "restaurant_name",
      header: "Restaurant",
      cell: ({ row }) => <span className="text-white text-xs">{row.original.restaurant_name ?? row.original.restaurant_id.slice(-8)}</span>,
    },
    {
      accessorKey: "customer_name",
      header: "User",
      cell: ({ row }) => <span className="text-text-secondary text-xs">{row.original.customer_name ?? row.original.customer_id.slice(-8)}</span>,
    },
    {
      accessorKey: "food_rating",
      header: "Rating",
      cell: ({ getValue }) => (
        <div className="flex items-center gap-0.5">
          {[...Array(5)].map((_, i) => (
            <Star key={i} size={11} className={i < (getValue() as number) ? "text-rating fill-rating" : "text-white/20"} />
          ))}
        </div>
      ),
    },
    {
      accessorKey: "review_text",
      header: "Review",
      cell: ({ getValue }) => <span className="text-text-secondary text-xs line-clamp-2 max-w-64">{getValue() as string}</span>,
    },
    {
      accessorKey: "is_visible",
      header: "Visible",
      cell: ({ getValue }) => <StatusBadge status={getValue() ? "active" : "inactive"} label={getValue() ? "Visible" : "Hidden"} />,
    },
    { accessorKey: "created_at", header: "Date", cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDateTime(getValue() as string)}</span> },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => {
        const r = row.original as any;
        return (
          <div className="flex items-center gap-1">
            <button
              onClick={() => moderateMutation.mutate({ id: r.$id, action: "approve" })}
              className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-status-success/10 text-status-success hover:bg-status-success/20"
            >
              <CheckCircle size={11} /> Show
            </button>
            <button
              onClick={() => moderateMutation.mutate({ id: r.$id, action: "reject" })}
              className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-status-error/10 text-status-error hover:bg-status-error/20"
            >
              <Flag size={11} /> Hide
            </button>
          </div>
        );
      },
    },
  ];

  const TABS = ["all", "pending", "approved", "rejected", "flagged"];

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-white">Reviews</h1>
        <p className="text-sm text-text-muted">{data?.data?.length ?? 0} records</p>
      </div>
      <div className="flex gap-1 bg-surface-200 rounded-lg p-1 w-fit">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className={`text-xs px-3 py-1.5 rounded-md capitalize transition-colors ${tab === t ? "bg-brand-500 text-white" : "text-text-muted hover:text-white"}`}>{t}</button>
        ))}
      </div>
      <DataTable columns={columns} data={data?.data ?? []} loading={isLoading} searchColumn="review_text" searchPlaceholder="Search review…" />
    </div>
  );
}
