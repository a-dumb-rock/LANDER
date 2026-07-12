"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Input";
import type { Team, Thresholds } from "@/lib/types/database";

interface SettingsFormProps {
  team: Team;
  thresholds: Thresholds;
  profile: { team_id: string | null; role: string; full_name: string | null };
}

export function SettingsForm({ team, thresholds: initialThresholds, profile }: SettingsFormProps) {
  const [teamName, setTeamName] = useState(team.name);
  const [thresholds, setThresholds] = useState<Thresholds>(initialThresholds);
  const [loading, setLoading] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState("");
  const router = useRouter();

  function updateThreshold(key: keyof Thresholds, value: string) {
    setThresholds((prev) => ({
      ...prev,
      [key]: parseFloat(value) || 0,
    }));
  }

  async function handleSave() {
    setLoading(true);
    setError("");
    setSaved(false);

    const supabase = createClient();

    const { error: updateErr } = await supabase
      .from("teams")
      .update({
        name: teamName,
        thresholds: thresholds as unknown as Record<string, unknown>,
      })
      .eq("id", team.id);

    if (updateErr) {
      setError(updateErr.message);
    } else {
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    }

    setLoading(false);
    router.refresh();
  }

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="mb-6 text-2xl font-bold text-gray-900">Settings</h1>

      {/* Team info */}
      <Card className="mb-6">
        <CardHeader>
          <CardTitle>Team</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <Input
            id="teamName"
            label="Team name"
            value={teamName}
            onChange={(e) => setTeamName(e.target.value)}
          />
          <div className="grid grid-cols-2 gap-3">
            <div>
              <p className="text-xs text-gray-400">Your role</p>
              <p className="text-sm font-medium capitalize">{profile.role}</p>
            </div>
            <div>
              <p className="text-xs text-gray-400">Your name</p>
              <p className="text-sm font-medium">{profile.full_name || "—"}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Thresholds */}
      <Card className="mb-6">
        <CardHeader>
          <CardTitle>Risk Thresholds</CardTitle>
          <p className="text-xs text-gray-500">
            These determine when an athlete is flagged as Yellow (caution) or Red
            (high risk). Adjust based on your sport and population.
          </p>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <div>
              <h4 className="mb-2 text-sm font-semibold text-gray-700">
                Knee Valgus (degrees)
              </h4>
              <div className="grid grid-cols-2 gap-3">
                <Input
                  id="valgus_yellow"
                  label="Yellow threshold"
                  type="number"
                  step="0.5"
                  value={thresholds.valgus_yellow_deg.toString()}
                  onChange={(e) =>
                    updateThreshold("valgus_yellow_deg", e.target.value)
                  }
                />
                <Input
                  id="valgus_red"
                  label="Red threshold"
                  type="number"
                  step="0.5"
                  value={thresholds.valgus_red_deg.toString()}
                  onChange={(e) =>
                    updateThreshold("valgus_red_deg", e.target.value)
                  }
                />
              </div>
            </div>

            <div>
              <h4 className="mb-2 text-sm font-semibold text-gray-700">
                Knee Flexion (degrees, lower = worse)
              </h4>
              <div className="grid grid-cols-2 gap-3">
                <Input
                  id="flexion_yellow"
                  label="Yellow threshold"
                  type="number"
                  step="0.5"
                  value={thresholds.flexion_yellow_deg.toString()}
                  onChange={(e) =>
                    updateThreshold("flexion_yellow_deg", e.target.value)
                  }
                />
                <Input
                  id="flexion_red"
                  label="Red threshold"
                  type="number"
                  step="0.5"
                  value={thresholds.flexion_red_deg.toString()}
                  onChange={(e) =>
                    updateThreshold("flexion_red_deg", e.target.value)
                  }
                />
              </div>
            </div>

            <div>
              <h4 className="mb-2 text-sm font-semibold text-gray-700">
                Fatigue Delta (% worsening from baseline)
              </h4>
              <div className="grid grid-cols-2 gap-3">
                <Input
                  id="delta_yellow"
                  label="Yellow threshold (%)"
                  type="number"
                  step="1"
                  value={thresholds.delta_yellow_pct.toString()}
                  onChange={(e) =>
                    updateThreshold("delta_yellow_pct", e.target.value)
                  }
                />
                <Input
                  id="delta_red"
                  label="Red threshold (%)"
                  type="number"
                  step="1"
                  value={thresholds.delta_red_pct.toString()}
                  onChange={(e) =>
                    updateThreshold("delta_red_pct", e.target.value)
                  }
                />
              </div>
            </div>

            <div>
              <h4 className="mb-2 text-sm font-semibold text-gray-700">
                Baseline Calculation
              </h4>
              <Input
                id="baseline_n"
                label="Number of fresh sessions to average"
                type="number"
                min="1"
                max="10"
                value={thresholds.baseline_n_sessions.toString()}
                onChange={(e) =>
                  updateThreshold("baseline_n_sessions", e.target.value)
                }
              />
            </div>
          </div>
        </CardContent>
      </Card>

      {/* CV Model config info */}
      <Card className="mb-6">
        <CardHeader>
          <CardTitle>CV Model</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-gray-500">Mode</span>
              <code className="rounded bg-gray-100 px-2 py-0.5 text-xs">
                {process.env.NEXT_PUBLIC_CV_MODEL_MODE ?? "mock"}
              </code>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-500">API URL</span>
              <code className="rounded bg-gray-100 px-2 py-0.5 text-xs">
                {process.env.NEXT_PUBLIC_CV_MODEL_URL ?? "http://localhost:8000"}
              </code>
            </div>
            <p className="mt-2 text-xs text-gray-400">
              Set NEXT_PUBLIC_CV_MODEL_MODE=real and NEXT_PUBLIC_CV_MODEL_URL in
              your .env.local to connect to the live LANDER CV model.
            </p>
          </div>
        </CardContent>
      </Card>

      {/* Save */}
      {error && (
        <p className="mb-4 rounded-md bg-red-50 p-3 text-sm text-red-700">
          {error}
        </p>
      )}
      {saved && (
        <p className="mb-4 rounded-md bg-green-50 p-3 text-sm text-green-700">
          Settings saved successfully.
        </p>
      )}
      <Button onClick={handleSave} disabled={loading} className="w-full">
        {loading ? "Saving..." : "Save Settings"}
      </Button>
    </div>
  );
}
