import { Book } from "@/types";

// Simple in-memory book store (replace with Supabase in production)
let books: Book[] = [
  {
    id: "b1", isbn: "9782070360024", title: "Le Seigneur des Anneaux",
    authors: ["J.R.R. Tolkien"], cover_url: "https://covers.openlibrary.org/b/isbn/9782070360024-M.jpg",
    publisher: "Gallimard", published_year: 1954, page_count: 1200,
    book_type: "livre", status: "lu", rating: 5,
    added_by: "user1", added_at: "2025-01-10T10:00:00Z", updated_at: "2025-01-10T10:00:00Z", library_id: "lib1",
  },
  {
    id: "b2", isbn: "9782205055375", title: "Astérix le Gaulois",
    authors: ["René Goscinny", "Albert Uderzo"], cover_url: "https://covers.openlibrary.org/b/isbn/9782205055375-M.jpg",
    publisher: "Hachette", published_year: 1961, page_count: 48,
    book_type: "bd", status: "lu", rating: 4, series_name: "Astérix", series_index: 1,
    added_by: "user1", added_at: "2025-02-01T10:00:00Z", updated_at: "2025-02-01T10:00:00Z", library_id: "lib1",
  },
  {
    id: "b3", isbn: "9782012101562", title: "Harry Potter à l'école des sorciers",
    authors: ["J.K. Rowling"], cover_url: "https://covers.openlibrary.org/b/isbn/9782012101562-M.jpg",
    publisher: "Gallimard Jeunesse", published_year: 1998, page_count: 320,
    book_type: "livre", status: "en_cours", rating: 4, series_name: "Harry Potter", series_index: 1,
    added_by: "user1", added_at: "2026-03-15T10:00:00Z", updated_at: "2026-03-15T10:00:00Z", library_id: "lib1",
  },
  {
    id: "b4", isbn: "9782344009888", title: "Naruto, tome 1",
    authors: ["Masashi Kishimoto"], cover_url: "https://covers.openlibrary.org/b/isbn/9782344009888-M.jpg",
    publisher: "Kana", published_year: 1999, page_count: 192,
    book_type: "manga", status: "a_lire", series_name: "Naruto", series_index: 1,
    added_by: "user2", added_at: "2026-04-20T10:00:00Z", updated_at: "2026-04-20T10:00:00Z", library_id: "lib1",
  },
  {
    id: "b5", isbn: "9782070628070", title: "L'Étranger",
    authors: ["Albert Camus"], cover_url: "https://covers.openlibrary.org/b/isbn/9782070628070-M.jpg",
    publisher: "Gallimard", published_year: 1942, page_count: 186,
    book_type: "livre", status: "lu", rating: 5,
    added_by: "user1", added_at: "2026-05-05T10:00:00Z", updated_at: "2026-05-05T10:00:00Z", library_id: "lib1",
  },
  {
    id: "b6", isbn: "9782070413119", title: "Le Petit Prince",
    authors: ["Antoine de Saint-Exupéry"], cover_url: "https://covers.openlibrary.org/b/isbn/9782070413119-M.jpg",
    publisher: "Gallimard", published_year: 1943, page_count: 96,
    book_type: "livre", status: "lu", rating: 5,
    added_by: "user1", added_at: "2026-05-10T10:00:00Z", updated_at: "2026-05-10T10:00:00Z", library_id: "lib1",
  },
  {
    id: "b7", isbn: "9782290349229", title: "Dune",
    authors: ["Frank Herbert"], cover_url: "https://covers.openlibrary.org/b/isbn/9782290349229-M.jpg",
    publisher: "Pocket", published_year: 1965, page_count: 896,
    book_type: "livre", status: "a_lire",
    added_by: "user1", added_at: "2026-05-20T10:00:00Z", updated_at: "2026-05-20T10:00:00Z", library_id: "lib1",
  },
];

let idCounter = 20;

export function getBooks(library_id: string): Book[] {
  return books.filter(b => b.library_id === library_id);
}

export function addBook(book: Omit<Book, "id" | "added_at" | "updated_at">): Book {
  const newBook: Book = {
    ...book,
    id: `b${idCounter++}`,
    added_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
  books.push(newBook);
  return newBook;
}

export function updateBook(id: string, updates: Partial<Book>): Book | null {
  const idx = books.findIndex(b => b.id === id);
  if (idx === -1) return null;
  books[idx] = { ...books[idx], ...updates, updated_at: new Date().toISOString() };
  return books[idx];
}

export function deleteBook(id: string): boolean {
  const prev = books.length;
  books = books.filter(b => b.id !== id);
  return books.length < prev;
}
