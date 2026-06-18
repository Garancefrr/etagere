import { NextRequest, NextResponse } from "next/server";
import { getBooks, patchBook } from "@/lib/db";

async function fetchDescription(title: string, authors: string[], isbn?: string): Promise<string | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  // Try ISBN first (most precise)
  if (isbn) {
    try {
      const res = await fetch(
        `https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}&maxResults=1${keyParam}`,
        { signal: AbortSignal.timeout(5000) }
      );
      if (res.ok) {
        const data = await res.json();
        const desc = data.items?.[0]?.volumeInfo?.description;
        if (desc && desc.length > 20) return desc;
      }
    } catch { /* continue */ }
  }

  // Fallback: search by title + author
  const author = authors[0] ?? "";
  const q = author ? `intitle:${title} inauthor:${author}` : `intitle:${title}`;
  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}&langRestrict=fr&maxResults=5${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.items?.length) return null;

    const titleLower = title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.description || vol.description.length < 20) continue;
      const volTitle = (vol.title ?? "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      // Check title similarity
      const titleWords = titleLower.split(/\s+/).filter(w => w.length >= 3);
      const matchCount = titleWords.filter(w => volTitle.includes(w)).length;
      if (titleWords.length > 0 && matchCount >= titleWords.length * 0.5) {
        return vol.description;
      }
    }
    return null;
  } catch { return null; }
}

export async function POST(req: NextRequest) {
  const { library_id } = await req.json();
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });

  try {
    const books = await getBooks(library_id);
    const withoutDesc = books.filter(b => !b.description);

    let updated = 0;
    for (const book of withoutDesc) {
      try {
        const desc = await fetchDescription(book.title, book.authors, book.isbn);
        if (desc) {
          await patchBook(book.id, { description: desc } as any, library_id);
          updated++;
        }
        await new Promise(r => setTimeout(r, 200));
      } catch { /* skip */ }
    }

    return NextResponse.json({ total: withoutDesc.length, updated });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
