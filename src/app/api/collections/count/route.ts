import { NextRequest, NextResponse } from "next/server";

export async function GET(req: NextRequest) {
  const series = req.nextUrl.searchParams.get("series");
  if (!series) return NextResponse.json({ total: null });

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    // Search for all volumes in this series
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:"${encodeURIComponent(series)}"+Tome&langRestrict=fr&maxResults=40&orderBy=relevance${keyParam}`,
      { signal: AbortSignal.timeout(8000) }
    );
    if (!res.ok) return NextResponse.json({ total: null });

    const data = await res.json();
    if (!data.items?.length) return NextResponse.json({ total: null });

    let maxVolume = 0;
    const seriesLower = series.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");

    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.title) continue;

      const titleLower = vol.title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      
      // Check that this result actually matches our series
      const seriesWords = seriesLower.split(/\s+/).filter(w => w.length >= 3);
      const isMatch = seriesWords.every(w => titleLower.includes(w));
      if (!isMatch) continue;

      // Extract volume number from seriesInfo
      const displayNum = item.volumeInfo?.seriesInfo?.bookDisplayNumber;
      if (displayNum) {
        const n = parseInt(displayNum);
        if (n > maxVolume) maxVolume = n;
      }

      // Extract volume number from title (Tome XX, T.XX, Vol.XX)
      const tomeMatch = vol.title.match(/(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i);
      if (tomeMatch) {
        const n = parseInt(tomeMatch[1]);
        if (n > maxVolume) maxVolume = n;
      }
    }

    return NextResponse.json({ 
      total: maxVolume > 0 ? maxVolume : null,
      results_count: data.items.length,
    });
  } catch {
    return NextResponse.json({ total: null });
  }
}
