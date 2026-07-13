"use client";

import Link from "next/link";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/Card";
import { StatusBadge } from "@/components/ui/StatusDot";
import { Button } from "@/components/ui/Button";
import { TrendChart } from "@/components/TrendChart";
import { cn, trendIcon, trendLabel, round1, formatDate } from "@/lib/utils";
import type { Athlete, AthleteReadiness } from "@/lib/types/database";
import type { Baseline } from "@/lib/engine/delta";

interface ChartPoint {
  date: string;
  state: "fresh" | "fatigued";
  valgus: number | null;
  flexion: number | null;
  lessScore: number | null;
  deltaPct: number | null;
}

interface AthleteProfileProps {
  athlete: Athlete;
  readiness: AthleteReadiness;
  baseline: Baseline;
  chartData: ChartPoint[];
  recommendation: string;
}

export function AthleteProfile({
  athlete,
  readiness,
  baseline,
  chartData,
  recommendation,
}: AthleteProfileProps) {
  return (
    <div className="mx-auto max-w-4xl">
      {/* Back button */}
      <Link
        href="/"
        className="mb-4 inline-flex items-center gap-1 text-sm text-gray-500 hover:text-brand"
      >
        &larr; Back to Readiness Board
      </Link>

      {/* Header */}
      <div className="mb-6 flex items-center gap-4">
        <div className="flex h-14 w-14 items-center justify-center rounded-full bg-brand/10 text-xl font-bold text-brand">
          #{athlete.jersey_number || "—"}
        </div>
        <div className="flex-1">
          <h1 className="text-2xl font-bold text-gray-900">{athlete.name}</h1>
          <p className="text-sm text-gray-500">{athlete.position || "No position"}</p>
        </div>
        <StatusBadge status={readiness.status} />
      </div>

      {/* Stats cards */}
      <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Card className="text-center">
          <p className="text-xs text-gray-400">Latest Valgus</p>
          <p className="text-xl font-bold">
            {round1(readiness.latestValgus)}&deg;
          </p>
        </Card>
        <Card className="text-center">
          <p className="text-xs text-gray-400">Fatigue Delta</p>
          <p
            className={cn(
              "text-xl font-bold",
              readiness.fatigueDeltaPct !== null && readiness.fatigueDeltaPct > 20
                ? "text-red-600"
                : readiness.fatigueDeltaPct !== null && readiness.fatigueDeltaPct > 10
                ? "text-yellow-600"
                : "text-green-600"
            )}
          >
            {readiness.fatigueDeltaPct !== null
              ? `${readiness.fatigueDeltaPct > 0 ? "+" : ""}${readiness.fatigueDeltaPct.toFixed(0)}%`
              : "—"}
          </p>
        </Card>
        <Card className="text-center">
          <p className="text-xs text-gray-400">Trend</p>
          <p className="text-xl font-bold">
            {trendIcon(readiness.trend)} {trendLabel(readiness.trend)}
          </p>
        </Card>
        <Card className="text-center">
          <p className="text-xs text-gray-400">Baseline Valgus</p>
          <p className="text-xl font-bold">
            {round1(baseline.valgus)}&deg;
            <span className="text-xs font-normal text-gray-400">
              {" "}
              (n={baseline.n})
            </span>
          </p>
        </Card>
      </div>

      {/* Recommendation */}
      <Card className="mb-6">
        <CardHeader>
          <CardTitle>Recommendation</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm leading-relaxed text-gray-700">{recommendation}</p>
        </CardContent>
      </Card>

      {/* Trend Charts */}
      <div className="mb-6 grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Knee Valgus Over Time</CardTitle>
          </CardHeader>
          <CardContent>
            <TrendChart
              data={chartData}
              dataKey="valgus"
              label="Valgus (deg)"
              color="#EF4444"
              baselineValue={baseline.valgus}
            />
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Knee Flexion Over Time</CardTitle>
          </CardHeader>
          <CardContent>
            <TrendChart
              data={chartData}
              dataKey="flexion"
              label="Flexion (deg)"
              color="#3B82F6"
              baselineValue={baseline.flexion}
            />
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>LESS Score Over Time</CardTitle>
          </CardHeader>
          <CardContent>
            <TrendChart
              data={chartData}
              dataKey="lessScore"
              label="LESS Score"
              color="#F59E0B"
              baselineValue={baseline.lessScore}
            />
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Fatigue Delta (%)</CardTitle>
          </CardHeader>
          <CardContent>
            <TrendChart
              data={chartData.filter((d) => d.deltaPct !== null)}
              dataKey="deltaPct"
              label="Delta %"
              color="#8B5CF6"
            />
          </CardContent>
        </Card>
      </div>

      {/* Session history */}
      <Card>
        <CardHeader>
          <CardTitle>Session History</CardTitle>
        </CardHeader>
        <CardContent>
          {chartData.length === 0 ? (
            <p className="text-sm text-gray-500">No sessions recorded yet.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left text-xs text-gray-400">
                    <th className="pb-2 pr-4">Date</th>
                    <th className="pb-2 pr-4">Type</th>
                    <th className="pb-2 pr-4">Valgus</th>
                    <th className="pb-2 pr-4">Flexion</th>
                    <th className="pb-2 pr-4">LESS</th>
                    <th className="pb-2">Delta</th>
                  </tr>
                </thead>
                <tbody>
                  {[...chartData].reverse().map((d, i) => (
                    <tr key={i} className="border-b last:border-0">
                      <td className="py-2 pr-4 text-gray-700">
                        {formatDate(d.date)}
                      </td>
                      <td className="py-2 pr-4">
                        <span
                          className={cn(
                            "rounded-full px-2 py-0.5 text-xs font-medium",
                            d.state === "fresh"
                              ? "bg-blue-50 text-blue-700"
                              : "bg-orange-50 text-orange-700"
                          )}
                        >
                          {d.state}
                        </span>
                      </td>
                      <td className="py-2 pr-4">{round1(d.valgus)}&deg;</td>
                      <td className="py-2 pr-4">{round1(d.flexion)}&deg;</td>
                      <td className="py-2 pr-4">{d.lessScore ?? "—"}</td>
                      <td className="py-2">
                        {d.deltaPct !== null ? `${d.deltaPct.toFixed(0)}%` : "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
