import { NextRequest, NextResponse } from "next/server";
import { getLibraryId } from "@/lib/db";

export async function GET(req: NextRequest) {
  const userId = req.nextUrl.searchParams.get("user_id");
  if (!userId) return NextResponse.json({ error: "user_id manquant" }, { status: 400 });
  try {
    const id = await getLibraryId(userId);
    return NextResponse.json({ id });
  } catch {
    return NextResponse.json({ error: "Bibliothèque introuvable" }, { status: 404 });
  }
}
