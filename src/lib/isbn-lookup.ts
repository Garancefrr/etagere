import { LookupResult, BookType } from "@/types";

function detectType(terms: string): BookType {
  if (/manga|manhwa|shonen|shojo|seinen|josei/.test(terms)) return "manga";
  if (/bande dessinée|comics|bd|graphic novel/.test(terms))  return "bd";
  return "livre";
}

function parseSeriesFromTitle(title: string): { name?: string; index?: number } {
  const match = title.match(/(?:vol(?:ume)?\.?\s*|tome\s*|t\.\s*|#\s*)(\d+)/i);
  if (!match) return {};
  return {
    index: parseInt(match[1]),
    name: title.replace(/[,\s]*(?:vol(?:ume)?\.?\s*|tome\s*|t\.\s*|#\s*)\d+.*/i, "").trim() || undefined,
  };
}

async function fromOpenLibrary(isbn: string): Promise<LookupResult | null> {
  const res  = await fetch(`https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`);
  const data = await res.json();
  const b    = data[`ISBN:${isbn}`];
  if (!b) return null;

  const subjects = (b.subjects ?? []).map((s: any) => (typeof s === "string" ? s : s.name ?? "")).join(" ").toLowerCase();
  const series   = Array.isArray(b.series) ? b.series[0] : b.series;
  const numMatch = typeof series === "string" ? series.match(/#?(\d+)/) : null;

  return {
    isbn,
    title: b.title,
    authors: (b.authors ?? []).map((a: any) => a.name),
    cover_url: b.cover?.large ?? b.cover?.medium ?? b.cover?.small,
    publisher: b.publishers?.[0]?.name,
    published_year: b.publish_date ? parseInt(b.publish_date.slice(-4)) : undefined,
    page_count: b.number_of_pages,
    description: b.excerpts?.[0]?.text,
    series_name: typeof series === "string" ? series.replace(/\s*#?\d+.*$/, "").trim() || undefined : undefined,
    series_index: numMatch ? parseInt(numMatch[1]) : undefined,
    book_type: detectType(subjects + " " + b.title),
  };
}

async function fromGoogleBooks(isbn: string): Promise<LookupResult | null> {
  const res  = await fetch(`https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}`);
  const data = await res.json();
  const vol  = data.items?.[0]?.volumeInfo;
  if (!vol) return null;

  const categories = (vol.categories ?? []).join(" ").toLowerCase();
  const parsed     = parseSeriesFromTitle(`${vol.title ?? ""} ${vol.subtitle ?? ""}`);

  return {
    isbn,
    title: vol.title,
    authors: vol.authors ?? [],
    cover_url: vol.imageLinks?.thumbnail?.replace("http:", "https:"),
    publisher: vol.publisher,
    published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : undefined,
    page_count: vol.pageCount,
    description: vol.description,
    series_name: parsed.name,
    series_index: parsed.index,
    book_type: detectType(categories + " " + vol.title),
  };
}

export async function lookupISBN(isbn: string): Promise<LookupResult | null> {
  const clean = isbn.replace(/[-\s]/g, "");
  try { const r = await fromOpenLibrary(clean); if (r) return r; } catch {}
  try { const r = await fromGoogleBooks(clean);  if (r) return r; } catch {}
  return null;
}

