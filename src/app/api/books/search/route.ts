import { NextRequest, NextResponse } from "next/server";

export async function GET(req: NextRequest) {
  const q = req.nextUrl.searchParams.get("q");
  if (!q || q.length < 2) return NextResponse.json([]);

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}&langRestrict=fr&maxResults=8${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return NextResponse.json([]);
    const data = await res.json();
    if (!data.items?.length) return NextResponse.json([]);

    const results = data.items.map((item: any) => {
      const vol = item.volumeInfo;
      let cover = vol.imageLinks?.large ?? vol.imageLinks?.medium ?? vol.imageLinks?.thumbnail;
      if (cover) cover = cover.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");

      // Extract series if any
      const titleRaw = vol.title ?? "";
      const seriesInfo = vol.seriesInfo;
      let seriesName: string | undefined;
      let seriesIndex: number | undefined;
      if (seriesInfo?.bookDisplayNumber) seriesIndex = parseInt(seriesInfo.bookDisplayNumber);
      const m = titleRaw.match(/^(.+?)\s*[-–—]\s*(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i);
      if (m) { seriesName = m[1].trim(); seriesIndex = seriesIndex ?? parseInt(m[2]); }

      return {
        isbn: vol.industryIdentifiers?.find((id: any) => id.type.includes("ISBN"))?.identifier,
        title: titleRaw.split(";")[0].trim(),
        authors: vol.authors ?? [],
        cover_url: cover ?? null,
        publisher: vol.publisher ?? null,
        published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : null,
        page_count: vol.pageCount ?? null,
        description: vol.description ?? null,
        series_name: seriesName ?? null,
        series_index: seriesIndex ?? null,
      };
    });

    return NextResponse.json(results);
  } catch { return NextResponse.json([]); }
}
