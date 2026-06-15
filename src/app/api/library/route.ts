import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const email = req.nextUrl.searchParams.get("email");
  if (!email) return NextResponse.json({ error: "email manquant" }, { status: 400 });

  const db = createServerClient();

  // Find or create profile by email
  let { data: profile } = await db
    .from("profiles").select("id").eq("email", email).maybeSingle();

  if (!profile) {
    const { data: newProfile } = await db
      .from("profiles")
      .insert({ id: crypto.randomUUID(), email, name: email.split("@")[0] })
      .select("id").single();
    profile = newProfile;
  }

  if (!profile) return NextResponse.json({ error: "Profil introuvable" }, { status: 404 });

  // Find or create library
  let { data: library } = await db
    .from("libraries").select("id").eq("owner_id", profile.id).maybeSingle();

  if (!library) {
    const { data: newLib } = await db
      .from("libraries")
      .insert({ owner_id: profile.id, name: "Ma Bibliothèque" })
      .select("id").single();
    library = newLib;
  }

  if (!library) return NextResponse.json({ error: "Bibliothèque introuvable" }, { status: 404 });
  return NextResponse.json({ id: library.id, profile_id: profile.id });
}
