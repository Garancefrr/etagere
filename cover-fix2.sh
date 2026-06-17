#!/bin/bash
set -e
echo "🖼️ Fix couvertures — validation + fallback si image indisponible..."
cd "$(git rev-parse --show-toplevel)"
mkdir -p src/lib
cat > "src/lib/cover-utils.ts" << 'FILEOF'
/**
 * Validates and cleans a cover URL.
 * Returns null if the URL likely points to a placeholder/unavailable image.
 */
export async function validateCoverUrl(url: string | undefined | null): Promise<string | null> {
  if (!url) return null;

  // Clean the URL
  let clean = url
    .replace("http:", "https:")
    .replace("&edge=curl", "")
    .replace(/zoom=\d/, "zoom=1");

  // Known placeholder patterns to reject
  const PLACEHOLDER_PATTERNS = [
    "no_cover",
    "nocover",
    "image_not_available",
    "no-image",
    "default_cover",
    "notoile=1",  // BnF no-image flag
  ];

  if (PLACEHOLDER_PATTERNS.some(p => clean.toLowerCase().includes(p))) return null;

  // For Google Books, try fetching to check if image is real
  if (clean.includes("books.google.com")) {
    try {
      const res = await fetch(clean, { method: "HEAD", signal: AbortSignal.timeout(3000) });
      // Google returns 200 even for "Image not available" but with small content-length
      const size = res.headers.get("content-length");
      if (size && parseInt(size) < 2000) return null; // too small = placeholder
      if (!res.ok) return null;
      return clean;
    } catch { return null; }
  }

  return clean;
}

/**
 * Searches Google Books for a cover by exact title.
 */
