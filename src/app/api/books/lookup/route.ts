import { NextRequest, NextResponse } from "next/server";
import { lookupISBN } from "@/lib/isbn-lookup";
import { resolveCollection } from "@/lib/collection-service";

export async function GET(req: NextRequest) {
  const isbn = req.nextUrl.searchParams.get("isbn");
  const library_id = req.nextUrl.searchParams.get("library_id") ?? "lib1";
  if (!isbn) return NextResponse.json({ error: "ISBN manquant" }, { status: 400 });

  const book = await lookupISBN(isbn);
  if (!book) return NextResponse.json({ error: "Livre introuvable" }, { status: 404 });

  const scanResult = resolveCollection(book, library_id);
  return NextResponse.json(scanResult);
}
