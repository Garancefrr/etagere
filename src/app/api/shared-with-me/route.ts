import { NextRequest, NextResponse } from "next/server";
import { getSharedWithMe } from "@/lib/db";

export async function GET(req: NextRequest) {
  const viewer_id = req.nextUrl.searchParams.get("viewer_id");
  if (!viewer_id) return NextResponse.json({ error: "viewer_id manquant" }, { status: 400 });
  const shared = await getSharedWithMe(viewer_id);
  return NextResponse.json(shared);
}
