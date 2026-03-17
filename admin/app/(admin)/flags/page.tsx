"use client";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { flagsApi } from "@/lib/api";
import { formatDateTime } from "@/lib/utils";
import { toast } from "sonner";
import type { FeatureFlag } from "@/types";
import { Flag, ToggleLeft, ToggleRight } from "lucide-react";

export default function FlagsPage() {
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ["feature-flags"],
    queryFn: () => flagsApi.list() as Promise<{ data: FeatureFlag[] }>,
  });

  const toggleMutation = useMutation({
    mutationFn: ({ id, enabled }: { id: string; enabled: boolean }) => flagsApi.update(id, { enabled }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["feature-flags"] }); toast.success("Flag updated"); },
    onError: () => toast.error("Failed"),
  });

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-white">Feature Flags</h1>
        <p className="text-sm text-text-muted">Toggle features without redeploying</p>
      </div>

      {isLoading ? (
        <div className="space-y-3">{[...Array(6)].map((_, i) => <div key={i} className="skeleton h-16 rounded-xl" />)}</div>
      ) : (
        <div className="space-y-2">
          {data?.data?.map(flag => {
            const isEnabled = flag.type === "boolean" ? flag.value === true : !!flag.value;
            return (
              <div key={flag.key} className="card px-5 py-4 flex items-center gap-4">
                <div className={`w-2 h-2 rounded-full flex-shrink-0 ${isEnabled ? "bg-status-success" : "bg-status-error"}`} />
                <div className="flex-1 min-w-0">
                  <p className="text-white font-medium text-sm">{flag.key}</p>
                  <p className="text-text-muted text-xs truncate">{flag.description}</p>
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-xs text-text-muted font-mono">
                    {String(flag.value)}
                  </span>
                  <span className={`text-xs ${isEnabled ? "text-status-success" : "text-text-muted"}`}>
                    {isEnabled ? "Enabled" : "Disabled"}
                  </span>
                  <button
                    onClick={() => toggleMutation.mutate({ id: flag.key, enabled: !isEnabled })}
                    className="transition-colors"
                  >
                    {isEnabled
                      ? <ToggleRight size={24} className="text-status-success" />
                      : <ToggleLeft size={24} className="text-text-muted hover:text-white" />
                    }
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
