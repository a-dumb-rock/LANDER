"use client";

import Link from "next/link";
import { StatusDot, StatusBadge } from "@/components/ui/StatusDot";
import { Card } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { cn, trendIcon, trendLabel } from "@/lib/utils";
import type { AthleteReadiness, ReadinessStatus } from "@/lib/types/database";

interface ReadinessBoardProps {
  readinessList: AthleteReadiness[];
  teamId: string;
}

export function ReadinessBoard({ readinessList, teamId }: ReadinessBoardProps) {
  // Summary counts
  const counts = readinessList.reduce(
    (acc, r) => {
      acc[r.status] = (acc[r.status] || 0) + 1;
      return acc;
    },
    {} as Record<ReadinessStatus, number>
  );

  const alerts = readinessList.filter(
    (r) => r.status === "red" || (r.status === "yellow" && r.trend === "worsening")
  );

  return (
    <div className="mx-auto max-w-5xl">
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Readiness Board</h1>
          <p className="text-sm text-gray-500">
            This week&apos;s knee readiness for your team
          </p>
        </div>
        <Link href="/capture">
          <Button size="lg">+ New Capture Session</Button>
        </Link>
      </div>

      {/* Summary bar */}
      <Card className="mb-6">
        <div className="flex flex-wrap items-center gap-6">
          <div className="flex items-center gap-2">
            <StatusDot status="green" />
            <span className="text-sm font-medium text-gray-700">
              {counts.green ?? 0} Good
            </span>
          </div>
          <div className="flex items-center gap-2">
            <StatusDot status="yellow" />
            <span className="text-sm font-medium text-gray-700">
              {counts.yellow ?? 0} Caution
            </span>
          </div>
          <div className="flex items-center gap-2">
            <StatusDot status="red" />
            <span className="text-sm font-medium text-gray-700">
              {counts.red ?? 0} High Risk
            </span>
          </div>
          <div className="flex items-center gap-2">
            <span className="inline-block h-3.5 w-3.5 rounded-full bg-gray-300" />
            <span className="text-sm font-medium text-gray-700">
              {counts.none ?? 0} No Data
            </span>
          </div>

          {alerts.length > 0 && (
            <div className="ml-auto rounded-md bg-red-50 px-3 py-1.5 text-xs font-medium text-red-700">
              {alerts.length} athlete{alerts.length > 1 ? "s" : ""} need attention
            </div>
          )}
        </div>
      </Card>

      {/* Athlete list */}
      {readinessList.length === 0 ? (
        <Card className="py-12 text-center">
          <p className="text-gray-500">No athletes yet.</p>
          <p className="mt-2 text-sm text-gray-400">
            Add athletes in the{" "}
            <Link href="/roster" className="text-brand underline">
              Roster
            </Link>{" "}
            page, then run a capture session.
          </p>
        </Card>
      ) : (
        <div className="space-y-2">
          {readinessList.map((r) => (
            <Link
              key={r.athlete.id}
              href={`/athlete/${r.athlete.id}`}
              className="block"
            >
              <Card className="transition-shadow hover:shadow-md">
                <div className="flex items-center gap-4">
                  {/* Status dot */}
                  <StatusDot status={r.status} size="lg" />

                  {/* Jersey */}
                  <div className="flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-sm font-bold text-gray-700">
                    #{r.athlete.jersey_number || "—"}
                  </div>

                  {/* Name & position */}
                  <div className="min-w-0 flex-1">
                    <p className="font-semibold text-gray-900">
                      {r.athlete.name}
                    </p>
                    <p className="truncate text-xs text-gray-500">
                      {r.athlete.position || "No position"}
                    </p>
                  </div>

                  {/* Key metrics */}
                  <div className="hidden items-center gap-6 text-sm sm:flex">
                    {r.latestValgus !== null && (
                      <div className="text-center">
                        <p className="text-xs text-gray-400">Valgus</p>
                        <p className="font-medium">{r.latestValgus.toFixed(1)}&deg;</p>
                      </div>
                    )}
                    {r.fatigueDeltaPct !== null && (
                      <div className="text-center">
                        <p className="text-xs text-gray-400">Delta</p>
                        <p
                          className={cn(
                            "font-medium",
                            r.fatigueDeltaPct > 20
                              ? "text-red-600"
                              : r.fatigueDeltaPct > 10
                              ? "text-yellow-600"
                              : "text-green-600"
                          )}
                        >
                          {r.fatigueDeltaPct > 0 ? "+" : ""}
                          {r.fatigueDeltaPct.toFixed(0)}%
                        </p>
                      </div>
                    )}
                    {r.trend !== "unknown" && (
                      <div className="text-center">
                        <p className="text-xs text-gray-400">Trend</p>
                        <p className="font-medium">
                          {trendIcon(r.trend)} {trendLabel(r.trend)}
                        </p>
                      </div>
                    )}
                  </div>

                  {/* Note */}
                  <div className="hidden max-w-[200px] text-right lg:block">
                    <p className="truncate text-xs text-gray-500">{r.note}</p>
                  </div>

                  {/* Status badge */}
                  <StatusBadge status={r.status} />
                </div>
              </Card>
            </Link>
          ))}
        </div>
      )}

      {/* Reminder at bottom */}
      <div className="mt-6 rounded-md border border-blue-200 bg-blue-50 p-4 text-sm text-blue-800">
        <strong>Tip:</strong> Use the same jump and the same camera position each
        time so comparisons stay valid. Film once fresh (warm-up) and once fatigued
        (end of practice).
      </div>
    </div>
  );
}
