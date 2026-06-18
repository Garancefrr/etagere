import { NextRequest, NextResponse } from "next/server";
import { getBooks, getCollections } from "@/lib/db";
import { Book, Collection } from "@/types";

interface Suggestion {
  type: "series" | "author";
  name: string;
  cover_url?: string;
  author?: string;
  book_type: "livre" | "bd" | "manga";
  books: { id: string; title: string; series_index?: number }[];
  total_volumes?: number;
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

  // 1. Books with series_name but no collection yet
  const bySeriesName: Record<string, Book[]> = {};
  for (const book of books) {
    if (!book.series_name) continue;
    const key = book.series_name.toLowerCase().trim();
    if (existingNames.has(key)) continue; // already has collection
    if (!bySeriesName[key]) bySeriesName[key] = [];
    bySeriesName[key].push(book);
  }

  for (const [key, seriesBooks] of Object.entries(bySeriesName)) {
    const first = seriesBooks[0];
    // Deduplicate by series_index (keep only one book per tome number)
    const seen = new Set<number>();
    const dedupedBooks = seriesBooks.filter(b => {
      if (!b.series_index) return true;
      if (seen.has(b.series_index)) return false;
      seen.add(b.series_index);
      return true;
    });
    suggestions.push({
      type: "series",
      name: first.series_name!,
      cover_url: dedupedBooks.find(b => b.cover_url)?.cover_url,
      author: first.authors[0],
      book_type: first.book_type,
      books: dedupedBooks.map(b => ({ id: b.id, title: b.title, series_index: b.series_index })),
    });
  }

  // 2. Authors with 3+ books (livres only), no collection
  const byAuthor: Record<string, Book[]> = {};
  for (const book of books.filter(b => b.book_type === "livre")) {
    const author = book.authors[0];
    if (!author) continue;
    const key = author.toLowerCase().trim();
    if (existingNames.has(key)) continue;
    if (!byAuthor[key]) byAuthor[key] = [];
    byAuthor[key].push(book);
  }

  for (const [key, authorBooks] of Object.entries(byAuthor)) {
    if (authorBooks.length < 3) continue;
    // Skip if already suggested via series
    const hasSeriesSuggestion = suggestions.some(s =>
      s.books.some(b => authorBooks.some(ab => ab.id === b.id))
    );
    if (hasSeriesSuggestion) continue;

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

  // Sort: series first, then by book count desc
  suggestions.sort((a, b) => {
    if (a.type !== b.type) return a.type === "series" ? -1 : 1;
    return b.books.length - a.books.length;
  });

  return NextResponse.json(suggestions.slice(0, 10));
}
