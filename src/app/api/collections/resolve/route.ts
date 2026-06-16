import { NextRequest, NextResponse } from "next/server";
import { resolveCollection, patchCollection } from "@/lib/db";
import { BookType } from "@/types";

async function fetchSeriesCount(seriesName: string): Promise<number | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:"${encodeURIComponent(seriesName)}"+Tome&langRestrict=fr&maxResults=40&orderBy=relevance${keyParam}`,
      { signal: AbortSignal.timeout(8000) }
    );
    if (!res.ok) return null;

    const data = await res.json();
    if (!data.items?.length) return null;

    let maxVolume = 0;
    const seriesLower = seriesName.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    const seriesWords = seriesLower.split(/\s+/).filter((w: string) => w.length >= 3);

    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.title) continue;
      const titleLower = vol.title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      if (!seriesWords.every((w: string) => titleLower.includes(w))) continue;

      const displayNum = item.volumeInfo?.seriesInfo?.bookDisplayNumber;
      if (displayNum) { const n = parseInt(displayNum); if (n > maxVolume) maxVolume = n; }

      const tomeMatch = vol.title.match(/(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i);
      if (tomeMatch) { const n = parseInt(tomeMatch[1]); if (n > maxVolume) maxVolume = n; }
    }

    return maxVolume > 0 ? maxVolume : null;
  } catch { return null; }
}

export async function GET(req: NextRequest) {
  const library_id   = req.nextUrl.searchParams.get("library_id");
  const series_name  = req.nextUrl.searchParams.get("series_name");
  const series_index = req.nextUrl.searchParams.get("series_index");
  const book_type    = (req.nextUrl.searchParams.get("book_type") ?? "bd") as BookType;

  if (!library_id || !series_name || !series_index)
    return NextResponse.json({ error: "Paramètres manquants" }, { status: 400 });

  try {
    const { collection, isNew, isNewVolume } = await resolveCollection(
      library_id, series_name, parseInt(series_index), { book_type }
    );

    // Auto-fetch total volumes for new collections
    if (isNew && collection.id) {
      const total = await fetchSeriesCount(series_name);
      if (total) {
        await patchCollection(collection.id, { total_volumes: total });
        collection.total_volumes = total;
      }
    }

    return NextResponse.json({ collection, isNew, isNewVolume });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