export async function searchCoverByTitle(title: string, seriesName?: string): Promise<string | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";
  const q = seriesName ? `${seriesName} ${title}` : title;

  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:${encodeURIComponent(`"${q}"`)}&langRestrict=fr&maxResults=5${keyParam}`,
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
      if (!url) continue;
      url = url.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");

      const validated = await validateCoverUrl(url);
      if (validated) return validated;
    }
    return null;
  } catch { return null; }
}
FILEOF
cat > "src/lib/isbn-lookup.ts" << 'FILEOF'
import { validateCoverUrl } from "@/lib/cover-utils";
import { LookupResult, BookType } from "@/types";

function detectType(terms: string): BookType {
  const t = terms.toLowerCase();
  if (/manga|manhwa|shonen|shojo|seinen|josei|kodansha|shueisha|viz|one.piece|naruto|dragon.ball/.test(t)) return "manga";
  if (/bande.dessin|bd|comics|dargaud|dupuis|lombard|casterman|lucky|schtroumpf|ast[eé]rix|tintin|spirou|blake|mortimer|franco.belge/.test(t)) return "bd";
  return "livre";
}

function extractSeries(title: string): { seriesName?: string; seriesIndex?: number } {
  const patterns = [
    /^(.+?)\s*[-–—]\s*(?:tome|t\.?|vol(?:ume)?\.?|#)\s*(\d+)/i,
    /^(.+?)\s*,\s*(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i,
    /^(.+?)\s+(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i,
    /^(.+?)\s*\((?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)\)/i,
  ];
  for (const re of patterns) {
    const m = title.match(re);
    if (m && parseInt(m[2]) <= 200) {
      return { seriesName: m[1].replace(/\s+$/, "").trim() || undefined, seriesIndex: parseInt(m[2]) };
    }
  }
  return {};
}

// ISBN = 978/979 (13 digits) or 10 digits
// ── Google Books ──────────────────────────────────────────────────────────────

async function fromGoogleBooks(code: string): Promise<LookupResult | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";
  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=isbn:${code}${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) { console.error("Google Books error:", res.status); return null; }
    const data = await res.json();
    const vol = data.items?.[0]?.volumeInfo;
    if (!vol?.title) return null;

    const categories = (vol.categories ?? []).join(" ").toLowerCase();
    const rawTitle   = vol.title ?? "";
    // Clean title: take first part before ";" (multi-story compilations)
    const cleanTitle = rawTitle.includes(";") ? rawTitle.split(";")[0].trim() : rawTitle;
    const fullTitle  = `${cleanTitle} ${vol.subtitle ?? ""}`.trim();

    let seriesName: string | undefined;
    let seriesIndex: number | undefined;
    const seriesInfo = data.items?.[0]?.volumeInfo?.seriesInfo;
    if (seriesInfo?.bookDisplayNumber) seriesIndex = parseInt(seriesInfo.bookDisplayNumber);

    // Try extracting series from "Series - Tome X - Title" pattern
    const parsed = extractSeries(fullTitle);
    seriesName  = parsed.seriesName ?? seriesName;
    seriesIndex = seriesIndex ?? parsed.seriesIndex;

    // If no series detected but it looks like a BD, try to extract series name
    // from the title pattern "Les X something" → series "Les X"
    if (!seriesName && seriesIndex) {
      // We have a volume number from seriesInfo but no name
      // Use the main title words as series name
      seriesName = cleanTitle.replace(/\s*[-–—].*$/, "").trim() || undefined;
    }

    let rawCover = vol.imageLinks?.extraLarge ?? vol.imageLinks?.large ?? vol.imageLinks?.medium ?? vol.imageLinks?.thumbnail;
    if (rawCover) rawCover = rawCover.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");
    const coverUrl = await validateCoverUrl(rawCover);

    return {
      isbn: code, title: cleanTitle, authors: vol.authors ?? [],
      cover_url: coverUrl ?? undefined, publisher: vol.publisher,
      published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : undefined,
      page_count: vol.pageCount, description: vol.description,
      series_name: seriesName, series_index: seriesIndex,
      book_type: detectType(categories + " " + fullTitle + " " + (vol.publisher ?? "")),
    };
  } catch { return null; }
}

// ── BnF SRU API ───────────────────────────────────────────────────────────────

async function fromBnF(code: string): Promise<LookupResult | null> {
  try {
    for (const field of ["bib.ean", "bib.isbn"]) {
      const url = `https://catalogue.bnf.fr/api/SRU?version=1.2&operation=searchRetrieve&query=${field}+adj+"${code}"&recordSchema=unimarcxchange&maximumRecords=1`;
      const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
      const text = await res.text();
      if (text.includes("<numberOfRecords>0")) continue;

      const titleA   = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
      const titleE   = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="e">([^<]+)/)?.[1]?.trim();
      if (!titleA) continue;
      const title    = titleE ? `${titleA} — ${titleE}` : titleA;

      const volStr    = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="h">([^<]+)/)?.[1]?.trim();
      const volNum    = volStr ? parseInt(volStr.replace(/\D/g, "")) : undefined;
      const seriesRaw = text.match(/<datafield tag="225"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
      const seriesVol = text.match(/<datafield tag="225"[^>]*>[\s\S]*?<subfield code="v">([^<]+)/)?.[1]?.trim();
      const authorB   = text.match(/<datafield tag="700"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
      const authorF   = text.match(/<datafield tag="700"[^>]*>[\s\S]*?<subfield code="b">([^<]+)/)?.[1]?.trim();
      const author    = authorB ? [authorF ? `${authorF} ${authorB}` : authorB] : [];
      const publisher = text.match(/<datafield tag="210"[^>]*>[\s\S]*?<subfield code="c">([^<]+)/)?.[1]?.trim();
      const yearStr   = text.match(/<datafield tag="210"[^>]*>[\s\S]*?<subfield code="d">(\d{4})/)?.[1];
      const subjects  = text.match(/<subfield code="a">([^<]+)/g)?.join(" ") ?? "";

      let seriesName  = seriesRaw?.replace(/\s*#?\d+.*$/, "").trim();
      let seriesIndex = seriesVol ? parseInt(seriesVol.replace(/\D/g, "")) : volNum;
      if (!seriesName) { const p = extractSeries(title); seriesName = p.seriesName; seriesIndex = p.seriesIndex ?? seriesIndex; }

      return {
        isbn: code, title, authors: author,
        cover_url: `https://catalogue.bnf.fr/couverture?&isbn=${code}&notoile=1`,
        publisher, published_year: yearStr ? parseInt(yearStr) : undefined,
        series_name: seriesName, series_index: seriesIndex,
        book_type: detectType(subjects + " " + title + " " + (publisher ?? "") + " " + (seriesName ?? "")),
      };
    }
    return null;
  } catch { return null; }
}

// ── Open Library ──────────────────────────────────────────────────────────────

