import { NextRequest, NextResponse } from "next/server";
import { getBooks, patchBook, removeBook } from "@/lib/db";

export async function GET(req: NextRequest) {
  const libraryId = req.nextUrl.searchParams.get("library_id");
  if (!libraryId) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
  const books = await getBooks(libraryId);
  return NextResponse.json(books);
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
