"use client";
import { useQuery } from "@tanstack/react-query";
import { ordersApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDateTime, formatCurrency } from "@/lib/utils";
import type { ColumnDef } from "@tanstack/react-table";
import type { Order } from "@/types";
import Link from "next/link";
import { ExternalLink } from "lucide-react";

export default function OrdersPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["admin-orders"],
    queryFn: () => ordersApi.list({ limit: 200 }) as Promise<{ data: Order[] }>,
    refetchInterval: 30_000,
  });

  const columns: ColumnDef<Order, unknown>[] = [
    {
      accessorKey: "$id",
      header: "Order ID",
      cell: ({ getValue }) => (
        <Link href={`/orders/${getValue()}`} className="text-brand-400 hover:underline font-mono text-xs flex items-center gap-1">
          #{(getValue() as string).slice(-8).toUpperCase()} <ExternalLink size={11} />
        </Link>
      ),
    },
    {
      accessorKey: "customer_id",
      header: "Customer",
      cell: ({ getValue }) => <span className="text-text-secondary text-xs font-mono">{(getValue() as string).slice(-10)}</span>,
    },
    {
      accessorKey: "restaurant_name",
      header: "Restaurant",
      cell: ({ getValue }) => <span className="text-white text-xs">{getValue() as string}</span>,
    },
    {
      accessorKey: "grand_total",
      header: "Total",
      cell: ({ getValue }) => <span className="font-semibold text-white">{formatCurrency(getValue() as number)}</span>,
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ getValue }) => <StatusBadge status={getValue() as string} />,
    },
    {
      accessorKey: "payment_method",
      header: "Payment",
      cell: ({ getValue }) => (
        <span className="text-xs px-2 py-0.5 rounded bg-white/5 text-text-secondary capitalize">
          {(getValue() as string).replace("_", " ")}
        </span>
      ),
    },
    {
      accessorKey: "placed_at",
      header: "Placed At",
      cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDateTime(getValue() as string)}</span>,
    },
  ];

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-white">Orders</h1>
        <p className="text-sm text-text-muted">{data?.data?.length ?? 0} total</p>
      </div>
      <DataTable
        columns={columns}
        data={data?.data ?? []}
        loading={isLoading}
        searchColumn="$id"
        searchPlaceholder="Search order ID…"
      />
    </div>
  );
}
