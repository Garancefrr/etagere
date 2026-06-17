import { NextRequest, NextResponse } from "next/server";
import { lookupISBN } from "@/lib/isbn-lookup";
import { getCollections, findCollection } from "@/lib/db";
import { ScanResult, Collection } from "@/types";

// Guess series name by searching Google Books for related volumes
async function guessSeriesFromTitle(title: string): Promise<string | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  // Try progressively shorter prefixes of the title
  const words = title.split(/\s+/);
  for (let len = Math.min(words.length, 4); len >= 2; len--) {
    const prefix = words.slice(0, len).join(" ");
    try {
      const res = await fetch(
        `https://www.googleapis.com/books/v1/volumes?q=intitle:"${encodeURIComponent(prefix)}"+Tome&langRestrict=fr&maxResults=3${keyParam}`,
        { signal: AbortSignal.timeout(4000) }
      );
      if (!res.ok) continue;
      const data = await res.json();
      if (!data.items?.length) continue;

      // Look for "Series - Tome X" pattern in results
      for (const item of data.items) {
        const t = item.volumeInfo?.title ?? "";
        const match = t.match(/^(.+?)\s*[-–—]\s*(?:tome|t\.?|vol)\s*\d+/i);
        if (match) {
          return match[1].trim();
        }
      }
    } catch { continue; }
  }
  return null;
}

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
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:${encodeURIComponent(`"${title}"`)}&langRestrict=fr&maxResults=5${keyParam}`,
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
      if (titleWords.filter(w => volTitle.includes(w)).length < titleWords.length * 0.6) continue;
      let url = vol.imageLinks.large ?? vol.imageLinks.medium ?? vol.imageLinks.thumbnail;
      if (url) url = url.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");
      return url ?? null;
    }
    return null;
  } catch { return null; }
}

export async function GET(req: NextRequest) {
  const isbn       = req.nextUrl.searchParams.get("isbn");
  const library_id = req.nextUrl.searchParams.get("library_id");

  if (!isbn)       return NextResponse.json({ error: "isbn manquant" },       { status: 400 });
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });

  const book = await lookupISBN(isbn);
  if (!book) return NextResponse.json({ error: "Livre introuvable" }, { status: 404 });

  // Auto-search cover if missing
  if (!book.cover_url && book.title) {
    const cover = await searchCover(book.title);
    if (cover) book.cover_url = cover;
  }

  // SUGGEST collection — never create here
  // Creation only happens via /api/collections/resolve (called from Scanner on save)
  const isSeries = (book.book_type === "bd" || book.book_type === "manga")
    && book.series_name && book.series_index !== undefined;

  if (isSeries) {
    // Check if collection already exists (without creating it)
    const existing = await findCollection(library_id, book.series_name!);
    if (existing) {
      return NextResponse.json({
        book, collection: existing,
        isNewCollection: false,
        isNewVolume: !existing.owned_volumes.includes(book.series_index!),
      } satisfies ScanResult);
    }
    // Series detected but no collection yet — return suggestion without creating
    return NextResponse.json({
      book, isNewCollection: false, isNewVolume: false,
    } satisfies ScanResult);
  }

  // BD/manga without series — try fuzzy match existing collections
  if (book.book_type === "bd" || book.book_type === "manga") {
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

    // No existing collection — try to guess series name from Google Books
    if (!book.series_name) {
      const guessed = await guessSeriesFromTitle(book.title);
      if (guessed) {
        book.series_name = guessed;
      }
    }
  }

  return NextResponse.json({ book, isNewCollection: false, isNewVolume: false } satisfies ScanResult);
}
