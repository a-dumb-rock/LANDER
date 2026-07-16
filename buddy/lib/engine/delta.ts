/**
 * LANDER Buddy — Delta Engine
 *
 * Implements the core product logic from the spec (Part 2, Part 10):
 *   - Baseline: rolling average of last N fresh readings per athlete
 *   - Fatigue delta: how much the fatigued reading worsened vs fresh baseline
 *   - Trend: direction of deltas over recent weeks
 *   - Readiness status: Green / Yellow / Red
 *   - Recommendation: plain-language action for the coach
 *
 * All computation is done on the fly from raw captures (no caching needed at MVP scale).
 */

import type {
  Capture,
  Session,
  Thresholds,
  ReadinessStatus,
  Trend,
  AthleteReadiness,
  Athlete,
} from "@/lib/types/database";

export const DEFAULT_THRESHOLDS: Thresholds = {
  valgus_yellow_deg: 5,
  valgus_red_deg: 10,
  flexion_yellow_deg: 45,
  flexion_red_deg: 30,
  delta_yellow_pct: 10,
  delta_red_pct: 20,
  baseline_n_sessions: 3,
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function avg(vals: number[]): number | null {
  if (vals.length === 0) return null;
  return vals.reduce((a, b) => a + b, 0) / vals.length;
}

function pctChange(baseline: number, current: number): number {
  if (baseline === 0) return 0;
  return ((current - baseline) / Math.abs(baseline)) * 100;
}

// ─── Baseline computation ─────────────────────────────────────────────────────

export interface Baseline {
  valgus: number | null;
  flexion: number | null;
  lessScore: number | null;
  n: number; // how many fresh readings contributed
}

/**
 * Compute a rolling baseline from the last `n` fresh sessions.
 * A "fresh" capture is one from a session tagged state='fresh'.
 */
export function computeBaseline(
  freshCaptures: Capture[],
  n: number = DEFAULT_THRESHOLDS.baseline_n_sessions
): Baseline {
  // Sort newest-first, take last n
  const sorted = [...freshCaptures]
    .filter((c) => c.knee_valgus_deg !== null || c.knee_flexion_deg !== null)
    .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
    .slice(0, n);

  return {
    valgus: avg(sorted.map((c) => c.knee_valgus_deg!).filter((v) => v !== null)),
    flexion: avg(sorted.map((c) => c.knee_flexion_deg!).filter((v) => v !== null)),
    lessScore: avg(sorted.map((c) => c.less_score!).filter((v) => v !== null)),
    n: sorted.length,
  };
}

// ─── Fatigue delta ────────────────────────────────────────────────────────────

export interface FatigueDelta {
  valgusDeltaDeg: number | null;    // fatigued - fresh (positive = worse)
  flexionDeltaDeg: number | null;   // fatigued - fresh (negative = worse)
  valgusDeltaPct: number | null;    // % worsening from baseline
  flexionDeltaPct: number | null;
  lessScoreDelta: number | null;
  vulnerabilityScore: number | null; // 0-100 from the vulnerability_score column
  fatigueCaptureDate: string | null;
}

/**
 * Compute the fatigue delta for a single fatigued capture vs a baseline.
 */
export function computeFatigueDelta(
  fatiguedCapture: Capture,
  baseline: Baseline
): FatigueDelta {
  const valgusDelta =
    fatiguedCapture.knee_valgus_deg !== null && baseline.valgus !== null
      ? fatiguedCapture.knee_valgus_deg - baseline.valgus
      : null;

  const flexionDelta =
    fatiguedCapture.knee_flexion_deg !== null && baseline.flexion !== null
      ? fatiguedCapture.knee_flexion_deg - baseline.flexion
      : null;

  const lessDelta =
    fatiguedCapture.less_score !== null && baseline.lessScore !== null
      ? fatiguedCapture.less_score - baseline.lessScore
      : null;

  return {
    valgusDeltaDeg: valgusDelta !== null ? parseFloat(valgusDelta.toFixed(2)) : null,
    flexionDeltaDeg: flexionDelta !== null ? parseFloat(flexionDelta.toFixed(2)) : null,
    valgusDeltaPct:
      valgusDelta !== null && baseline.valgus !== null && baseline.valgus !== 0
        ? parseFloat(pctChange(baseline.valgus, fatiguedCapture.knee_valgus_deg!).toFixed(1))
        : null,
    flexionDeltaPct:
      flexionDelta !== null && baseline.flexion !== null && baseline.flexion !== 0
        ? parseFloat(pctChange(baseline.flexion, fatiguedCapture.knee_flexion_deg!).toFixed(1))
        : null,
    lessScoreDelta: lessDelta !== null ? parseFloat(lessDelta.toFixed(1)) : null,
    vulnerabilityScore: fatiguedCapture.vulnerability_score,
    fatigueCaptureDate: fatiguedCapture.created_at,
  };
}

// ─── Trend ────────────────────────────────────────────────────────────────────

/**
 * Look at the last 4 weeks of fatigue deltas and determine if things
 * are improving, stable, or worsening.
 *
 * Logic: linear regression on valgus delta over time. Slope > 0.5 = worsening,
 * slope < -0.5 = improving, otherwise stable. Need at least 3 data points.
 */
export function computeTrend(deltas: { date: string; valgusDeltaDeg: number | null }[]): Trend {
  const valid = deltas
    .filter((d) => d.valgusDeltaDeg !== null)
    .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
    .slice(-4); // last 4

  if (valid.length < 2) return "unknown";

  // Simple slope via least-squares
  const n = valid.length;
  const xs = valid.map((_, i) => i);
  const ys = valid.map((d) => d.valgusDeltaDeg!);
  const xMean = xs.reduce((a, b) => a + b, 0) / n;
  const yMean = ys.reduce((a, b) => a + b, 0) / n;
  const num = xs.reduce((s, x, i) => s + (x - xMean) * (ys[i] - yMean), 0);
  const den = xs.reduce((s, x) => s + (x - xMean) ** 2, 0);
  const slope = den === 0 ? 0 : num / den;

  if (slope > 0.5) return "worsening";
  if (slope < -0.5) return "improving";
  return "stable";
}

// ─── Readiness status ─────────────────────────────────────────────────────────

/**
 * Green / Yellow / Red derivation from the spec.
 *
 * Red  if: valgus > red threshold, OR flexion < flexion_red, OR fatigue delta % > delta_red
 * Yellow if: any metric in caution zone
 * Green otherwise
 */
export function computeReadinessStatus(
  latestFreshCapture: Capture | null,
  latestFatiguedCapture: Capture | null,
  baseline: Baseline,
  trend: Trend,
  thresholds: Thresholds
): ReadinessStatus {
  if (!latestFreshCapture && !latestFatiguedCapture) return "none";

  const capture = latestFatiguedCapture ?? latestFreshCapture;
  if (!capture) return "none";

  const valgus = capture.knee_valgus_deg ?? 0;
  const flexion = capture.knee_flexion_deg ?? 999;

  // Absolute risk from raw metrics
  if (
    valgus >= thresholds.valgus_red_deg ||
    flexion <= thresholds.flexion_red_deg
  ) {
    return "red";
  }

  // Fatigue delta risk
  if (latestFatiguedCapture && baseline.valgus !== null) {
    const delta = computeFatigueDelta(latestFatiguedCapture, baseline);
    if (
      delta.valgusDeltaPct !== null &&
      delta.valgusDeltaPct >= thresholds.delta_red_pct
    ) {
      return "red";
    }
    if (
      delta.valgusDeltaPct !== null &&
      delta.valgusDeltaPct >= thresholds.delta_yellow_pct
    ) {
      return "yellow";
    }
  }

  // Trend contribution
  if (trend === "worsening") return "yellow";

  // Caution zone absolute metrics
  if (
    valgus >= thresholds.valgus_yellow_deg ||
    flexion <= thresholds.flexion_yellow_deg
  ) {
    return "yellow";
  }

  return "green";
}

// ─── Recommendation ───────────────────────────────────────────────────────────

export function generateRecommendation(
  status: ReadinessStatus,
  trend: Trend,
  delta: FatigueDelta | null,
  thresholds: Thresholds
): string {
  if (status === "none") return "No data yet — run a fresh capture session.";

  if (status === "red") {
    const reason =
      delta?.valgusDeltaPct !== null && delta?.valgusDeltaPct !== undefined && delta.valgusDeltaPct >= thresholds.delta_red_pct
        ? `Landing degraded ${delta.valgusDeltaPct.toFixed(0)}% under fatigue vs. baseline.`
        : "High valgus or stiff landing detected.";
    return `⛔ High risk — recommend rest or reduced load. ${reason}`;
  }

  if (status === "yellow") {
    if (trend === "worsening") {
      return "⚠️ Trending toward risk over the last few weeks — monitor closely and consider load reduction.";
    }
    const reason =
      delta?.valgusDeltaPct !== null && delta?.valgusDeltaPct !== undefined
        ? `Fatigue degradation: ${delta.valgusDeltaPct.toFixed(0)}% above baseline.`
        : "Mechanics in caution zone.";
    return `⚠️ Caution — watch training load this week. ${reason}`;
  }

  if (trend === "improving") {
    return "✅ Stable and improving — keep current training plan.";
  }

  return "✅ Looking good — mechanics stable within baseline.";
}

// ─── Full readiness computation for one athlete ───────────────────────────────

export interface CaptureWithSessionState extends Capture {
  sessionState: "fresh" | "fatigued";
  sessionDate: string;
}

export function computeAthleteReadiness(
  athlete: Athlete,
  capturesWithState: CaptureWithSessionState[],
  thresholds: Thresholds = DEFAULT_THRESHOLDS
): AthleteReadiness {
  const freshCaptures = capturesWithState.filter((c) => c.sessionState === "fresh");
  const fatiguedCaptures = capturesWithState.filter((c) => c.sessionState === "fatigued");

  const baseline = computeBaseline(freshCaptures, thresholds.baseline_n_sessions);

  // Most recent readings
  const latestFresh = freshCaptures.sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  )[0] ?? null;
  const latestFatigued = fatiguedCaptures.sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  )[0] ?? null;

  // Trend: use fatigued sessions if available, otherwise use fresh valgus trend
  const trendPoints = fatiguedCaptures
    .map((c) => ({
      date: c.created_at,
      valgusDeltaDeg:
        c.knee_valgus_deg !== null && baseline.valgus !== null
          ? c.knee_valgus_deg - baseline.valgus
          : null,
    }))
    .filter((p) => p.valgusDeltaDeg !== null);

  const trend = computeTrend(trendPoints);

  const delta = latestFatigued ? computeFatigueDelta(latestFatigued, baseline) : null;

  const status = computeReadinessStatus(
    latestFresh,
    latestFatigued,
    baseline,
    trend,
    thresholds
  );

  const recommendation = generateRecommendation(status, trend, delta, thresholds);

  // One-line note for the readiness board
  let note = recommendation;
  if (delta?.valgusDeltaPct !== null && delta?.valgusDeltaPct !== undefined) {
    note = `↑${delta.valgusDeltaPct.toFixed(0)}% under fatigue`;
    if (trend === "worsening") note += " · trending ↑";
    else if (trend === "improving") note += " · trending ↓";
  } else if (status === "none") {
    note = "No data";
  } else if (status === "green") {
    note = "Stable";
  }

  // Unique weeks of data
  const weekStrings = new Set(
    capturesWithState.map((c) => {
      const d = new Date(c.sessionDate);
      const week = Math.floor(d.getTime() / (7 * 24 * 60 * 60 * 1000));
      return `${d.getFullYear()}-${week}`;
    })
  );

  const latestCapture = latestFatigued ?? latestFresh;

  return {
    athlete,
    status,
    trend,
    latestValgus: latestCapture?.knee_valgus_deg ?? null,
    latestFlexion: latestCapture?.knee_flexion_deg ?? null,
    fatigueDeltaPct: delta?.valgusDeltaPct ?? null,
    vulnerabilityScore: delta?.vulnerabilityScore ?? latestFatigued?.vulnerability_score ?? null,
    note,
    hasBaseline: baseline.n >= 1,
    weeksOfData: weekStrings.size,
  };
}
