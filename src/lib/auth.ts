/**
 * Server-side auth utilities.
 * Resolves NextAuth email → Supabase profile_id + library_id.
 * Auto-creates profile and library on first login.
 */
import { createServerClient } from "@/lib/supabase";

export interface UserContext {
  profile_id: string;
  library_id: string;
  email: string;
}

export async function resolveUser(email: string): Promise<UserContext | null> {
  if (!email) return null;
  const db = createServerClient();

  // 1. Find or create profile
  let { data: profile } = await db
    .from("profiles")
    .select("id")
    .eq("email", email)
    .maybeSingle();

  if (!profile) {
    const { data } = await db
      .from("profiles")
      .insert({ id: crypto.randomUUID(), email, name: email.split("@")[0] })
      .select("id")
      .single();
    profile = data;
  }

  if (!profile) return null;

  // 2. Find or create library
  let { data: library } = await db
    .from("libraries")
    .select("id")
    .eq("owner_id", profile.id)
    .maybeSingle();

  if (!library) {
    const { data } = await db
      .from("libraries")
      .insert({ owner_id: profile.id, name: "Ma Bibliothèque" })
      .select("id")
      .single();
    library = data;
  }

  if (!library) return null;

  return { profile_id: profile.id, library_id: library.id, email };
}

export async function getProfileId(email: string): Promise<string | null> {
  if (!email) return null;
  const db = createServerClient();
  const { data } = await db
    .from("profiles")
    .select("id")
    .eq("email", email)
    .maybeSingle();
  return data?.id ?? null;
}

