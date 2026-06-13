import { Collection, LookupResult, ScanResult, BookType } from "@/types";

// In-memory store (replace with Supabase calls in production)
let collections: Collection[] = [];
let collectionIdCounter = 1;

export function getCollections(library_id: string): Collection[] {
  return collections.filter(c => c.library_id === library_id);
}

export function getCollection(id: string): Collection | undefined {
  return collections.find(c => c.id === id);
}

/**
 * Core logic: given a scan result, determine what to do with collections.
 * - If series_name is present and book_type is bd or manga:
 *   → find or create a collection, add the volume
 * - Otherwise: just return the book with no collection action
 */
export function resolveCollection(
  book: LookupResult,
  library_id: string
): ScanResult {
  const hasSeriesInfo = !!(book.series_name && book.series_index !== undefined);
  const isSeriesType = book.book_type === "bd" || book.book_type === "manga";

  if (!hasSeriesInfo || !isSeriesType) {
    return { book, isNewCollection: false, isNewVolume: false };
  }

  // Look for existing collection with same name (case-insensitive)
  const existing = collections.find(
    c =>
      c.library_id === library_id &&
      c.name.toLowerCase() === book.series_name!.toLowerCase()
  );

  if (existing) {
    const alreadyOwned = existing.owned_volumes.includes(book.series_index!);
    if (!alreadyOwned) {
      existing.owned_volumes = [...existing.owned_volumes, book.series_index!].sort((a, b) => a - b);
      existing.updated_at = new Date().toISOString();
      if (book.cover_url && !existing.cover_url) existing.cover_url = book.cover_url;
    }
    return {
      book,
      collection: existing,
      isNewCollection: false,
      isNewVolume: !alreadyOwned,
    };
  }

  // Create new collection automatically
  const newCollection: Collection = {
    id: `col_${collectionIdCounter++}`,
    library_id,
    name: book.series_name!,
    author: book.authors[0],
    cover_url: book.cover_url,
    book_type: book.book_type,
    total_volumes: undefined, // unknown until more data
    owned_volumes: [book.series_index!],
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
  collections.push(newCollection);

  return {
    book,
    collection: newCollection,
    isNewCollection: true,
    isNewVolume: true,
  };
}

export function createManualCollection(
  library_id: string,
  name: string,
  book_type: BookType,
  author?: string
): Collection {
  const col: Collection = {
    id: `col_${collectionIdCounter++}`,
    library_id,
    name,
    author,
    book_type,
    owned_volumes: [],
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
  collections.push(col);
  return col;
}

export function updateTotalVolumes(collection_id: string, total: number): void {
  const col = collections.find(c => c.id === collection_id);
  if (col) {
    col.total_volumes = total;
    col.updated_at = new Date().toISOString();
  }
}

// Seed demo data
collections = [
  {
    id: "col_demo_1",
    library_id: "lib1",
    name: "Astérix",
    author: "Goscinny & Uderzo",
    cover_url: "https://covers.openlibrary.org/b/isbn/9782205055375-M.jpg",
    book_type: "bd",
    total_volumes: 40,
    owned_volumes: [1, 2, 3, 4, 5, 8, 10, 12],
    created_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-06-01T00:00:00Z",
  },
  {
    id: "col_demo_2",
    library_id: "lib1",
    name: "Naruto",
    author: "Masashi Kishimoto",
    cover_url: "https://covers.openlibrary.org/b/isbn/9782344009888-M.jpg",
    book_type: "manga",
    total_volumes: 72,
    owned_volumes: [1, 2, 3, 4, 5, 11, 12],
    created_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-06-01T00:00:00Z",
  },
  {
    id: "col_demo_3",
    library_id: "lib1",
    name: "Harry Potter",
    author: "J.K. Rowling",
    cover_url: "https://covers.openlibrary.org/b/isbn/9782012101562-M.jpg",
    book_type: "livre",
    total_volumes: 7,
    owned_volumes: [1, 2, 3],
    created_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-06-01T00:00:00Z",
  },
];
collectionIdCounter = 10;
