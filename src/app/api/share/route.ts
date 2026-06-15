import { NextRequest, NextResponse } from "next/server";
import { createShare, getShareByToken, registerViewer } from "@/lib/db";

// POST /api/share — create a share link for a collection
export async function POST(req: NextRequest) {
  const { collection_id, owner_id } = await req.json();
  if (!collection_id || !owner_id)
    return NextResponse.json({ error: "Paramètres manquants" }, { status: 400 });
  try {
    const token = await createShare(collection_id, owner_id);
    return NextResponse.json({ token });
  } catch (e) {
    console.error(e);
    return NextResponse.json({ error: "Erreur création du partage" }, { status: 500 });
  }
}

// GET /api/share?token=xxx — get shared collection data
export async function GET(req: NextRequest) {
  const token    = req.nextUrl.searchParams.get("token");
  const viewer_id = req.nextUrl.searchParams.get("viewer_id");
  if (!token) return NextResponse.json({ error: "Token manquant" }, { status: 400 });
  try {
    const share = await getShareByToken(token);
    if (!share) return NextResponse.json({ error: "Lien invalide ou expiré" }, { status: 404 });
    // Register viewer if logged in
    if (viewer_id) await registerViewer(share.id, viewer_id);
    return NextResponse.json(share);
  } catch (e) {
    console.error(e);
    return NextResponse.json({ error: "Erreur" }, { status: 500 });
  }
}
