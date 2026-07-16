import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import Link from "next/link";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/Card";
import { StatusBadge } from "@/components/ui/StatusDot";
import { cn, formatDate, round1, riskLevelToStatus } from "@/lib/utils";

export default async function SessionDetailPage({
  params,
}: {
  params: { id: string };
}) {
  const supabase = await createClient();
  const { id } = params;

  const { data: session } = await supabase
    .from("sessions")
    .select("*")
    .eq("id", id)
    .single();

  if (!session) notFound();

  // Get captures with athlete info
  const { data: captures } = await supabase
    .from("captures")
    .select("*, athletes(name, jersey_number, position)")
    .eq("session_id", id)
    .order("created_at");

  return (
    <div className="mx-auto max-w-4xl">
      <Link
        href="/sessions"
        className="mb-4 inline-flex items-center gap-1 text-sm text-gray-500 hover:text-brand"
      >
        &larr; Back to Sessions
      </Link>

      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">
          Session: {formatDate(session.date)}
        </h1>
        <div className="mt-1 flex items-center gap-2">
          <span
            className={cn(
              "rounded-full px-2.5 py-0.5 text-xs font-medium",
              session.state === "fresh"
                ? "bg-blue-50 text-blue-700"
                : "bg-orange-50 text-orange-700"
            )}
          >
            {session.state}
          </span>
          <span className="text-sm text-gray-500">
            {captures?.length ?? 0} athletes captured
          </span>
        </div>
      </div>

      {/* Results table */}
      <Card>
        <CardHeader>
          <CardTitle>Results</CardTitle>
        </CardHeader>
        <CardContent>
          {!captures || captures.length === 0 ? (
            <p className="text-sm text-gray-500">No captures in this session.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left text-xs text-gray-400">
                    <th className="pb-2 pr-4">#</th>
                    <th className="pb-2 pr-4">Athlete</th>
                    <th className="pb-2 pr-4">Valgus</th>
                    <th className="pb-2 pr-4">Flexion</th>
                    <th className="pb-2 pr-4">Trunk</th>
                    <th className="pb-2 pr-4">LESS</th>
                    <th className="pb-2 pr-4">Asymmetry</th>
                    <th className="pb-2">Risk</th>
                  </tr>
                </thead>
                <tbody>
                  {captures.map((c: any) => (
                    <tr key={c.id} className="border-b last:border-0">
                      <td className="py-2.5 pr-4 font-bold text-gray-500">
                        {c.athletes?.jersey_number || "—"}
                      </td>
                      <td className="py-2.5 pr-4">
                        <Link
                          href={`/athlete/${c.athlete_id}`}
                          className="font-medium text-brand hover:underline"
                        >
                          {c.athletes?.name ?? "Unknown"}
                        </Link>
                        <p className="text-xs text-gray-400">
                          {c.athletes?.position}
                        </p>
                      </td>
                      <td className="py-2.5 pr-4">
                        {round1(c.knee_valgus_deg)}&deg;
                      </td>
                      <td className="py-2.5 pr-4">
                        {round1(c.knee_flexion_deg)}&deg;
                      </td>
                      <td className="py-2.5 pr-4">
                        {round1(c.trunk_lean_deg)}&deg;
                      </td>
                      <td className="py-2.5 pr-4">{c.less_score ?? "—"}</td>
                      <td className="py-2.5 pr-4">
                        {c.asymmetry_index
                          ? (c.asymmetry_index * 100).toFixed(1) + "%"
                          : "—"}
                      </td>
                      <td className="py-2.5">
                        <StatusBadge status={riskLevelToStatus(c.risk_level)} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {session.notes && (
        <Card className="mt-4">
          <CardHeader>
            <CardTitle>Notes</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-gray-700">{session.notes}</p>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
