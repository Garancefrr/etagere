import { NextRequest, NextResponse } from "next/server";

export async function GET(req: NextRequest) {
  const title = req.nextUrl.searchParams.get("title");
  if (!title) return NextResponse.json({ cover_url: null });

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(title)}&langRestrict=fr${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return NextResponse.json({ cover_url: null });

    const data = await res.json();
    const vol = data.items?.[0]?.volumeInfo;
    if (!vol) return NextResponse.json({ cover_url: null });

    let coverUrl = vol.imageLinks?.large
      ?? vol.imageLinks?.medium
      ?? vol.imageLinks?.thumbnail;

    if (coverUrl) {
      coverUrl = coverUrl
        .replace("http:", "https:")
        .replace("&edge=curl", "")
        .replace(/zoom=\d/, "zoom=3");
    }

    return NextResponse.json({
      cover_url: coverUrl ?? null,
      found_title: vol.title,
      found_authors: vol.authors ?? [],
    });
  } catch {
    return NextResponse.json({ cover_url: null });
  }
}
