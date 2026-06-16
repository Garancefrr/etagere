import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { createShare, getShareByToken, registerViewer } from "@/lib/db";

export async function POST(req: NextRequest) {
  const { collection_id, profile_id } = await req.json();
  if (!collection_id || !profile_id)
    return NextResponse.json({ error: "Paramètres manquants" }, { status: 400 });
  try {
    const token = await createShare(collection_id, profile_id);
    return NextResponse.json({ token });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function GET(req: NextRequest) {
  const token        = req.nextUrl.searchParams.get("token");
  const viewer_email = req.nextUrl.searchParams.get("viewer_email");
  if (!token) return NextResponse.json({ error: "Token manquant" }, { status: 400 });
  try {
    const share = await getShareByToken(token);
    if (!share) return NextResponse.json({ error: "Lien invalide ou expiré" }, { status: 404 });
    if (viewer_email) {
      const viewer_id = await getProfileId(viewer_email);
      if (viewer_id) await registerViewer(share.id, viewer_id);
    }
    return NextResponse.json(share);
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

