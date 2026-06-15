import { NextRequest, NextResponse } from "next/server";
import { lookupISBN } from "@/lib/isbn-lookup";
import { resolveCollection } from "@/lib/db";
import { ScanResult } from "@/types";

export async function GET(req: NextRequest) {
  const isbn      = req.nextUrl.searchParams.get("isbn");
  const libraryId = req.nextUrl.searchParams.get("library_id");

  if (!isbn)      return NextResponse.json({ error: "ISBN manquant" },        { status: 400 });
  if (!libraryId) return NextResponse.json({ error: "library_id manquant" },  { status: 400 });

  const book = await lookupISBN(isbn);
  if (!book) return NextResponse.json({ error: "Livre introuvable" }, { status: 404 });

  // Auto-resolve collection for BD and manga with series info
  const isSeriesType = book.book_type === "bd" || book.book_type === "manga";
  if (book.series_name && book.series_index !== undefined && isSeriesType) {
    try {
      const { collection, isNew, isNewVolume } = await resolveCollection(
        libraryId,
        book.series_name,
        book.series_index,
        { cover_url: book.cover_url, author: book.authors[0], book_type: book.book_type }
      );
      return NextResponse.json({
        book,
        collection,
        isNewCollection: isNew,
        isNewVolume,
      } satisfies ScanResult);
    } catch (e) {
      console.error("Collection resolve error:", e);
    }
  }

  return NextResponse.json({ book, isNewCollection: false, isNewVolume: false } satisfies ScanResult);
}
