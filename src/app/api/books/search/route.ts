import { NextRequest, NextResponse } from "next/server";
import { validateCoverUrl } from "@/lib/cover-utils";

export async function GET(req: NextRequest) {
  const q = req.nextUrl.searchParams.get("q");
  if (!q || q.length < 2) return NextResponse.json([]);

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  // Try with API key first, then without if it fails (quota exceeded)
  const urls = [
    `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}&maxResults=10&orderBy=relevance${keyParam}`,
    `https://www.googleapis.com/books/v1/volumes?q=inauthor:${encodeURIComponent(q)}&maxResults=10&orderBy=relevance${keyParam}`,
  ];

  let allItems: any[] = [];
  let usedFallback = false;

  // Parallel fetch
  const responses = await Promise.allSettled(
    urls.map(url => fetch(url, { signal: AbortSignal.timeout(6000) }))
  );

  for (const result of responses) {
    if (result.status !== "fulfilled") continue;
    const res = result.value;
    if (res.status === 429 || res.status === 403) {
      // API key quota exceeded — retry without key
      usedFallback = true;
      continue;
    }
    if (!res.ok) continue;
    try {
      const data = await res.json();
      if (data.items) allItems.push(...data.items);
    } catch { continue; }
  }

  // Fallback: retry without API key if quota exceeded
  if (allItems.length === 0 && (usedFallback || !apiKey)) {
    try {
      const res = await fetch(
        `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}&maxResults=10&orderBy=relevance`,
        { signal: AbortSignal.timeout(6000) }
      );
      if (res.ok) {
        const data = await res.json();
        if (data.items) allItems = data.items;
      } else {
        console.error("Google Books search failed:", res.status, await res.text().catch(() => ""));
      }
    } catch (e) {
      console.error("Google Books search error:", e);
    }
  }

  if (!allItems.length) {
    console.error("Search returned 0 results for:", q, "usedFallback:", usedFallback);
    return NextResponse.json([]);
  }

  const seen = new Set<string>();
  const results: any[] = [];

  for (const item of allItems) {
    if (results.length >= 10) break;
    const vol = item.volumeInfo;
    if (!vol?.title) continue;

    const key = `${vol.title.toLowerCase()}::${(vol.authors?.[0] ?? "").toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);

    const rawCover = vol.imageLinks?.large ?? vol.imageLinks?.medium ?? vol.imageLinks?.thumbnail;
    const cover = rawCover ? validateCoverUrl(rawCover) : null;

    const titleRaw = vol.title ?? "";
    let seriesName: string | null = null;
    let seriesIndex: number | null = null;
    if (vol.seriesInfo?.bookDisplayNumber) seriesIndex = parseInt(vol.seriesInfo.bookDisplayNumber);
    const m = titleRaw.match(/^(.+?)\s*[-\u2013\u2014:,]\s*(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i);
    if (m) { seriesName = m[1].trim(); seriesIndex = seriesIndex ?? parseInt(m[2]); }

    const isbn = vol.industryIdentifiers?.find(
      (id: any) => id.type === "ISBN_13" || id.type === "ISBN_10"
    )?.identifier ?? null;

    const categories = (vol.categories ?? []).join(" ").toLowerCase();
    let book_type = "livre";
    if (/manga|manhwa/.test(titleRaw.toLowerCase() + " " + categories)) book_type = "manga";
    else if (/comic|bande dessin|graphic novel/.test(categories)) book_type = "bd";

    results.push({
      isbn, title: titleRaw.split(";")[0].trim(),
      authors: vol.authors ?? [], cover_url: cover,
      publisher: vol.publisher ?? null,
      published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : null,
      page_count: vol.pageCount ?? null,
      description: vol.description ?? null,
      series_name: seriesName, series_index: seriesIndex, book_type,
    });
  }

  return NextResponse.json(results);
}
