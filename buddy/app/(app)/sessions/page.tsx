import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { Card } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { cn, formatDate } from "@/lib/utils";

export default async function SessionsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("team_id")
    .eq("id", user.id)
    .single();

  if (!profile?.team_id) return <p>No team found.</p>;

  const { data: sessions } = await supabase
    .from("sessions")
    .select("*")
    .eq("team_id", profile.team_id)
    .order("date", { ascending: false });

  // Count captures per session
  const sessionIds = sessions?.map((s) => s.id) ?? [];
  let captureCounts: Record<string, number> = {};
  if (sessionIds.length > 0) {
    const { data: captures } = await supabase
      .from("captures")
      .select("session_id")
      .in("session_id", sessionIds);

    captureCounts = (captures ?? []).reduce(
      (acc, c) => {
        acc[c.session_id] = (acc[c.session_id] || 0) + 1;
        return acc;
      },
      {} as Record<string, number>
    );
  }

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Sessions</h1>
          <p className="text-sm text-gray-500">All capture sessions</p>
        </div>
        <Link href="/capture">
          <Button>+ New Session</Button>
        </Link>
      </div>

      {!sessions || sessions.length === 0 ? (
        <Card className="py-12 text-center">
          <p className="text-gray-500">No sessions yet.</p>
          <p className="mt-2 text-sm text-gray-400">
            Run your first capture session to start collecting data.
          </p>
        </Card>
      ) : (
        <div className="space-y-2">
          {sessions.map((session) => (
            <Link
              key={session.id}
              href={`/sessions/${session.id}`}
              className="block"
            >
              <Card className="flex items-center gap-4 transition-shadow hover:shadow-md">
                <div
                  className={cn(
                    "flex h-10 w-10 items-center justify-center rounded-full text-xs font-bold",
                    session.state === "fresh"
                      ? "bg-blue-100 text-blue-700"
                      : "bg-orange-100 text-orange-700"
                  )}
                >
                  {session.state === "fresh" ? "F" : "T"}
                </div>
                <div className="flex-1">
                  <p className="font-semibold text-gray-900">
                    {formatDate(session.date)}{" "}
                    <span
                      className={cn(
                        "ml-2 rounded-full px-2 py-0.5 text-xs font-medium",
                        session.state === "fresh"
                          ? "bg-blue-50 text-blue-700"
                          : "bg-orange-50 text-orange-700"
                      )}
                    >
                      {session.state}
                    </span>
                  </p>
                  <p className="text-xs text-gray-500">
                    {captureCounts[session.id] ?? 0} captures
                  </p>
                </div>
                <span className="text-gray-300">&rsaquo;</span>
              </Card>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
