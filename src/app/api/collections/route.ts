import { NextRequest, NextResponse } from "next/server";
import { getCollections } from "@/lib/data";

export async function GET(req: NextRequest) {
  const libraryId = req.nextUrl.searchParams.get("library_id") ?? "lib1";
  return NextResponse.json(getCollections(libraryId));
}
