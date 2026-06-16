import { NextRequest, NextResponse } from "next/server";
import { lookupISBN } from "@/lib/isbn-lookup";
import { resolveCollection, getCollections } from "@/lib/db";
import { ScanResult, Collection } from "@/types";

function matchCollection(title: string, collections: Collection[]): Collection | null {
  const t = title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  for (const col of collections) {
    const colName = col.name.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    if (t.includes(colName) || colName.includes(t)) return col;
    const words = colName.split(/\s+/).filter(w => w.length >= 3);
    if (words.length > 0 && words.every(w => t.includes(w))) return col;
  }
  return null;
}

async function searchCover(title: string): Promise<string | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";
  try {
    const exactQuery = `"${title}"`;
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:${encodeURIComponent(exactQuery)}&langRestrict=fr&maxResults=5${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.items?.length) return null;

    const titleLower = title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    const titleWords = titleLower.split(/\s+/).filter(w => w.length >= 3);

    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.imageLinks) continue;
      const volTitle = (vol.title ?? "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      const matchCount = titleWords.filter(w => volTitle.includes(w)).length;
      if (matchCount < titleWords.length * 0.6) continue;

      let url = vol.imageLinks.large ?? vol.imageLinks.medium ?? vol.imageLinks.thumbnail;
      if (url) url = url.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");
      return url ?? null;
    }
    return null;
  } catch { return null; }
}

export async function GET(req: NextRequest) {
  const isbn        = req.nextUrl.searchParams.get("isbn");
  const library_id  = req.nextUrl.searchParams.get("library_id");
  const series_name = req.nextUrl.searchParams.get("series_name");
  const series_idx  = req.nextUrl.searchParams.get("series_index");

  if (!isbn)       return NextResponse.json({ error: "isbn manquant" },       { status: 400 });
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });

  // Manual series override
  if (series_name && series_idx) {
    try {
      const { collection, isNew, isNewVolume } = await resolveCollection(
        library_id, series_name, parseInt(series_idx), { book_type: "bd" }
      );
      return NextResponse.json({
        book: { isbn, title: "", authors: [], book_type: "bd" },
        collection, isNewCollection: isNew, isNewVolume,
      } satisfies ScanResult);
    } catch (e: any) {
      return NextResponse.json({ error: e.message }, { status: 500 });
    }
  }

  const book = await lookupISBN(isbn);
  if (!book) return NextResponse.json({ error: "Livre introuvable" }, { status: 404 });

  // Auto-search cover if missing — use exact title matching
  if (!book.cover_url && book.title) {
    const cover = await searchCover(book.title);
    if (cover) book.cover_url = cover;
  }

  // Auto-resolve collection
  const isSeries = (book.book_type === "bd" || book.book_type === "manga")
    && book.series_name && book.series_index !== undefined;

  if (isSeries) {
    try {
      const { collection, isNew, isNewVolume } = await resolveCollection(
        library_id, book.series_name!, book.series_index!,
        { cover_url: book.cover_url, author: book.authors[0], book_type: book.book_type }
      );
      return NextResponse.json({ book, collection, isNewCollection: isNew, isNewVolume } satisfies ScanResult);
    } catch (e: any) {
      console.error("resolveCollection:", e);
    }
  } else if (book.book_type === "bd" || book.book_type === "manga") {
    try {
      const existingCollections = await getCollections(library_id);
      const matched = matchCollection(book.title, existingCollections);
      if (matched) {
        return NextResponse.json({
          book: { ...book, series_name: matched.name },
          collection: matched, isNewCollection: false, isNewVolume: false,
        } satisfies ScanResult);
      }
    } catch (e: any) {
      console.error("matchCollection:", e);
    }
  }

  return NextResponse.json({ book, isNewCollection: false, isNewVolume: false } satisfies ScanResult);
}
