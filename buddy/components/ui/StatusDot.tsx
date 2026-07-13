"use client";

import { cn, statusColor } from "@/lib/utils";
import type { ReadinessStatus } from "@/lib/types/database";

export function StatusDot({
  status,
  size = "md",
}: {
  status: ReadinessStatus;
  size?: "sm" | "md" | "lg";
}) {
  const { dot } = statusColor(status);
  const sizeClass = {
    sm: "h-2.5 w-2.5",
    md: "h-3.5 w-3.5",
    lg: "h-5 w-5",
  }[size];

  return (
    <span
      className={cn("inline-block rounded-full ring-2 ring-white", dot, sizeClass)}
      aria-label={`Status: ${status}`}
    />
  );
}

export function StatusBadge({
  status,
  label,
}: {
  status: ReadinessStatus;
  label?: string;
}) {
  const { badge, label: defaultLabel } = statusColor(status);
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-medium",
        badge
      )}
    >
      <StatusDot status={status} size="sm" />
      {label ?? defaultLabel}
    </span>
  );
}
