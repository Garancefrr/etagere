import { NextRequest, NextResponse } from "next/server";
import { validateCoverUrl } from "@/lib/cover-utils";

export async function GET(req: NextRequest) {
  const q = req.nextUrl.searchParams.get("q");
  if (!q || q.length < 2) return NextResponse.json([]);

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  // Run title + author searches in parallel
  const [byGeneral, byAuthor, byTitle] = await Promise.allSettled([
    fetch(`https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}&maxResults=10&orderBy=relevance${keyParam}`,
      { signal: AbortSignal.timeout(6000) }),
    fetch(`https://www.googleapis.com/books/v1/volumes?q=inauthor:${encodeURIComponent(q)}&maxResults=10&orderBy=relevance${keyParam}`,
      { signal: AbortSignal.timeout(6000) }),
    fetch(`https://www.googleapis.com/books/v1/volumes?q=intitle:${encodeURIComponent(q)}&maxResults=10&orderBy=relevance${keyParam}`,
      { signal: AbortSignal.timeout(6000) }),
  ]);

  // Merge all results
  const allItems: any[] = [];
  for (const result of [byGeneral, byAuthor, byTitle]) {
    if (result.status !== "fulfilled" || !result.value.ok) continue;
    try {
      const data = await result.value.json();
      if (data.items) allItems.push(...data.items);
    } catch { continue; }
  }

  if (!allItems.length) return NextResponse.json([]);

  const seen = new Set<string>();
  const results: any[] = [];

  for (const item of allItems) {
    if (results.length >= 10) break;
    const vol = item.volumeInfo;
    if (!vol?.title) continue;

    // Deduplicate by title + first author
    const key = `${vol.title.toLowerCase()}::${(vol.authors?.[0] ?? "").toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);

    // Cover
    const rawCover = vol.imageLinks?.extraLarge
      ?? vol.imageLinks?.large
      ?? vol.imageLinks?.medium
      ?? vol.imageLinks?.thumbnail;
    const cover = rawCover ? validateCoverUrl(rawCover) : null;

    // Series detection
    const titleRaw = vol.title ?? "";
    let seriesName: string | null = null;
    let seriesIndex: number | null = null;
    if (vol.seriesInfo?.bookDisplayNumber) {
      seriesIndex = parseInt(vol.seriesInfo.bookDisplayNumber);
    }
    const m = titleRaw.match(/^(.+?)\s*[-–—:,]\s*(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i);
    if (m) { seriesName = m[1].trim(); seriesIndex = seriesIndex ?? parseInt(m[2]); }

    // ISBN
    const isbn = vol.industryIdentifiers?.find(
      (id: any) => id.type === "ISBN_13" || id.type === "ISBN_10"
    )?.identifier ?? null;

    // Book type
    const categories = (vol.categories ?? []).join(" ").toLowerCase();
    const titleL = titleRaw.toLowerCase();
    let book_type = "livre";
    if (/manga|manhwa/.test(titleL + " " + categories)) book_type = "manga";
    else if (/comic|bande dessin|graphic novel/.test(categories)) book_type = "bd";

    results.push({
      isbn,
      title: titleRaw.split(";")[0].trim(),
      authors: vol.authors ?? [],
      cover_url: cover,
      publisher: vol.publisher ?? null,
      published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : null,
      page_count: vol.pageCount ?? null,
      description: vol.description ?? null,
      series_name: seriesName,
      series_index: seriesIndex,
      book_type,
    });
  }

  return NextResponse.json(results);
}
