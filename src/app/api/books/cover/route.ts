import { NextRequest, NextResponse } from "next/server";
import { searchCoverByTitle } from "@/lib/cover-utils";

export async function GET(req: NextRequest) {
  const title     = req.nextUrl.searchParams.get("title");
  const seriesName = req.nextUrl.searchParams.get("series") ?? undefined;
  if (!title) return NextResponse.json({ cover_url: null });

  const cover = await searchCoverByTitle(title, seriesName);
  return NextResponse.json({ cover_url: cover ?? null });
}
