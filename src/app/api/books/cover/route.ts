import { NextRequest, NextResponse } from "next/server";

export async function GET(req: NextRequest) {
  const title = req.nextUrl.searchParams.get("title");
  if (!title) return NextResponse.json({ cover_url: null });

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    // Search with exact title in quotes for better matching
    const exactQuery = `"${title}"`;
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:${encodeURIComponent(exactQuery)}&langRestrict=fr&maxResults=5${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return NextResponse.json({ cover_url: null });

    const data = await res.json();
    if (!data.items?.length) return NextResponse.json({ cover_url: null });

    // Find best match: title must actually contain our search terms
    const titleLower = title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    const titleWords = titleLower.split(/\s+/).filter(w => w.length >= 3);

    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.imageLinks) continue;

      const volTitle = (vol.title ?? "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      // Check that most title words match
      const matchCount = titleWords.filter(w => volTitle.includes(w)).length;
      if (matchCount < titleWords.length * 0.6) continue;

      let url = vol.imageLinks.large ?? vol.imageLinks.medium ?? vol.imageLinks.thumbnail;
      if (url) {
        url = url.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");
      }
      return NextResponse.json({ cover_url: url ?? null, found_title: vol.title });
    }

    return NextResponse.json({ cover_url: null });
  } catch {
    return NextResponse.json({ cover_url: null });
  }
}
