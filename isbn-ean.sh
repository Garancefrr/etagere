#!/bin/bash
set -e
echo "📚 BnF en priorité pour tous les EAN-13..."
cd "$(git rev-parse --show-toplevel)"
cat > src/lib/isbn-lookup.ts << 'FILEOF'
import { LookupResult, BookType } from "@/types";

// ── Type detection ─────────────────────────────────────────────────────────────

function detectType(terms: string): BookType {
  const t = terms.toLowerCase();
  if (/manga|manhwa|shonen|shojo|seinen|josei|kodansha|shueisha|viz|one.piece|naruto|dragon.ball/.test(t)) return "manga";
  if (/bande.dessin|bd|comics|dargaud|dupuis|lombard|casterman|lucky|schtroumpf|ast[eé]rix|tintin|spirou|blake|mortimer/.test(t)) return "bd";
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
      const name = m[1]
        .replace(/^(les|la|le|l'|the)\s+/i, "")
        .replace(/\s+$/, "")
        .trim();
      return { seriesName: name || undefined, seriesIndex: parseInt(m[2]) };
    }
  }
  return {};
}

// ── BnF SRU API — covers all French/Belgian EAN codes ────────────────────────

async function fromBnF(code: string): Promise<LookupResult | null> {
  try {
    const url = `https://catalogue.bnf.fr/api/SRU?version=1.2&operation=searchRetrieve&query=bib.ean+adj+"${code}"&recordSchema=unimarcxchange&maximumRecords=1`;
    const res  = await fetch(url, { signal: AbortSignal.timeout(6000) });
    const text = await res.text();

    if (!text.includes("<numberOfRecords>") || text.includes("<numberOfRecords>0")) return null;

    // Title: UNIMARC 200$a + 200$e (subtitle)
    const titleA = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
    const titleE = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="e">([^<]+)/)?.[1]?.trim();
    if (!titleA) return null;
    const title = titleE ? `${titleA} — ${titleE}` : titleA;

    // Volume number: UNIMARC 200$h
    const volStr  = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="h">([^<]+)/)?.[1]?.trim();
    const volNum  = volStr ? parseInt(volStr.replace(/\D/g, "")) : undefined;

    // Series: UNIMARC 225$a
    const seriesRaw = text.match(/<datafield tag="225"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
    const seriesVol = text.match(/<datafield tag="225"[^>]*>[\s\S]*?<subfield code="v">([^<]+)/)?.[1]?.trim();

    // Author: UNIMARC 700$a + 700$b
    const authorB = text.match(/<datafield tag="700"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
    const authorF = text.match(/<datafield tag="700"[^>]*>[\s\S]*?<subfield code="b">([^<]+)/)?.[1]?.trim();
    const author  = authorB ? [authorF ? `${authorF} ${authorB}` : authorB] : [];

    // Publisher: UNIMARC 210$c
    const publisher = text.match(/<datafield tag="210"[^>]*>[\s\S]*?<subfield code="c">([^<]+)/)?.[1]?.trim();

    // Year: UNIMARC 210$d
    const yearStr = text.match(/<datafield tag="210"[^>]*>[\s\S]*?<subfield code="d">(\d{4})/)?.[1];
    const year    = yearStr ? parseInt(yearStr) : undefined;

    // Genre/subject for type detection
    const subjects = text.match(/<subfield code="a">([^<]+)/g)?.join(" ") ?? "";

    // Series resolution
    let seriesName  = seriesRaw?.replace(/\s*#?\d+.*$/, "").trim();
    let seriesIndex = seriesVol ? parseInt(seriesVol.replace(/\D/g, "")) : volNum;

    // Fallback: parse series from title
    if (!seriesName) {
      const parsed = extractSeries(title);
      seriesName  = parsed.seriesName;
      seriesIndex = parsed.seriesIndex ?? seriesIndex;
    }

    const book_type = detectType(subjects + " " + title + " " + (publisher ?? "") + " " + (seriesName ?? ""));

    return {
      isbn: code,
      title,
      authors: author,
      cover_url: `https://catalogue.bnf.fr/couverture?&isbn=${code}&notoile=1`,
      publisher,
      published_year: year,
      series_name: seriesName,
      series_index: seriesIndex,
      book_type,
    };
  } catch {
    return null;
  }
}

// ── Open Library ──────────────────────────────────────────────────────────────

async function fromOpenLibrary(isbn: string): Promise<LookupResult | null> {
  try {
    const res  = await fetch(`https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`, { signal: AbortSignal.timeout(5000) });
    const data = await res.json();
    const b    = data[`ISBN:${isbn}`];
    if (!b?.title) return null;

    const subjects   = (b.subjects ?? []).map((s: any) => typeof s === "string" ? s : s.name ?? "").join(" ").toLowerCase();
    const series     = Array.isArray(b.series) ? b.series[0] : b.series;
    const numMatch   = typeof series === "string" ? series.match(/#?(\d+)/) : null;
    const { seriesName: parsedName, seriesIndex: parsedIdx } = extractSeries(b.title);

    return {
      isbn,
      title:          b.title,
      authors:        (b.authors ?? []).map((a: any) => a.name),
      cover_url:      b.cover?.large ?? b.cover?.medium ?? b.cover?.small,
      publisher:      b.publishers?.[0]?.name,
      published_year: b.publish_date ? parseInt(b.publish_date.slice(-4)) : undefined,
      page_count:     b.number_of_pages,
      description:    b.excerpts?.[0]?.text,
      series_name:    (typeof series === "string" ? series.replace(/\s*#?\d+.*$/, "").trim() || undefined : undefined) ?? parsedName,
      series_index:   numMatch ? parseInt(numMatch[1]) : parsedIdx,
      book_type:      detectType(subjects + " " + b.title),
    };
  } catch {
    return null;
  }
}

// ── Google Books ──────────────────────────────────────────────────────────────

async function fromGoogleBooks(isbn: string): Promise<LookupResult | null> {
  try {
    const res  = await fetch(`https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}`, { signal: AbortSignal.timeout(5000) });
    const data = await res.json();
    const vol  = data.items?.[0]?.volumeInfo;
    if (!vol?.title) return null;

    const categories = (vol.categories ?? []).join(" ").toLowerCase();
    const fullTitle  = `${vol.title} ${vol.subtitle ?? ""}`.trim();
    const { seriesName, seriesIndex } = extractSeries(fullTitle);

    return {
      isbn,
      title:          vol.title,
      authors:        vol.authors ?? [],
      cover_url:      vol.imageLinks?.thumbnail?.replace("http:", "https:").replace("zoom=1", "zoom=3").replace("&edge=curl", ""),
      publisher:      vol.publisher,
      published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : undefined,
      page_count:     vol.pageCount,
      description:    vol.description,
      series_name:    seriesName,
      series_index:   seriesIndex,
      book_type:      detectType(categories + " " + fullTitle),
    };
  } catch {
    return null;
  }
}

// ── Main lookup ───────────────────────────────────────────────────────────────
// Strategy:
// 1. BnF first — best coverage for ALL French/European EAN codes (books, BD, manga)
// 2. Open Library — good for international ISBN
// 3. Google Books — good fallback with cover images
// 4. Title-based series extraction as last resort

export async function lookupISBN(code: string): Promise<LookupResult | null> {
  const clean = code.replace(/[-\s]/g, "");

  // Try BnF first for all EAN-13 codes (European standard)
  // EAN-13 = 13 digits. ISBN-13 = subset of EAN-13 starting with 978/979
  const isEAN13 = /^\d{13}$/.test(clean);

  if (isEAN13) {
    const bnf = await fromBnF(clean);
    if (bnf?.title) return bnf;
  }

  // Open Library
  const ol = await fromOpenLibrary(clean);
  if (ol?.title) return ol;

  // Google Books
  const gb = await fromGoogleBooks(clean);
  if (gb?.title) return gb;

  // BnF as last resort (for non-EAN13 or if already tried above)
  if (!isEAN13) {
    const bnf = await fromBnF(clean);
    if (bnf?.title) return bnf;
  }

  return null;
}
FILEOF
git add -A
git commit -m "feat: BnF first for all EAN-13 codes — books, BD, manga"
git push
echo "🎉 Déployé !"
