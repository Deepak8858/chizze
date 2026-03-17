"use client";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { notificationsApi } from "@/lib/api";
import { formatDateTime } from "@/lib/utils";
import { toast } from "sonner";
import type { Notification } from "@/types";
import { Bell, Send, Users, User } from "lucide-react";

const TARGET_TYPES = ["all_users", "all_riders", "all_restaurants", "specific_user"];

export default function NotificationsPage() {
  const [form, setForm] = useState({ title: "", body: "", target_type: "all_users", target_id: "", type: "promotional" });
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["admin-notifications"],
    queryFn: () => notificationsApi.list({ limit: 50 }) as Promise<{ data: Notification[] }>,
  });

  const sendMutation = useMutation({
    mutationFn: (body: typeof form) => notificationsApi.send(body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["admin-notifications"] });
      toast.success("Notification sent");
      setForm({ title: "", body: "", target_type: "all_users", target_id: "", type: "promotional" });
    },
    onError: () => toast.error("Failed to send"),
  });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">Notifications</h1>
        <p className="text-sm text-text-muted">Broadcast push notifications via Firebase FCM</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Send panel */}
        <div className="card p-5 space-y-4">
          <h2 className="text-sm font-semibold text-white flex items-center gap-2"><Send size={14} className="text-brand-400" /> Send Notification</h2>

          <div>
            <label className="text-xs text-text-muted mb-1 block">Title</label>
            <input
              value={form.title}
              onChange={e => setForm(f => ({ ...f, title: e.target.value }))}
              placeholder="Notification title…"
              className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-text-muted focus:outline-none focus:border-brand-500"
            />
          </div>
          <div>
            <label className="text-xs text-text-muted mb-1 block">Message</label>
            <textarea
              value={form.body}
              onChange={e => setForm(f => ({ ...f, body: e.target.value }))}
              rows={3}
              placeholder="Notification body…"
              className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-text-muted focus:outline-none focus:border-brand-500 resize-none"
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-xs text-text-muted mb-1 block">Target</label>
              <select
                value={form.target_type}
                onChange={e => setForm(f => ({ ...f, target_type: e.target.value }))}
                className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
              >
                {TARGET_TYPES.map(t => <option key={t} value={t}>{t.replace(/_/g, " ")}</option>)}
              </select>
            </div>
            <div>
              <label className="text-xs text-text-muted mb-1 block">Type</label>
              <select
                value={form.type}
                onChange={e => setForm(f => ({ ...f, type: e.target.value }))}
                className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
              >
                {["promotional", "order_update", "system", "offer"].map(t => <option key={t} value={t}>{t}</option>)}
              </select>
            </div>
          </div>
          {form.target_type === "specific_user" && (
            <div>
              <label className="text-xs text-text-muted mb-1 block">User / Rider ID</label>
              <input
                value={form.target_id}
                onChange={e => setForm(f => ({ ...f, target_id: e.target.value }))}
                placeholder="User ID…"
                className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-text-muted focus:outline-none focus:border-brand-500"
              />
            </div>
          )}
          <button
            onClick={() => sendMutation.mutate(form)}
            disabled={!form.title || !form.body || sendMutation.isPending}
            className="w-full py-2.5 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium disabled:opacity-50 transition-colors flex items-center justify-center gap-2"
          >
            <Send size={14} /> {sendMutation.isPending ? "Sending…" : "Send Notification"}
          </button>
        </div>

        {/* Recent history */}
        <div className="card p-5">
          <h2 className="text-sm font-semibold text-white flex items-center gap-2 mb-4"><Bell size={14} /> Recent Notifications</h2>
          <div className="space-y-3 max-h-96 overflow-y-auto">
            {isLoading ? (
              [...Array(5)].map((_, i) => <div key={i} className="skeleton h-14 rounded-lg" />)
            ) : (
              data?.data?.map(n => (
                <div key={n.$id} className="flex items-start gap-3 p-3 rounded-lg bg-surface-200">
                  <div className="w-7 h-7 rounded-full bg-brand-500/20 flex items-center justify-center flex-shrink-0">
                    <Bell size={12} className="text-brand-400" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-white text-xs font-medium truncate">{n.title}</p>
                    <p className="text-text-muted text-xs truncate">{n.body}</p>
                    <p className="text-text-muted text-xs mt-0.5">{formatDateTime(n.created_at)}</p>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
