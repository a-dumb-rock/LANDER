import { createClient } from "@/lib/supabase/server";
import { ReadinessBoard } from "@/components/ReadinessBoard";
import { computeAthleteReadiness, DEFAULT_THRESHOLDS } from "@/lib/engine/delta";
import type { CaptureWithSessionState } from "@/lib/engine/delta";
import type { Thresholds, AthleteReadiness } from "@/lib/types/database";

export default async function HomePage() {
  const supabase = await createClient();

  // Get user's team
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("team_id")
    .eq("id", user.id)
    .single();

  if (!profile?.team_id) {
    return (
      <div className="flex h-full items-center justify-center">
        <p className="text-gray-500">No team found. Please complete setup.</p>
      </div>
    );
  }

  const teamId = profile.team_id;

  // Get team thresholds
  const { data: team } = await supabase
    .from("teams")
    .select("thresholds")
    .eq("id", teamId)
    .single();

  const thresholds: Thresholds = (team?.thresholds as Thresholds) ?? DEFAULT_THRESHOLDS;

  // Get all athletes
  const { data: athletes } = await supabase
    .from("athletes")
    .select("*")
    .eq("team_id", teamId)
    .eq("active", true)
    .order("jersey_number");

  // Get all captures with session info (last 8 weeks)
  const eightWeeksAgo = new Date(Date.now() - 8 * 7 * 24 * 60 * 60 * 1000)
    .toISOString()
    .split("T")[0];

  const { data: sessions } = await supabase
    .from("sessions")
    .select("*")
    .eq("team_id", teamId)
    .gte("date", eightWeeksAgo)
    .order("date", { ascending: false });

  const sessionIds = sessions?.map((s) => s.id) ?? [];
  const sessionMap = new Map(sessions?.map((s) => [s.id, s]) ?? []);

  let captures: CaptureWithSessionState[] = [];
  if (sessionIds.length > 0) {
    const { data: rawCaptures } = await supabase
      .from("captures")
      .select("*")
      .in("session_id", sessionIds);

    captures = (rawCaptures ?? []).map((c) => ({
      ...c,
      sessionState: sessionMap.get(c.session_id)?.state ?? "fresh",
      sessionDate: sessionMap.get(c.session_id)?.date ?? c.created_at,
    }));
  }

  // Compute readiness for each athlete
  const readinessList: AthleteReadiness[] = (athletes ?? []).map((athlete) => {
    const athleteCaptures = captures.filter(
      (c) => c.athlete_id === athlete.id
    );
    return computeAthleteReadiness(athlete, athleteCaptures, thresholds);
  });

  // Sort: red first, then yellow, then green, then none
  const statusOrder = { red: 0, yellow: 1, green: 2, none: 3 };
  readinessList.sort((a, b) => statusOrder[a.status] - statusOrder[b.status]);

  return <ReadinessBoard readinessList={readinessList} teamId={teamId} />;
}
