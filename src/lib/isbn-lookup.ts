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
