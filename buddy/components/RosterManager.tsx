"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Card } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Input";
import type { Athlete } from "@/lib/types/database";

interface RosterManagerProps {
  athletes: Athlete[];
  teamId: string;
}

export function RosterManager({ athletes: initialAthletes, teamId }: RosterManagerProps) {
  const [athletes, setAthletes] = useState(initialAthletes);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [jerseyNumber, setJerseyNumber] = useState("");
  const [position, setPosition] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const router = useRouter();

  function resetForm() {
    setName("");
    setJerseyNumber("");
    setPosition("");
    setEditingId(null);
    setShowForm(false);
    setError("");
  }

  function startEdit(athlete: Athlete) {
    setName(athlete.name);
    setJerseyNumber(athlete.jersey_number);
    setPosition(athlete.position);
    setEditingId(athlete.id);
    setShowForm(true);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);

    const supabase = createClient();

    if (editingId) {
      // Update
      const { error: updateErr } = await supabase
        .from("athletes")
        .update({ name, jersey_number: jerseyNumber, position })
        .eq("id", editingId);

      if (updateErr) {
        setError(updateErr.message);
        setLoading(false);
        return;
      }

      setAthletes((prev) =>
        prev.map((a) =>
          a.id === editingId ? { ...a, name, jersey_number: jerseyNumber, position } : a
        )
      );
    } else {
      // Insert
      const { data, error: insertErr } = await supabase
        .from("athletes")
        .insert({ team_id: teamId, name, jersey_number: jerseyNumber, position })
        .select()
        .single();

      if (insertErr) {
        setError(insertErr.message);
        setLoading(false);
        return;
      }

      if (data) setAthletes((prev) => [...prev, data]);
    }

    setLoading(false);
    resetForm();
    router.refresh();
  }

  async function handleDelete(id: string) {
    if (!confirm("Remove this athlete from the roster?")) return;

    const supabase = createClient();
    const { error: delErr } = await supabase
      .from("athletes")
      .update({ active: false })
      .eq("id", id);

    if (delErr) {
      alert("Error removing: " + delErr.message);
      return;
    }

    setAthletes((prev) => prev.filter((a) => a.id !== id));
    router.refresh();
  }

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Roster</h1>
          <p className="text-sm text-gray-500">
            {athletes.filter((a) => a.active).length} active athletes
          </p>
        </div>
        {!showForm && (
          <Button onClick={() => setShowForm(true)}>+ Add Athlete</Button>
        )}
      </div>

      {/* Add/Edit Form */}
      {showForm && (
        <Card className="mb-6">
          <h2 className="mb-4 text-lg font-semibold">
            {editingId ? "Edit Athlete" : "Add Athlete"}
          </h2>
          <form onSubmit={handleSubmit} className="space-y-3">
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <Input
                id="name"
                label="Name"
                placeholder="Jane Doe"
                value={name}
                onChange={(e) => setName(e.target.value)}
                required
              />
              <Input
                id="jerseyNumber"
                label="Jersey #"
                placeholder="12"
                value={jerseyNumber}
                onChange={(e) => setJerseyNumber(e.target.value)}
              />
              <Input
                id="position"
                label="Position"
                placeholder="Midfielder"
                value={position}
                onChange={(e) => setPosition(e.target.value)}
              />
            </div>
            {error && (
              <p className="text-sm text-red-600">{error}</p>
            )}
            <div className="flex gap-2">
              <Button type="submit" disabled={loading}>
                {loading ? "Saving..." : editingId ? "Update" : "Add"}
              </Button>
              <Button type="button" variant="ghost" onClick={resetForm}>
                Cancel
              </Button>
            </div>
          </form>
        </Card>
      )}

      {/* Athlete list */}
      {athletes.filter((a) => a.active).length === 0 ? (
        <Card className="py-12 text-center">
          <p className="text-gray-500">No athletes yet.</p>
          <p className="mt-2 text-sm text-gray-400">
            Add your first athlete to get started.
          </p>
        </Card>
      ) : (
        <div className="space-y-2">
          {athletes
            .filter((a) => a.active)
            .map((athlete) => (
              <Card key={athlete.id} className="flex items-center gap-4">
                <div className="flex h-10 w-10 items-center justify-center rounded-full bg-brand/10 text-sm font-bold text-brand">
                  #{athlete.jersey_number || "—"}
                </div>
                <div className="flex-1">
                  <p className="font-semibold text-gray-900">{athlete.name}</p>
                  <p className="text-xs text-gray-500">
                    {athlete.position || "No position"}
                  </p>
                </div>
                <div className="flex gap-1">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => startEdit(athlete)}
                  >
                    Edit
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="text-red-600 hover:text-red-700"
                    onClick={() => handleDelete(athlete.id)}
                  >
                    Remove
                  </Button>
                </div>
              </Card>
            ))}
        </div>
      )}
    </div>
  );
}
