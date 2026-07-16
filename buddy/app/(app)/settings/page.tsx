import { createClient } from "@/lib/supabase/server";
import { SettingsForm } from "@/components/SettingsForm";
import { DEFAULT_THRESHOLDS } from "@/lib/engine/delta";
import type { Thresholds } from "@/lib/types/database";

export default async function SettingsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("team_id, role, full_name")
    .eq("id", user.id)
    .single();

  if (!profile?.team_id) return <p>No team found.</p>;

  const { data: team } = await supabase
    .from("teams")
    .select("*")
    .eq("id", profile.team_id)
    .single();

  const thresholds: Thresholds =
    (team?.thresholds as Thresholds) ?? DEFAULT_THRESHOLDS;

  return (
    <SettingsForm
      team={team!}
      thresholds={thresholds}
      profile={profile}
    />
  );
}
