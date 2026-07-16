import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { AppShell } from "@/components/AppShell";

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // Get profile and team
  const { data: profile } = await supabase
    .from("profiles")
    .select("*, teams(*)")
    .eq("id", user.id)
    .single();

  return (
    <AppShell
      user={user}
      profile={profile}
      teamName={profile?.teams?.name ?? "My Team"}
    >
      {children}
    </AppShell>
  );
}
