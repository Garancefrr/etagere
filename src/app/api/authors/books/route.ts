import { NextRequest, NextResponse } from "next/server";
import { validateCoverUrl } from "@/lib/cover-utils";

export async function GET(req: NextRequest) {
  const author = req.nextUrl.searchParams.get("author");
  if (!author || author.length < 2) return NextResponse.json([]);

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";

  // Try with API key, then without on quota error
  let data: any = null;
  for (const key of [apiKey ? `&key=${apiKey}` : "", ""]) {
    try {
      const res = await fetch(
        `https://www.googleapis.com/books/v1/volumes?q=inauthor:"${encodeURIComponent(author)}"&maxResults=40&orderBy=relevance&printType=books${key}`,
        { signal: AbortSignal.timeout(8000) }
      );
      if (res.status === 403 || res.status === 429) continue;
      if (!res.ok) continue;
      data = await res.json();
      if (data.items?.length) break;
    } catch { continue; }
  }

  if (!data?.items?.length) return NextResponse.json([]);

  const seen = new Set<string>();
  const results: any[] = [];
  const authorLower = author.toLowerCase();

  for (const item of data.items) {
    const vol = item.volumeInfo;
    if (!vol?.title) continue;

    // Only keep books where this author is listed
    const isAuthor = vol.authors?.some((a: string) => {
      const aLower = a.toLowerCase();
      return aLower.includes(authorLower) || authorLower.includes(aLower) ||
        aLower.split(" ").pop() === authorLower.split(" ").pop();
    });
    if (!isAuthor) continue;

    // Dedup
    const key = vol.title.toLowerCase().replace(/[^a-zàâéèêëïîôùûüç0-9]/g, "");
    if (seen.has(key)) continue;
    seen.add(key);

    const rawCover = vol.imageLinks?.large ?? vol.imageLinks?.medium ?? vol.imageLinks?.thumbnail;
    const cover = rawCover ? validateCoverUrl(rawCover) : null;
    const isbn = vol.industryIdentifiers?.find(
      (id: any) => id.type === "ISBN_13" || id.type === "ISBN_10"
    )?.identifier ?? null;

    results.push({
      isbn, title: vol.title.split(";")[0].trim(),
      authors: vol.authors ?? [], cover_url: cover,
      published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : null,
      description: vol.description ?? null,
    });
  }

  results.sort((a: any, b: any) => (b.published_year ?? 0) - (a.published_year ?? 0));
  return NextResponse.json(results);
}
