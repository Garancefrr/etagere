import { NextRequest, NextResponse } from "next/server";
import { getBooks, getCollections } from "@/lib/db";
import { Book } from "@/types";

interface Suggestion {
  type: "series" | "author";
  name: string;
  cover_url?: string;
  author?: string;
  book_type: "livre" | "bd" | "manga";
  books: { id: string; title: string; series_index?: number }[];
}

export async function GET(req: NextRequest) {
  const library_id = req.nextUrl.searchParams.get("library_id");
  if (!library_id) return NextResponse.json([], { status: 400 });

  const [books, existingCollections] = await Promise.all([
    getBooks(library_id),
    getCollections(library_id),
  ]);

  const existingNames = new Set(
    existingCollections.map(c => c.name.toLowerCase().trim())
  );

  const suggestions: Suggestion[] = [];
  const usedBookIds = new Set<string>(); // track books already in a suggestion

  // 1. Books with series_name but no collection yet
  const bySeriesName: Record<string, Book[]> = {};
  for (const book of books) {
    if (!book.series_name) continue;
    const key = book.series_name.toLowerCase().trim();
    if (existingNames.has(key)) continue;
    if (!bySeriesName[key]) bySeriesName[key] = [];
    // Deduplicate by series_name + series_index
    const alreadyAdded = bySeriesName[key].some(
      b => b.series_index !== undefined && b.series_index === book.series_index
    );
    if (!alreadyAdded) bySeriesName[key].push(book);
  }

  for (const seriesBooks of Object.values(bySeriesName)) {
    const uniqueBooks = seriesBooks.filter((b, idx, arr) =>
      arr.findIndex(x => x.id === b.id) === idx
    );
    // Only suggest if 2+ books in the series
    if (uniqueBooks.length < 2) continue;
    const first = seriesBooks[0];
    uniqueBooks.forEach(b => usedBookIds.add(b.id));
    suggestions.push({
      type: "series",
      name: first.series_name!,
      cover_url: uniqueBooks.find(b => b.cover_url)?.cover_url,
      author: first.authors[0],
      book_type: first.book_type,
      books: uniqueBooks.map(b => ({
        id: b.id, title: b.title, series_index: b.series_index
      })),
    });
  }

  // 2. Authors with 3+ livres, no collection, not already covered by a series suggestion
  const byAuthor: Record<string, Book[]> = {};
  for (const book of books.filter(b => b.book_type === "livre")) {
    if (usedBookIds.has(book.id)) continue; // already in a series suggestion
    const author = book.authors[0];
    if (!author) continue;
    const key = author.toLowerCase().trim();
    if (existingNames.has(key)) continue;
    if (!byAuthor[key]) byAuthor[key] = [];
    // Deduplicate by book ID
    if (!byAuthor[key].some(b => b.id === book.id)) {
      byAuthor[key].push(book);
    }
  }

  for (const authorBooks of Object.values(byAuthor)) {
    if (authorBooks.length < 3) continue;
    authorBooks.forEach(b => usedBookIds.add(b.id));
    const first = authorBooks[0];
    suggestions.push({
      type: "author",
      name: first.authors[0],
      cover_url: authorBooks.find(b => b.cover_url)?.cover_url,
      author: first.authors[0],
      book_type: "livre",
      books: authorBooks.map(b => ({ id: b.id, title: b.title })),
    });
  }

  suggestions.sort((a, b) => {
    if (a.type !== b.type) return a.type === "series" ? -1 : 1;
    return b.books.length - a.books.length;
  });

  return NextResponse.json(suggestions.slice(0, 10));
}
