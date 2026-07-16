import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import { AthleteProfile } from "@/components/AthleteProfile";
import {
  computeAthleteReadiness,
  computeBaseline,
  computeFatigueDelta,
  DEFAULT_THRESHOLDS,
  generateRecommendation,
} from "@/lib/engine/delta";
import type { CaptureWithSessionState } from "@/lib/engine/delta";
import type { Thresholds } from "@/lib/types/database";

export default async function AthleteProfilePage({
  params,
}: {
  params: { id: string };
}) {
  const supabase = await createClient();
  const { id } = params;

  // Get athlete
  const { data: athlete } = await supabase
    .from("athletes")
    .select("*")
    .eq("id", id)
    .single();

  if (!athlete) notFound();

  // Get user's team thresholds
  const { data: team } = await supabase
    .from("teams")
    .select("thresholds")
    .eq("id", athlete.team_id)
    .single();

  const thresholds: Thresholds =
    (team?.thresholds as Thresholds) ?? DEFAULT_THRESHOLDS;

  // Get all sessions for this team (last 12 weeks)
  const twelveWeeksAgo = new Date(Date.now() - 12 * 7 * 24 * 60 * 60 * 1000)
    .toISOString()
    .split("T")[0];

  const { data: sessions } = await supabase
    .from("sessions")
    .select("*")
    .eq("team_id", athlete.team_id)
    .gte("date", twelveWeeksAgo)
    .order("date", { ascending: true });

  const sessionIds = sessions?.map((s) => s.id) ?? [];
  const sessionMap = new Map(sessions?.map((s) => [s.id, s]) ?? []);

  // Get this athlete's captures
  let captures: CaptureWithSessionState[] = [];
  if (sessionIds.length > 0) {
    const { data: rawCaptures } = await supabase
      .from("captures")
      .select("*")
      .eq("athlete_id", id)
      .in("session_id", sessionIds)
      .order("created_at", { ascending: true });

    captures = (rawCaptures ?? []).map((c) => ({
      ...c,
      sessionState: sessionMap.get(c.session_id)?.state ?? "fresh",
      sessionDate: sessionMap.get(c.session_id)?.date ?? c.created_at,
    }));
  }

  // Compute readiness
  const readiness = computeAthleteReadiness(athlete, captures, thresholds);

  // Compute baseline for display
  const freshCaptures = captures.filter((c) => c.sessionState === "fresh");
  const fatiguedCaptures = captures.filter((c) => c.sessionState === "fatigued");
  const baseline = computeBaseline(freshCaptures, thresholds.baseline_n_sessions);

  // Compute per-session deltas for chart data
  const chartData = captures.map((c) => {
    const delta =
      c.sessionState === "fatigued" ? computeFatigueDelta(c, baseline) : null;
    return {
      date: sessionMap.get(c.session_id)?.date ?? c.created_at,
      state: c.sessionState,
      valgus: c.knee_valgus_deg,
      flexion: c.knee_flexion_deg,
      lessScore: c.less_score,
      deltaPct: delta?.valgusDeltaPct ?? null,
    };
  });

  // Latest delta for recommendation
  const latestFatigued = fatiguedCaptures.sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  )[0];
  const latestDelta = latestFatigued
    ? computeFatigueDelta(latestFatigued, baseline)
    : null;
  const recommendation = generateRecommendation(
    readiness.status,
    readiness.trend,
    latestDelta,
    thresholds
  );

  return (
    <AthleteProfile
      athlete={athlete}
      readiness={readiness}
      baseline={baseline}
      chartData={chartData}
      recommendation={recommendation}
    />
  );
}
