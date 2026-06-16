import { NextRequest, NextResponse } from "next/server";
import { resolveUser } from "@/lib/auth";

export async function GET(req: NextRequest) {
  const email = req.nextUrl.searchParams.get("email");
  if (!email) return NextResponse.json({ error: "email manquant" }, { status: 400 });
  const ctx = await resolveUser(email);
  if (!ctx) return NextResponse.json({ error: "Impossible de créer le profil" }, { status: 500 });
  return NextResponse.json({ id: ctx.library_id, profile_id: ctx.profile_id });
}

