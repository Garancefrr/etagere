#!/bin/bash
set -e
echo "🔍 Lookup EAN + ISBN + fix collection_id..."
cd "$(git rev-parse --show-toplevel)"
cat > "src/lib/isbn-lookup.ts" << 'FILEOF'
import { LookupResult, BookType } from "@/types";

// ── Type detection ─────────────────────────────────────────────────────────────

function detectType(terms: string): BookType {
  const t = terms.toLowerCase();
  if (/manga|manhwa|shonen|shojo|seinen|josei|kodansha|shueisha|viz|one.piece|naruto|dragon.ball/.test(t)) return "manga";
  if (/bande.dessin|bd|comics|dargaud|dupuis|lombard|casterman|lucky|schtroumpf|ast[eé]rix|tintin|spirou|blake|mortimer|franco.belge/.test(t)) return "bd";
  return "livre";
}

// ── Series extraction from title ──────────────────────────────────────────────

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
      const name = m[1].replace(/\s+$/, "").trim();
      return { seriesName: name || undefined, seriesIndex: parseInt(m[2]) };
    }
  }
  return {};
}

// ── Google Books (with API key) ───────────────────────────────────────────────

async function fromGoogleBooks(code: string): Promise<LookupResult | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  // Try multiple query strategies
  const queries = [
    `isbn:${code}`,          // Standard ISBN lookup
    `ean:${code}`,           // EAN lookup
    code,                    // Raw code as general search
  ];

  for (const q of queries) {
    try {
      const res = await fetch(
        `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}${keyParam}`,
        { signal: AbortSignal.timeout(5000) }
      );

      if (!res.ok) {
        console.error(`Google Books error for "${q}":`, res.status);
        continue;
      }

      const data = await res.json();
      const vol = data.items?.[0]?.volumeInfo;
      if (!vol?.title) continue;

      // For raw code searches, verify the result has matching identifiers
      if (q === code && !queries[0].startsWith("isbn")) {
        const identifiers = vol.industryIdentifiers ?? [];
        const hasMatch = identifiers.some((id: any) =>
          id.identifier === code || id.identifier === code.replace(/-/g, "")
        );
        if (!hasMatch && data.totalItems > 1) continue; // Skip unreliable matches
      }

      const categories = (vol.categories ?? []).join(" ").toLowerCase();
      const fullTitle  = `${vol.title} ${vol.subtitle ?? ""}`.trim();
      const { seriesName, seriesIndex } = extractSeries(fullTitle);

      let coverUrl = vol.imageLinks?.extraLarge
        ?? vol.imageLinks?.large
        ?? vol.imageLinks?.medium
        ?? vol.imageLinks?.thumbnail;

      if (coverUrl) {
        coverUrl = coverUrl
          .replace("http:", "https:")
          .replace("&edge=curl", "")
          .replace(/zoom=\d/, "zoom=3");
      }

      return {
        isbn: code, title: vol.title, authors: vol.authors ?? [],
        cover_url: coverUrl,
        publisher: vol.publisher,
        published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : undefined,
        page_count: vol.pageCount,
        description: vol.description,
        series_name: seriesName, series_index: seriesIndex,
        book_type: detectType(categories + " " + fullTitle + " " + (vol.publisher ?? "")),
      };
    } catch {
      continue;
    }
  }

  return null;
}

// ── BnF SRU API ───────────────────────────────────────────────────────────────

async function fromBnF(code: string): Promise<LookupResult | null> {
  try {
    // Try EAN first, then ISBN
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
      if (!seriesName) {
        const p = extractSeries(title);
        seriesName  = p.seriesName;
        seriesIndex = p.seriesIndex ?? seriesIndex;
      }

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
    const res  = await fetch(
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
      page_count: b.number_of_pages,
      description: b.excerpts?.[0]?.text,
      series_name: (typeof series === "string" ? series.replace(/\s*#?\d+.*$/, "").trim() || undefined : undefined) ?? parsedName,
      series_index: numMatch ? parseInt(numMatch[1]) : parsedIdx,
      book_type: detectType(subjects + " " + b.title),
    };
  } catch { return null; }
}

// ── Main lookup ───────────────────────────────────────────────────────────────

export async function lookupISBN(code: string): Promise<LookupResult | null> {
  const clean = code.replace(/[-\s]/g, "");

  // 1. Google Books — tries isbn:, ean:, and raw code
  const gb = await fromGoogleBooks(clean);
  if (gb?.title) return gb;

  // 2. BnF — tries bib.ean then bib.isbn
  if (/^\d{13}$/.test(clean)) {
    const bnf = await fromBnF(clean);
    if (bnf?.title) return bnf;
  }

  // 3. Open Library — last resort
  const ol = await fromOpenLibrary(clean);
  if (ol?.title) return ol;

  return null;
}
FILEOF
cat > "src/app/api/books/add/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { insertBook } from "@/lib/db";
import { Book } from "@/types";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as Omit<Book, "id" | "added_at" | "updated_at"> & { email?: string };
    const { email, ...bookData } = body;

    // Resolve added_by: email → profile UUID
    if (email) {
      const profileId = await getProfileId(email);
      if (profileId) bookData.added_by = profileId;
    }

    // Remove collection_id if empty to avoid DB errors
    if (!bookData.collection_id) {
      delete (bookData as any).collection_id;
    }

    const book = await insertBook(bookData);
    return NextResponse.json(book);
  } catch (e: any) {
    console.error("POST /api/books/add:", e);
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
FILEOF
git add -A
git commit -m "feat: lookup tries isbn/ean/raw on Google Books, fix collection_id handling"
git push
echo "🎉 Déployé !"
