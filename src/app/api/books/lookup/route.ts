import { NextRequest, NextResponse } from "next/server";
import { lookupISBN } from "@/lib/isbn-lookup";
import { resolveCollection } from "@/lib/data";
import { ScanResult } from "@/types";

export async function GET(req: NextRequest) {
  const isbn       = req.nextUrl.searchParams.get("isbn");
  const libraryId  = req.nextUrl.searchParams.get("library_id") ?? "lib1";
  if (!isbn) return NextResponse.json({ error: "ISBN manquant" }, { status: 400 });

  const book = await lookupISBN(isbn);
  if (!book) return NextResponse.json({ error: "Livre introuvable" }, { status: 404 });

  const isSeriesType = book.book_type === "bd" || book.book_type === "manga";
  if (book.series_name && book.series_index !== undefined && isSeriesType) {
    const { collection, isNew, isNewVolume } = resolveCollection(libraryId, book.series_name, book.series_index, book.cover_url, book.authors[0], book.book_type);
    const result: ScanResult = { book, collection, isNewCollection: isNew, isNewVolume };
    return NextResponse.json(result);
  }

  return NextResponse.json({ book, isNewCollection: false, isNewVolume: false } satisfies ScanResult);
}
