"use client";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supportApi } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { formatDateTime } from "@/lib/utils";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import type { SupportTicket } from "@/types";
import { MessageSquare, Send } from "lucide-react";

export default function SupportPage() {
  const [selected, setSelected] = useState<SupportTicket | null>(null);
  const [reply, setReply] = useState("");
  const [tab, setTab] = useState("open");
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["admin-support", tab],
    queryFn: () => supportApi.list({ status: tab === "all" ? undefined : tab, limit: 200 }) as Promise<{ data: SupportTicket[] }>,
  });

  const { data: messages, isLoading: msgLoading } = useQuery({
    queryKey: ["support-messages", selected?.$id],
    queryFn: () => supportApi.getMessages(selected!.$id) as Promise<{ data: { sender: string; message: string; created_at: string }[] }>,
    enabled: !!selected,
  });

  const replyMutation = useMutation({
    mutationFn: ({ id, message }: { id: string; message: string }) => supportApi.reply(id, message),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["support-messages", selected?.$id] }); setReply(""); toast.success("Reply sent"); },
    onError: () => toast.error("Failed"),
  });

  const closeMutation = useMutation({
    mutationFn: (id: string) => supportApi.close(id),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-support"] }); setSelected(null); toast.success("Ticket closed"); },
  });

  const TABS = ["all", "open", "investigating", "resolved"];

  const columns: ColumnDef<SupportTicket, unknown>[] = [
    { accessorKey: "description", header: "Description", cell: ({ getValue }) => <span className="text-white text-sm font-medium line-clamp-2 max-w-48">{getValue() as string}</span> },
    { accessorKey: "category", header: "Category", cell: ({ getValue }) => <span className="text-text-secondary text-xs capitalize">{(getValue() as string).replace(/_/g, " ")}</span> },
    { accessorKey: "reporter_id", header: "Reporter", cell: ({ getValue }) => <span className="font-mono text-xs text-text-muted">{(getValue() as string).slice(-8)}</span> },
    { accessorKey: "status", header: "Status", cell: ({ getValue }) => <StatusBadge status={getValue() as string} /> },
    { accessorKey: "created_at", header: "Created", cell: ({ getValue }) => <span className="text-xs text-text-muted">{formatDateTime(getValue() as string)}</span> },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <button onClick={() => setSelected(row.original)} className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-brand-500/10 text-brand-400 hover:bg-brand-500/20 transition-colors">
          <MessageSquare size={11} /> View
        </button>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-white">Support Tickets</h1>
        <p className="text-sm text-text-muted">{data?.data?.length ?? 0} tickets</p>
      </div>

      <div className="flex gap-1 bg-surface-200 rounded-lg p-1 w-fit">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className={`text-xs px-3 py-1.5 rounded-md capitalize transition-colors ${tab === t ? "bg-brand-500 text-white" : "text-text-muted hover:text-white"}`}>{t.replace("_", " ")}</button>
        ))}
      </div>

      <DataTable columns={columns} data={data?.data ?? []} loading={isLoading} searchColumn="description" searchPlaceholder="Search ticket…" />

      {/* Ticket detail drawer */}
      {selected && (
        <div className="fixed inset-0 bg-black/70 flex items-end md:items-center justify-center z-50" onClick={() => setSelected(null)}>
          <div className="card w-full max-w-lg max-h-[80vh] flex flex-col" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between p-5 border-b border-white/5">
              <div>
                <h2 className="text-white font-semibold">{selected.order_number ? `Order #${selected.order_number}` : selected.category}</h2>
                <p className="text-text-muted text-xs capitalize">{selected.category} · <StatusBadge status={selected.status} className="inline" /></p>
              </div>
              <div className="flex items-center gap-2">
                {selected.status !== "resolved" && (
                  <button onClick={() => closeMutation.mutate(selected.$id)} className="text-xs px-2 py-1 rounded bg-white/5 hover:bg-white/10 text-text-muted transition-colors">Close ticket</button>
                )}
                <button onClick={() => setSelected(null)} className="text-text-muted hover:text-white text-lg">×</button>
              </div>
            </div>

            <div className="flex-1 overflow-y-auto p-5 space-y-3">
              {msgLoading ? (
                [...Array(3)].map((_, i) => <div key={i} className="skeleton h-12 rounded-lg" />)
              ) : (
                messages?.data?.map((m, i) => (
                  <div key={i} className={`flex gap-2 ${m.sender === "admin" ? "flex-row-reverse" : ""}`}>
                    <div className={`w-7 h-7 rounded-full flex-shrink-0 flex items-center justify-center text-xs font-bold ${m.sender === "admin" ? "bg-brand-500 text-white" : "bg-white/10 text-text-secondary"}`}>
                      {m.sender === "admin" ? "A" : "U"}
                    </div>
                    <div className={`max-w-[75%] rounded-xl px-3 py-2 text-sm ${m.sender === "admin" ? "bg-brand-500/20 text-white" : "bg-surface-200 text-text-secondary"}`}>
                      <p>{m.message}</p>
                      <p className="text-xs opacity-50 mt-0.5">{formatDateTime(m.created_at)}</p>
                    </div>
                  </div>
                ))
              )}
            </div>

            {selected.status !== "resolved" && (
              <div className="p-4 border-t border-white/5 flex gap-2">
                <input
                  value={reply}
                  onChange={e => setReply(e.target.value)}
                  onKeyDown={e => e.key === "Enter" && !e.shiftKey && reply && replyMutation.mutate({ id: selected.$id, message: reply })}
                  placeholder="Type a reply…"
                  className="flex-1 bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-text-muted focus:outline-none focus:border-brand-500"
                />
                <button
                  onClick={() => reply && replyMutation.mutate({ id: selected.$id, message: reply })}
                  disabled={!reply || replyMutation.isPending}
                  className="px-3 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white disabled:opacity-50 transition-colors"
                >
                  <Send size={14} />
                </button>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