async function fromOpenLibrary(isbn: string): Promise<LookupResult | null> {
  try {
    const res = await fetch(
      `https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`,
      { signal: AbortSignal.timeout(5000) }
    );
    const data = await res.json();
    const b    = data[`ISBN:${isbn}`];
    if (!b?.title) return null;

    const subjects   = (b.subjects ?? []).map((s: any) => typeof s === "string" ? s : s.name ?? "").join(" ").toLowerCase();
    const series     = Array.isArray(b.series) ? b.series[0] : b.series;
    const numMatch   = typeof series === "string" ? series.match(/#?(\d+)/) : null;
    const { seriesName: parsedName, seriesIndex: parsedIdx } = extractSeries(b.title);

    return {
      isbn, title: b.title,
      authors: (b.authors ?? []).map((a: any) => a.name),
      cover_url: b.cover?.large ?? b.cover?.medium ?? b.cover?.small,
      publisher: b.publishers?.[0]?.name,
      published_year: b.publish_date ? parseInt(b.publish_date.slice(-4)) : undefined,
      page_count: b.number_of_pages, description: b.excerpts?.[0]?.text,
      series_name: (typeof series === "string" ? series.replace(/\s*#?\d+.*$/, "").trim() || undefined : undefined) ?? parsedName,
      series_index: numMatch ? parseInt(numMatch[1]) : parsedIdx,
      book_type: detectType(subjects + " " + b.title),
    };
  } catch { return null; }
}

// ── Main lookup ───────────────────────────────────────────────────────────────

// Convert ISBN-10 to ISBN-13
function isbn10to13(isbn10: string): string {
  const base = "978" + isbn10.slice(0, 9);
  let sum = 0;
  for (let i = 0; i < 12; i++) sum += parseInt(base[i]) * (i % 2 === 0 ? 1 : 3);
  return base + ((10 - (sum % 10)) % 10);
}

export async function lookupISBN(code: string): Promise<LookupResult | null> {
  const clean = code.replace(/[-\s]/g, "");
  const isIsbn10 = /^\d{9}[\dXx]$/.test(clean);
  const isIsbn13 = /^(978|979)\d{10}$/.test(clean);
  const isbn13 = isIsbn10 ? isbn10to13(clean) : clean;

  // For valid ISBNs: try Google Books + BnF in PARALLEL (2-3x faster)
  if (isIsbn10 || isIsbn13) {
    const results = await Promise.allSettled([
      fromGoogleBooks(clean),
      isIsbn10 ? fromGoogleBooks(isbn13) : Promise.resolve(null),
      fromBnF(isbn13),
      isIsbn10 ? fromBnF(clean) : Promise.resolve(null),
    ]);
    for (const r of results) {
      if (r.status === "fulfilled" && r.value?.title) return r.value;
    }
  }

  // Fallback: BnF for non-ISBN 13-digit codes
  if (/^\d{13}$/.test(clean) && !isIsbn13) {
    const bnf = await fromBnF(clean);
    if (bnf?.title) return bnf;
  }

  // Last resort: Open Library
  const codes = [clean];
  if (isIsbn10) codes.push(isbn13);
  for (const c of codes) {
    const ol = await fromOpenLibrary(c);
    if (ol?.title) {
      if (!isIsbn10 && !isIsbn13) ol._unreliable = true;
      return ol;
    }
  }

  return null;
}
FILEOF
cat > "src/app/api/books/cover/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { searchCoverByTitle } from "@/lib/cover-utils";

export async function GET(req: NextRequest) {
  const title     = req.nextUrl.searchParams.get("title");
  const seriesName = req.nextUrl.searchParams.get("series") ?? undefined;
  if (!title) return NextResponse.json({ cover_url: null });

  const cover = await searchCoverByTitle(title, seriesName);
  return NextResponse.json({ cover_url: cover ?? null });
}
FILEOF
cat > "src/app/api/books/lookup/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { lookupISBN } from "@/lib/isbn-lookup";
import { getCollections, findCollection } from "@/lib/db";
import { ScanResult, Collection } from "@/types";
import { searchCoverByTitle } from "@/lib/cover-utils";

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

export async function GET(req: NextRequest) {
  const isbn       = req.nextUrl.searchParams.get("isbn");
  const library_id = req.nextUrl.searchParams.get("library_id");

  if (!isbn)       return NextResponse.json({ error: "isbn manquant" },       { status: 400 });
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });

  const book = await lookupISBN(isbn);
  if (!book) return NextResponse.json({ error: "Livre introuvable" }, { status: 404 });

  // Auto-search cover if missing
  if (!book.cover_url && book.title) {
    const cover = await searchCoverByTitle(book.title);
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
git commit -m "fix: validate cover URLs, reject 'image not available' placeholders"
git push
echo "🎉 Déployé !"
