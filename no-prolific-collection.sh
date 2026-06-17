#!/bin/bash
set -e
echo "🔧 Fix — auteur prolifique sans saga = pas de collection..."
cd "$(git rev-parse --show-toplevel)"
cat > src/app/api/books/lookup/route.ts << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { lookupISBN } from "@/lib/isbn-lookup";
import { getCollections, findCollection } from "@/lib/db";
import { ScanResult, Collection } from "@/types";

// Check if an author has a saga or is prolific (> 2 books)
async function checkAuthor(author: string): Promise<{ sagaName: string | null; bookCount: number }> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";
  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=inauthor:"${encodeURIComponent(author)}"&langRestrict=fr&maxResults=10${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return { sagaName: null, bookCount: 0 };
    const data = await res.json();
    const total = data.totalItems ?? 0;
    if (!data.items?.length) return { sagaName: null, bookCount: total };

    // Look for a saga (seriesInfo or "Tome X" pattern)
    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.title) continue;
      // Check seriesInfo
      if (vol.seriesInfo?.bookDisplayNumber) {
        const match = vol.title.match(/^(.+?)\s*[-–—]\s*(?:tome|t\.?|vol)\s*\d+/i);
        if (match) return { sagaName: match[1].trim(), bookCount: total };
      }
      // Check title pattern
      const tomeMatch = vol.title.match(/^(.+?)\s*[-–—,]\s*(?:tome|t\.?|vol(?:ume)?\.?|livre|#)\s*(\d+)/i);
      if (tomeMatch) return { sagaName: tomeMatch[1].trim(), bookCount: total };
    }

    return { sagaName: null, bookCount: total };
  } catch {
    return { sagaName: null, bookCount: 0 };
  }
}

// Guess series name by searching Google Books for related volumes
async function guessSeriesFromTitle(title: string): Promise<string | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  // Build search candidates: prefixes, suffixes, and distinctive words
  const words = title.split(/\s+/).filter(w => w.length >= 2);
  const stopWords = new Set(["le","la","les","un","une","des","de","du","et","au","aux","en","l'","d'"]);
  const candidates = new Set<string>();

  // Prefixes (first N words)
  for (let len = Math.min(words.length, 4); len >= 2; len--) {
    candidates.add(words.slice(0, len).join(" "));
  }
  // Suffixes (last N words)
  for (let len = Math.min(words.length, 3); len >= 1; len--) {
    candidates.add(words.slice(-len).join(" "));
  }
  // Individual distinctive words (5+ chars, not stop words)
  for (const w of words) {
    const clean = w.toLowerCase().replace(/^[l'd]+/i, "");
    if (clean.length >= 5 && !stopWords.has(w.toLowerCase())) {
      candidates.add(w);
    }
  }

  for (const candidate of Array.from(candidates)) {
    try {
      const res = await fetch(
        `https://www.googleapis.com/books/v1/volumes?q=intitle:"${encodeURIComponent(candidate)}"+Tome&langRestrict=fr&maxResults=5${keyParam}`,
        { signal: AbortSignal.timeout(4000) }
      );
      if (!res.ok) continue;
      const data = await res.json();
      if (!data.items?.length) continue;

      for (const item of data.items) {
        const t = item.volumeInfo?.title ?? "";
        const match = t.match(/^(.+?)\s*[-–—]\s*(?:tome|t\.?|vol)\s*\d+/i);
        if (match) return match[1].trim();
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

  // ── Collection / Series suggestion ──────────────────────────────────────────
  // Never create collections here — only suggest. Creation via /api/collections/resolve.

  const existingCollections = await getCollections(library_id).catch(() => [] as Collection[]);

  // 1. Series already detected (from API) — works for all types
  if (book.series_name && book.series_index !== undefined) {
    const existing = await findCollection(library_id, book.series_name);
    if (existing) {
      return NextResponse.json({
        book, collection: existing,
        isNewCollection: false,
        isNewVolume: !existing.owned_volumes.includes(book.series_index),
      } satisfies ScanResult);
    }
    return NextResponse.json({ book, isNewCollection: false, isNewVolume: false } satisfies ScanResult);
  }

  // 2. Fuzzy match title against existing collections (all types)
  const matched = matchCollection(book.title, existingCollections);
  if (matched) {
    return NextResponse.json({
      book: { ...book, series_name: matched.name },
      collection: matched, isNewCollection: false, isNewVolume: false,
    } satisfies ScanResult);
  }

  // 3. BD/manga: guess series from Google Books
  if ((book.book_type === "bd" || book.book_type === "manga") && !book.series_name) {
    const guessed = await guessSeriesFromTitle(book.title);
    if (guessed) book.series_name = guessed;
  }

  // 4. Livre: only create collection for explicit sagas (numbered series)
  // Never create collection just because author has written many books
  if (book.book_type === "livre" && !book.series_name && book.authors.length > 0) {
    const authorInfo = await checkAuthor(book.authors[0]);
    if (authorInfo.sagaName) {
      // Explicit saga with numbered volumes detected
      book.series_name = authorInfo.sagaName;
      book._createCollection = true;
    }
    // Prolific author without saga → no collection, simple library add
  }

  // For BD/manga: always create collection if series detected
  if ((book.book_type === "bd" || book.book_type === "manga") && book.series_name) {
    book._createCollection = true;
  }

  return NextResponse.json({ book, isNewCollection: false, isNewVolume: false } satisfies ScanResult);
}
FILEOF
git add -A
git commit -m "fix: no collection for prolific authors, only for explicit numbered sagas"
git push
echo "🎉 Déployé !"
