import { NextRequest, NextResponse } from "next/server";
import { getCollections, insertCollection } from "@/lib/db";
import { Collection } from "@/types";

export async function GET(req: NextRequest) {
  const library_id = req.nextUrl.searchParams.get("library_id");
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
  try {
    return NextResponse.json(await getCollections(library_id));
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as Omit<Collection, "id" | "created_at" | "updated_at">;
    if (!body.library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
    return NextResponse.json(await insertCollection(body));
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

