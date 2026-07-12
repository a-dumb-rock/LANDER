"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Input";
import Link from "next/link";

export default function SignupPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [teamName, setTeamName] = useState("");
  const [role, setRole] = useState<"trainer" | "coach">("trainer");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  async function handleSignup(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);

    const supabase = createClient();

    // 1. Sign up the user
    const { data: authData, error: signUpError } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { full_name: fullName },
      },
    });

    if (signUpError) {
      setError(signUpError.message);
      setLoading(false);
      return;
    }

    if (!authData.user) {
      setError("Signup succeeded but no user returned.");
      setLoading(false);
      return;
    }

    // 2. Create the team
    const { data: team, error: teamError } = await supabase
      .from("teams")
      .insert({ name: teamName || `${fullName}'s Team` })
      .select()
      .single();

    if (teamError) {
      setError("Account created but failed to create team: " + teamError.message);
      setLoading(false);
      return;
    }

    // 3. Link user profile to the team
    const { error: profileError } = await supabase
      .from("profiles")
      .update({ team_id: team.id, role })
      .eq("id", authData.user.id);

    if (profileError) {
      setError("Account created but failed to link team: " + profileError.message);
      setLoading(false);
      return;
    }

    router.push("/");
    router.refresh();
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface px-4">
      <div className="w-full max-w-md">
        {/* Brand */}
        <div className="mb-8 text-center">
          <div className="mb-2 text-3xl font-bold text-brand">LANDER</div>
          <h1 className="text-xl font-semibold text-gray-900">
            Create your account
          </h1>
          <p className="mt-1 text-sm text-gray-500">
            Set up your team and start monitoring knee readiness.
          </p>
        </div>

        {/* Form */}
        <form
          onSubmit={handleSignup}
          className="space-y-4 rounded-lg border border-surface-border bg-surface-card p-6 shadow-sm"
        >
          <Input
            id="fullName"
            label="Your name"
            placeholder="Jane Smith"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            required
          />
          <Input
            id="teamName"
            label="Team name"
            placeholder="e.g. Wildcats Women's Soccer"
            value={teamName}
            onChange={(e) => setTeamName(e.target.value)}
            required
          />
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">
              Your role
            </label>
            <div className="flex gap-4">
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="radio"
                  name="role"
                  value="trainer"
                  checked={role === "trainer"}
                  onChange={() => setRole("trainer")}
                  className="accent-brand"
                />
                Athletic Trainer
              </label>
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="radio"
                  name="role"
                  value="coach"
                  checked={role === "coach"}
                  onChange={() => setRole("coach")}
                  className="accent-brand"
                />
                Coach
              </label>
            </div>
          </div>
          <Input
            id="email"
            label="Email"
            type="email"
            placeholder="you@team.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
          <Input
            id="password"
            label="Password"
            type="password"
            placeholder="At least 6 characters"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={6}
          />

          {error && (
            <p className="rounded-md bg-red-50 p-3 text-sm text-red-700">
              {error}
            </p>
          )}

          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? "Creating account..." : "Create account & team"}
          </Button>
        </form>

        <p className="mt-4 text-center text-sm text-gray-500">
          Already have an account?{" "}
          <Link href="/login" className="font-medium text-brand hover:underline">
            Sign in
          </Link>
        </p>
      </div>
    </div>
  );
}
