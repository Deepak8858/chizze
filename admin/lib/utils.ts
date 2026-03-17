import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
import { format, formatDistanceToNow } from "date-fns";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatCurrency(amount: number): string {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0,
  }).format(amount);
}

export function formatNumber(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return n.toString();
}

export function formatDate(iso: string, fmt = "dd MMM yyyy"): string {
  try {
    return format(new Date(iso), fmt);
  } catch {
    return iso;
  }
}

export function formatDateTime(iso: string): string {
  try {
    return format(new Date(iso), "dd MMM yyyy, HH:mm");
  } catch {
    return iso;
  }
}

export function timeAgo(iso: string): string {
  try {
    return formatDistanceToNow(new Date(iso), { addSuffix: true });
  } catch {
    return iso;
  }
}

export function formatDuration(minutes: number): string {
  if (minutes < 60) return `${Math.round(minutes)}m`;
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes % 60);
  return m > 0 ? `${h}h ${m}m` : `${h}h`;
}

export function statusColor(status: string): string {
  const map: Record<string, string> = {
    placed: "text-info bg-info/10",
    confirmed: "text-brand-500 bg-brand-500/10",
    preparing: "text-brand-500 bg-brand-500/10",
    ready: "text-success bg-success/10",
    pickedUp: "text-success bg-success/10",
    outForDelivery: "text-success bg-success/10",
    delivered: "text-success bg-success/10",
    cancelled: "text-error bg-error/10",
    pending: "text-warning bg-warning/10",
    processing: "text-info bg-info/10",
    completed: "text-success bg-success/10",
    failed: "text-error bg-error/10",
    active: "text-success bg-success/10",
    inactive: "text-text-muted bg-text-muted/10",
    open: "text-info bg-info/10",
    investigating: "text-warning bg-warning/10",
    resolved: "text-success bg-success/10",
    closed: "text-text-muted bg-text-muted/10",
  };
  return map[status] ?? "text-text-secondary bg-text-secondary/10";
}

export function trendColor(delta: number): string {
  if (delta > 0) return "text-success";
  if (delta < 0) return "text-error";
  return "text-text-muted";
}

export function trendIcon(delta: number): string {
  if (delta > 0) return "↑";
  if (delta < 0) return "↓";
  return "→";
}

export function parseOrderItems(itemsJson: string) {
  try {
    return JSON.parse(itemsJson);
  } catch {
    return [];
  }
}

export function truncate(str: string, len = 40): string {
  return str.length > len ? str.slice(0, len) + "…" : str;
}

export function capitalize(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1).replace(/_/g, " ");
}

export function slugify(str: string): string {
  return str.toLowerCase().replace(/\s+/g, "-").replace(/[^\w-]+/g, "");
}

/** Returns the SLA class for a kanban card */
export function slaClass(
  status: string,
  lastChangedAt: string
): "sla-normal" | "sla-warning" | "sla-critical" {
  const thresholds: Record<string, number> = {
    placed: 5, confirmed: 2, preparing: 20, ready: 5, pickedUp: 2,
    outForDelivery: 30,
  };
  const threshold = thresholds[status] ?? 30;
  const elapsed = (Date.now() - new Date(lastChangedAt).getTime()) / 60000;
  if (elapsed > threshold * 2) return "sla-critical";
  if (elapsed > threshold) return "sla-warning";
  return "sla-normal";
}
