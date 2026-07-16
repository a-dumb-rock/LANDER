/**
 * LANDER Buddy — CV Model Integration
 *
 * Sends a video to the LANDER CV backend (server.py) and returns metrics.
 * Falls back to a realistic mock when NEXT_PUBLIC_CV_MODEL_MODE=mock.
 *
 * API contract (from server.py):
 *   POST /analyze-landing
 *   Body: multipart/form-data { file: <video> }
 *   Response: {
 *     knee_valgus_angle: number,
 *     knee_flexion_angle: number,
 *     asymmetry_index: number,
 *     acl_risk_level: "HIGH RISK" | "MODERATE RISK" | "LOW RISK",
 *     feedback_message: string,
 *     ... (raw metrics blob)
 *   }
 */

import type { ModelMetrics } from "@/lib/types/database";

// ─── Mock ─────────────────────────────────────────────────────────────────────

function gaussianRandom(mean: number, std: number): number {
  // Box-Muller transform
  const u1 = Math.random();
  const u2 = Math.random();
  const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  return mean + std * z;
}

/**
 * Realistic mock that returns plausible biomechanics values.
 * Adds slight randomness so repeated calls give slightly different results.
 * Simulates ~600ms processing time.
 */
export async function mockAnalyzeLanding(
  sessionState: "fresh" | "fatigued" = "fresh"
): Promise<ModelMetrics> {
  await new Promise((r) => setTimeout(r, 600 + Math.random() * 800));

  // Fatigued readings are typically worse (higher valgus, lower flexion)
  const isFatigued = sessionState === "fatigued";
  const valgus = Math.max(0, gaussianRandom(isFatigued ? 9.5 : 5.5, 2.5));
  const flexion = Math.max(15, gaussianRandom(isFatigued ? 33 : 44, 6));
  const trunk = Math.max(0, gaussianRandom(18, 5));
  const asymmetry = Math.max(0, gaussianRandom(0.06, 0.03));
  const less = Math.round(Math.max(0, gaussianRandom(isFatigued ? 6 : 3, 1.5)));

  let risk_level: string;
  if (valgus > 10 || flexion < 30) risk_level = "HIGH RISK";
  else if (valgus > 5 || flexion < 45) risk_level = "MODERATE RISK";
  else risk_level = "LOW RISK";

  return {
    knee_valgus_deg: parseFloat(valgus.toFixed(2)),
    knee_flexion_deg: parseFloat(flexion.toFixed(2)),
    trunk_lean_deg: parseFloat(trunk.toFixed(2)),
    less_score: less,
    risk_level,
    asymmetry_index: parseFloat(asymmetry.toFixed(4)),
    raw: {
      model_version: "mock-v1",
      feedback_message:
        risk_level === "HIGH RISK"
          ? "Danger: Severe knee inward cave or stiff landing detected."
          : risk_level === "MODERATE RISK"
          ? "Caution: Minor knee valgus or shallow landing depth."
          : "Optimal: Safe knee alignment and force absorption depth.",
    },
  };
}

// ─── Real API call ────────────────────────────────────────────────────────────

export async function realAnalyzeLanding(
  file: File,
  modelUrl: string
): Promise<ModelMetrics> {
  const form = new FormData();
  form.append("file", file);

  const res = await fetch(`${modelUrl}/analyze-landing`, {
    method: "POST",
    body: form,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`CV model API error ${res.status}: ${text}`);
  }

  const data = await res.json();

  // Map the server.py response shape to our ModelMetrics type
  return {
    knee_valgus_deg:
      data.knee_valgus_angle ??
      data.at_initial_contact?.knee_valgus_deg ??
      data.knee_valgus_deg ??
      0,
    knee_flexion_deg:
      data.knee_flexion_angle ??
      data.at_initial_contact?.knee_flexion_deg ??
      data.knee_flexion_deg ??
      0,
    trunk_lean_deg:
      data.trunk_lean_deg ?? data.at_initial_contact?.trunk_lean_deg ?? 0,
    less_score: data.less_total ?? data.less_score ?? 0,
    risk_level: data.acl_risk_level ?? data.risk?.category ?? "UNKNOWN",
    asymmetry_index: data.asymmetry_index ?? 0,
    raw: data,
  };
}

// ─── Dispatcher ──────────────────────────────────────────────────────────────

export async function analyzeVideo(
  file: File,
  sessionState: "fresh" | "fatigued" = "fresh"
): Promise<ModelMetrics> {
  const mode = process.env.NEXT_PUBLIC_CV_MODEL_MODE ?? "mock";
  const modelUrl = process.env.NEXT_PUBLIC_CV_MODEL_URL ?? "http://localhost:8000";

  if (mode === "mock") {
    return mockAnalyzeLanding(sessionState);
  }

  return realAnalyzeLanding(file, modelUrl);
}

// ─── Vulnerability score (mirrors fatigue.py logic) ──────────────────────────

/**
 * Compute a 0-100 vulnerability score from two captures (fresh vs fatigued).
 * This mirrors the logic in landr/fatigue.py:compare().
 */
export function computeVulnerabilityScore(
  freshMetrics: ModelMetrics,
  fatiguedMetrics: ModelMetrics
): { score: number; category: "robust" | "moderate" | "vulnerable" } {
  const dValgus = Math.max(
    0,
    fatiguedMetrics.knee_valgus_deg - freshMetrics.knee_valgus_deg
  );
  const dFlexionLoss = Math.max(
    0,
    freshMetrics.knee_flexion_deg - fatiguedMetrics.knee_flexion_deg
  );
  const dLess = Math.max(
    0,
    (fatiguedMetrics.less_score ?? 0) - (freshMetrics.less_score ?? 0)
  );
  const dAsym = Math.max(
    0,
    (fatiguedMetrics.asymmetry_index ?? 0) - (freshMetrics.asymmetry_index ?? 0)
  );

  // Matches the weighting in fatigue.py exactly
  const score = Math.min(
    100,
    Math.max(
      0,
      Math.pow(dValgus, 1.4) * 0.4 +
        dFlexionLoss * 1.1 +
        dAsym * 25.0 +
        dLess * 4.0
    )
  );

  const category: "robust" | "moderate" | "vulnerable" =
    score < 25 ? "robust" : score < 55 ? "moderate" : "vulnerable";

  return { score: parseFloat(score.toFixed(1)), category };
}
