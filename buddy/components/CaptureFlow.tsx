"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Card } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { Input, Select } from "@/components/ui/Input";
import { StatusBadge } from "@/components/ui/StatusDot";
import { analyzeVideo } from "@/lib/engine/model";
import { riskLevelToStatus, round1 } from "@/lib/utils";
import type { Athlete, SessionItem, ModelMetrics } from "@/lib/types/database";

interface CaptureFlowProps {
  athletes: Athlete[];
  teamId: string;
  userId: string;
}

type Step = "setup" | "upload" | "processing" | "summary";

export function CaptureFlow({ athletes, teamId, userId }: CaptureFlowProps) {
  const router = useRouter();
  const [step, setStep] = useState<Step>("setup");
  const [sessionDate, setSessionDate] = useState(
    new Date().toISOString().split("T")[0]
  );
  const [sessionState, setSessionState] = useState<"fresh" | "fatigued">("fresh");
  const [items, setItems] = useState<SessionItem[]>([]);
  const [error, setError] = useState("");

  // ─── Step 1: Setup ────────────────────────────────────────────────
  function handleSetupNext() {
    if (athletes.length === 0) {
      setError("Add athletes to your roster first.");
      return;
    }
    setStep("upload");
  }

  // ─── Step 2: Upload / assign ──────────────────────────────────────
  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const files = e.target.files;
    if (!files) return;

    const newItems: SessionItem[] = Array.from(files).map((file) => ({
      file,
      athleteId: athletes[0]?.id ?? "",
      athleteName: athletes[0]?.name ?? "",
      status: "pending" as const,
      metrics: null,
      error: null,
    }));

    setItems((prev) => [...prev, ...newItems]);
  }

  function updateItemAthlete(index: number, athleteId: string) {
    const athlete = athletes.find((a) => a.id === athleteId);
    setItems((prev) =>
      prev.map((item, i) =>
        i === index
          ? { ...item, athleteId, athleteName: athlete?.name ?? "" }
          : item
      )
    );
  }

  function removeItem(index: number) {
    setItems((prev) => prev.filter((_, i) => i !== index));
  }

  // ─── Step 3: Process all ──────────────────────────────────────────
  async function handleSubmit() {
    if (items.length === 0) {
      setError("Add at least one video.");
      return;
    }
    setError("");
    setStep("processing");

    const supabase = createClient();

    // Create session
    const { data: session, error: sessionErr } = await supabase
      .from("sessions")
      .insert({
        team_id: teamId,
        date: sessionDate,
        state: sessionState,
        created_by: userId,
      })
      .select()
      .single();

    if (sessionErr || !session) {
      setError("Failed to create session: " + (sessionErr?.message ?? ""));
      setStep("upload");
      return;
    }

    // Process each item sequentially
    const updatedItems = [...items];

    for (let i = 0; i < updatedItems.length; i++) {
      updatedItems[i] = { ...updatedItems[i], status: "processing" };
      setItems([...updatedItems]);

      try {
        const metrics: ModelMetrics = await analyzeVideo(
          updatedItems[i].file,
          sessionState
        );

        // Save capture to DB
        const { error: captureErr } = await supabase.from("captures").insert({
          session_id: session.id,
          athlete_id: updatedItems[i].athleteId,
          knee_valgus_deg: metrics.knee_valgus_deg,
          knee_flexion_deg: metrics.knee_flexion_deg,
          trunk_lean_deg: metrics.trunk_lean_deg,
          less_score: metrics.less_score,
          risk_level: metrics.risk_level,
          asymmetry_index: metrics.asymmetry_index,
          raw_metrics: metrics.raw as Record<string, unknown> ?? null,
          model_version: (metrics.raw as Record<string, unknown>)?.model_version as string ?? "unknown",
        });

        if (captureErr) throw new Error(captureErr.message);

        updatedItems[i] = { ...updatedItems[i], status: "done", metrics };
      } catch (err) {
        updatedItems[i] = {
          ...updatedItems[i],
          status: "error",
          error: err instanceof Error ? err.message : "Unknown error",
        };
      }

      setItems([...updatedItems]);
    }

    setStep("summary");
  }

  // ─── Render steps ─────────────────────────────────────────────────
  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="mb-6 text-2xl font-bold text-gray-900">
        New Capture Session
      </h1>

      {/* Step indicators */}
      <div className="mb-6 flex items-center gap-2 text-sm">
        {(["setup", "upload", "processing", "summary"] as Step[]).map((s, idx) => (
          <div key={s} className="flex items-center gap-2">
            <span
              className={`flex h-6 w-6 items-center justify-center rounded-full text-xs font-bold ${
                step === s
                  ? "bg-brand text-white"
                  : idx < ["setup", "upload", "processing", "summary"].indexOf(step)
                  ? "bg-green-100 text-green-700"
                  : "bg-gray-100 text-gray-400"
              }`}
            >
              {idx + 1}
            </span>
            <span
              className={
                step === s ? "font-medium text-gray-900" : "text-gray-400"
              }
            >
              {s === "setup"
                ? "Setup"
                : s === "upload"
                ? "Upload"
                : s === "processing"
                ? "Processing"
                : "Summary"}
            </span>
            {idx < 3 && <span className="mx-2 text-gray-300">&#8250;</span>}
          </div>
        ))}
      </div>

      {/* Step 1: Setup */}
      {step === "setup" && (
        <Card>
          <h2 className="mb-4 text-lg font-semibold">Session Details</h2>
          <div className="space-y-4">
            <Input
              id="date"
              label="Session date"
              type="date"
              value={sessionDate}
              onChange={(e) => setSessionDate(e.target.value)}
            />
            <Select
              id="state"
              label="Session type"
              value={sessionState}
              onChange={(e) =>
                setSessionState(e.target.value as "fresh" | "fatigued")
              }
              options={[
                { value: "fresh", label: "Fresh (warm-up / rested)" },
                { value: "fatigued", label: "Fatigued (end of practice)" },
              ]}
            />
            <div className="rounded-md border border-blue-200 bg-blue-50 p-3 text-sm text-blue-800">
              <strong>Reminder:</strong> Use the same jump (drop vertical jump)
              and the same camera position each time so comparisons stay valid.
            </div>
            {error && <p className="text-sm text-red-600">{error}</p>}
            <Button onClick={handleSetupNext}>Next: Upload Videos</Button>
          </div>
        </Card>
      )}

      {/* Step 2: Upload */}
      {step === "upload" && (
        <div className="space-y-4">
          <Card>
            <h2 className="mb-2 text-lg font-semibold">Upload Videos</h2>
            <p className="mb-4 text-sm text-gray-500">
              Upload one video per athlete. Assign each to the correct athlete.
            </p>

            {/* File input */}
            <div className="mb-4">
              <label className="flex cursor-pointer items-center justify-center rounded-lg border-2 border-dashed border-gray-300 bg-gray-50 px-6 py-8 transition-colors hover:border-brand hover:bg-brand/5">
                <div className="text-center">
                  <svg
                    className="mx-auto mb-2 h-10 w-10 text-gray-400"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    strokeWidth="1.5"
                    stroke="currentColor"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      d="M12 16.5V9.75m0 0l3 3m-3-3l-3 3M6.75 19.5a4.5 4.5 0 01-1.41-8.775 5.25 5.25 0 0110.338-2.32 3 3 0 013.598 2.395A4.5 4.5 0 0118.75 19.5H6.75z"
                    />
                  </svg>
                  <p className="text-sm font-medium text-gray-700">
                    Click to upload videos
                  </p>
                  <p className="text-xs text-gray-400">MP4, MOV, or AVI</p>
                </div>
                <input
                  type="file"
                  className="hidden"
                  accept="video/*"
                  multiple
                  onChange={handleFileChange}
                />
              </label>
            </div>

            {/* Items list */}
            {items.length > 0 && (
              <div className="space-y-3">
                {items.map((item, idx) => (
                  <div
                    key={idx}
                    className="flex items-center gap-3 rounded-md border border-surface-border bg-gray-50 p-3"
                  >
                    <div className="flex-1">
                      <p className="text-sm font-medium text-gray-800 truncate">
                        {item.file.name}
                      </p>
                      <p className="text-xs text-gray-400">
                        {(item.file.size / 1024 / 1024).toFixed(1)} MB
                      </p>
                    </div>
                    <Select
                      value={item.athleteId}
                      onChange={(e) => updateItemAthlete(idx, e.target.value)}
                      options={athletes.map((a) => ({
                        value: a.id,
                        label: `#${a.jersey_number} ${a.name}`,
                      }))}
                      className="w-48"
                    />
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => removeItem(idx)}
                      className="text-red-500"
                    >
                      &times;
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </Card>

          {error && <p className="text-sm text-red-600">{error}</p>}

          <div className="flex gap-3">
            <Button variant="outline" onClick={() => setStep("setup")}>
              Back
            </Button>
            <Button onClick={handleSubmit} disabled={items.length === 0}>
              Submit &amp; Analyze ({items.length} video
              {items.length !== 1 ? "s" : ""})
            </Button>
          </div>
        </div>
      )}

      {/* Step 3: Processing */}
      {step === "processing" && (
        <Card>
          <h2 className="mb-4 text-lg font-semibold">Processing...</h2>
          <p className="mb-4 text-sm text-gray-500">
            Analyzing each video with the LANDER CV model. This may take a moment.
          </p>
          <div className="space-y-3">
            {items.map((item, idx) => (
              <div
                key={idx}
                className="flex items-center gap-3 rounded-md border p-3"
              >
                <div className="flex-1">
                  <p className="text-sm font-medium">{item.athleteName}</p>
                  <p className="truncate text-xs text-gray-400">
                    {item.file.name}
                  </p>
                </div>
                <div className="text-sm">
                  {item.status === "pending" && (
                    <span className="text-gray-400">Waiting...</span>
                  )}
                  {item.status === "processing" && (
                    <span className="animate-pulse text-brand font-medium">
                      Analyzing...
                    </span>
                  )}
                  {item.status === "done" && (
                    <span className="text-green-600 font-medium">Done</span>
                  )}
                  {item.status === "error" && (
                    <span className="text-red-600 font-medium">Error</span>
                  )}
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Step 4: Summary */}
      {step === "summary" && (
        <div className="space-y-4">
          <Card>
            <h2 className="mb-2 text-lg font-semibold">Session Complete</h2>
            <p className="mb-4 text-sm text-gray-500">
              {sessionState === "fresh" ? "Fresh" : "Fatigued"} session on{" "}
              {sessionDate} — {items.filter((i) => i.status === "done").length}/
              {items.length} athletes processed.
            </p>
            <div className="space-y-3">
              {items.map((item, idx) => (
                <div
                  key={idx}
                  className="flex items-center gap-4 rounded-md border p-3"
                >
                  <div className="flex-1">
                    <p className="font-semibold text-gray-900">
                      {item.athleteName}
                    </p>
                    {item.error && (
                      <p className="text-xs text-red-600">{item.error}</p>
                    )}
                  </div>
                  {item.metrics && (
                    <div className="flex items-center gap-4 text-sm">
                      <div className="text-center">
                        <p className="text-xs text-gray-400">Valgus</p>
                        <p className="font-medium">
                          {round1(item.metrics.knee_valgus_deg)}&deg;
                        </p>
                      </div>
                      <div className="text-center">
                        <p className="text-xs text-gray-400">Flexion</p>
                        <p className="font-medium">
                          {round1(item.metrics.knee_flexion_deg)}&deg;
                        </p>
                      </div>
                      <div className="text-center">
                        <p className="text-xs text-gray-400">LESS</p>
                        <p className="font-medium">{item.metrics.less_score}</p>
                      </div>
                      <StatusBadge
                        status={riskLevelToStatus(item.metrics.risk_level)}
                      />
                    </div>
                  )}
                </div>
              ))}
            </div>
          </Card>

          <div className="flex gap-3">
            <Button onClick={() => router.push("/")}>
              Back to Readiness Board
            </Button>
            <Button
              variant="outline"
              onClick={() => {
                setItems([]);
                setStep("setup");
              }}
            >
              New Session
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
