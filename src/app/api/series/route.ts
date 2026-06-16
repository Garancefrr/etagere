import { NextRequest, NextResponse } from "next/server";

interface SeriesSuggestion {
  name: string;
  author?: string;
  total_volumes?: number;
  cover_url?: string;
  book_type: "livre" | "bd" | "manga";
}

export async function GET(req: NextRequest) {
  const q = req.nextUrl.searchParams.get("q");
  if (!q || q.length < 2) return NextResponse.json([]);

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:"${encodeURIComponent(q)}"+Tome&langRestrict=fr&maxResults=20${keyParam}`,
      { signal: AbortSignal.timeout(6000) }
    );
    if (!res.ok) return NextResponse.json([]);

    const data = await res.json();
    if (!data.items?.length) return NextResponse.json([]);

    // Group results by series name and find the highest tome
    const seriesMap = new Map<string, SeriesSuggestion>();

    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.title) continue;

      // Extract series name from title pattern "Series - Tome X"
      const match = vol.title.match(/^(.+?)\s*[-–—]\s*(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i);
      if (!match) continue;

      const seriesName = match[1].trim();
      const tomeNum = parseInt(match[2]);
      const key = seriesName.toLowerCase();

      const existing = seriesMap.get(key);
      const currentMax = existing?.total_volumes ?? 0;

      // Detect type
      const categories = (vol.categories ?? []).join(" ").toLowerCase();
      const allText = categories + " " + vol.title + " " + (vol.publisher ?? "");
      let bookType: "livre" | "bd" | "manga" = "livre";
      if (/manga|manhwa|shonen|shojo|seinen/.test(allText)) bookType = "manga";
      else if (/bande.dessin|bd|comics|dargaud|dupuis|lombard|casterman/.test(allText)) bookType = "bd";

      // Get cover
      let coverUrl = vol.imageLinks?.thumbnail;
      if (coverUrl) coverUrl = coverUrl.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");

      if (tomeNum > currentMax || !existing) {
        seriesMap.set(key, {
          name: seriesName,
          author: vol.authors?.[0],
          total_volumes: Math.max(tomeNum, currentMax),
          cover_url: existing?.cover_url ?? coverUrl,
          book_type: existing?.book_type ?? bookType,
        });
      }
    }

    // Sort by relevance (name closest to query first)
    const results = Array.from(seriesMap.values())
      .sort((a, b) => {
        const aMatch = a.name.toLowerCase().startsWith(q.toLowerCase()) ? 0 : 1;
        const bMatch = b.name.toLowerCase().startsWith(q.toLowerCase()) ? 0 : 1;
        return aMatch - bMatch || a.name.localeCompare(b.name);
      })
      .slice(0, 8);

    return NextResponse.json(results);
  } catch {
    return NextResponse.json([]);
  }
}
