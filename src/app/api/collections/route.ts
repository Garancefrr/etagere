import { NextRequest, NextResponse } from "next/server";
import { getCollections } from "@/lib/collection-service";

export async function GET(req: NextRequest) {
  const library_id = req.nextUrl.searchParams.get("library_id") ?? "lib1";
  return NextResponse.json(getCollections(library_id));
}
