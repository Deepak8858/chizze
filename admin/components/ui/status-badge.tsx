import { cn, statusColor, capitalize } from "@/lib/utils";

interface StatusBadgeProps {
  status: string;
  className?: string;
  label?: string;
}

export function StatusBadge({ status, className, label }: StatusBadgeProps) {
  return (
    <span
      className={cn(
        "inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold uppercase tracking-wide",
        statusColor(status),
        className
      )}
    >
      {label ? capitalize(label) : capitalize(status)}
    </span>
  );
}
