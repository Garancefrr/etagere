import { NextRequest, NextResponse } from "next/server";
import { validateCoverUrl } from "@/lib/cover-utils";

export async function GET(req: NextRequest) {
  const q = req.nextUrl.searchParams.get("q");
  if (!q || q.length < 2) return NextResponse.json([]);

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    // Search without langRestrict to get all languages
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}&maxResults=10&orderBy=relevance${keyParam}`,
      { signal: AbortSignal.timeout(6000) }
    );
    if (!res.ok) return NextResponse.json([]);
    const data = await res.json();
    if (!data.items?.length) return NextResponse.json([]);

    const seen = new Set<string>();
    const results = [];

    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.title) continue;

      // Deduplicate by title+author
      const key = `${vol.title}::${(vol.authors ?? []).join(",")}`.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);

      // Cover
      const rawCover = vol.imageLinks?.extraLarge
        ?? vol.imageLinks?.large
        ?? vol.imageLinks?.medium
        ?? vol.imageLinks?.thumbnail;
      const cover = rawCover ? validateCoverUrl(rawCover) : null;

      // Series detection from title
      const titleRaw = vol.title ?? "";
      let seriesName: string | null = null;
      let seriesIndex: number | null = null;

      // From seriesInfo API field
      if (vol.seriesInfo?.bookDisplayNumber) {
        seriesIndex = parseInt(vol.seriesInfo.bookDisplayNumber);
      }
      // From title pattern "Series - Tome N" or "Series, T. N"
      const m = titleRaw.match(/^(.+?)\s*[-–—:,]\s*(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i);
      if (m) {
        seriesName = m[1].trim();
        seriesIndex = seriesIndex ?? parseInt(m[2]);
      }

      // ISBN
      const isbn = vol.industryIdentifiers?.find(
        (id: any) => id.type === "ISBN_13" || id.type === "ISBN_10"
      )?.identifier ?? null;

      // Book type detection
      let book_type = "livre";
      const categories = (vol.categories ?? []).join(" ").toLowerCase();
      const titleL = titleRaw.toLowerCase();
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

    return NextResponse.json(results.slice(0, 8));
  } catch (e) {
    console.error("Search error:", e);
    return NextResponse.json([]);
  }
}
