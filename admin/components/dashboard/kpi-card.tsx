"use client";
import { cn, formatCurrency, formatNumber, trendColor, trendIcon } from "@/lib/utils";
import type { LucideIcon } from "lucide-react";

interface KPICardProps {
  label: string;
  value: string | number;
  delta?: number; // % change
  icon: LucideIcon;
  iconColor?: string;
  format?: "currency" | "number" | "raw";
  loading?: boolean;
}

export function KPICard({
  label,
  value,
  delta,
  icon: Icon,
  iconColor = "text-brand-400",
  format = "raw",
  loading = false,
}: KPICardProps) {
  const formatted =
    typeof value === "number"
      ? format === "currency"
        ? formatCurrency(value)
        : format === "number"
        ? formatNumber(value)
        : value.toString()
      : value;

  if (loading) {
    return (
      <div className="card flex flex-col gap-3">
        <div className="skeleton h-4 w-24" />
        <div className="skeleton h-8 w-32" />
        <div className="skeleton h-3 w-20" />
      </div>
    );
  }

  return (
    <div className="card flex flex-col gap-2 hover:border-white/[0.14] transition-colors">
      <div className="flex items-center justify-between">
        <p className="text-xs text-text-secondary font-medium">{label}</p>
        <div className={cn("w-7 h-7 rounded-lg flex items-center justify-center bg-white/5", iconColor)}>
          <Icon size={14} />
        </div>
      </div>
      <p className="text-2xl font-bold text-white tabular-nums">{formatted}</p>
      {delta !== undefined && (
        <p className={cn("text-xs font-medium flex items-center gap-1", trendColor(delta))}>
          <span>{trendIcon(delta)}</span>
          <span>{Math.abs(delta).toFixed(1)}% vs yesterday</span>
        </p>
      )}
    </div>
  );
}
