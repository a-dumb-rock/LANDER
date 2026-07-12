import { createClient } from "@/lib/supabase/server";
import { CaptureFlow } from "@/components/CaptureFlow";

export default async function CapturePage() {
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

  if (!profile?.team_id) {
    return <p className="text-gray-500">No team found.</p>;
  }

  const { data: athletes } = await supabase
    .from("athletes")
    .select("*")
    .eq("team_id", profile.team_id)
    .eq("active", true)
    .order("jersey_number");

  return (
    <CaptureFlow
      athletes={athletes ?? []}
      teamId={profile.team_id}
      userId={user.id}
    />
  );
}
