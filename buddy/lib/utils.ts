import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
import type { ReadinessStatus, Trend } from "./types/database";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function statusColor(status: ReadinessStatus) {
  switch (status) {
    case "green":
      return {
        bg: "bg-status-green-bg",
        text: "text-status-green-text",
        dot: "bg-status-green",
        badge: "bg-status-green-bg text-status-green-text border-status-green/30",
        label: "Good",
      };
    case "yellow":
      return {
        bg: "bg-status-yellow-bg",
        text: "text-status-yellow-text",
        dot: "bg-status-yellow",
        badge: "bg-status-yellow-bg text-status-yellow-text border-status-yellow/30",
        label: "Caution",
      };
    case "red":
      return {
        bg: "bg-status-red-bg",
        text: "text-status-red-text",
        dot: "bg-status-red",
        badge: "bg-status-red-bg text-status-red-text border-status-red/30",
        label: "High Risk",
      };
    default:
      return {
        bg: "bg-gray-100",
        text: "text-gray-500",
        dot: "bg-gray-400",
        badge: "bg-gray-100 text-gray-500 border-gray-300",
        label: "No Data",
      };
  }
}

export function trendIcon(trend: Trend): string {
  switch (trend) {
    case "improving":
      return "↓";
    case "worsening":
      return "↑";
    case "stable":
      return "→";
    default:
      return "—";
  }
}

export function trendLabel(trend: Trend): string {
  switch (trend) {
    case "improving":
      return "Improving";
    case "worsening":
      return "Worsening";
    case "stable":
      return "Stable";
    default:
      return "Unknown";
  }
}

export function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export function formatDateShort(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

export function riskLevelToStatus(riskLevel: string | null): ReadinessStatus {
  if (!riskLevel) return "none";
  const lower = riskLevel.toLowerCase();
  if (lower.includes("high")) return "red";
  if (lower.includes("moderate")) return "yellow";
  if (lower.includes("low")) return "green";
  return "none";
}

export function round1(n: number | null | undefined): string {
  if (n === null || n === undefined) return "—";
  return n.toFixed(1);
}

export function round0(n: number | null | undefined): string {
  if (n === null || n === undefined) return "—";
  return Math.round(n).toString();
}
