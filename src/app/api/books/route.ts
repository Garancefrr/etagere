import { NextRequest, NextResponse } from "next/server";
import { getBooks, patchBook, removeBook } from "@/lib/db";

export async function GET(req: NextRequest) {
  const library_id = req.nextUrl.searchParams.get("library_id");
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
  try {
    return NextResponse.json(await getBooks(library_id));
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function PATCH(req: NextRequest) {
  const { id, ...updates } = await req.json();
  await patchBook(id, updates);
  return NextResponse.json({ ok: true });
}

export async function DELETE(req: NextRequest) {
  const { id } = await req.json();
  await removeBook(id);
  return NextResponse.json({ ok: true });
}

