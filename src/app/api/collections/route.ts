import { NextRequest, NextResponse } from "next/server";
import { getCollections } from "@/lib/db";

export async function GET(req: NextRequest) {
  const libraryId = req.nextUrl.searchParams.get("library_id");
  if (!libraryId) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
  const collections = await getCollections(libraryId);
  return NextResponse.json(collections);
}
