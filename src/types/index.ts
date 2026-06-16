// ─── Core types ───────────────────────────────────────────────────────────────

export type ReadStatus = "lu" | "en_cours" | "a_lire";
export type BookType   = "livre" | "bd" | "manga";

export interface Book {
  id: string;
  isbn?: string;
  title: string;
  authors: string[];
  cover_url?: string;
  publisher?: string;
  published_year?: number;
  page_count?: number;
  description?: string;
  book_type: BookType;
  status: ReadStatus;
  rating?: number;       // 1–5
  note?: string;
  series_name?: string;
  series_index?: number;
  collection_id?: string;
  library_id: string;
  added_by: string;
  added_at: string;
  updated_at: string;
}

export interface Collection {
  id: string;
  library_id: string;
  name: string;
  author?: string;
  cover_url?: string;
  book_type: BookType;
  total_volumes?: number;
  owned_volumes: number[];
  created_at: string;
  updated_at: string;
}

export interface WishlistItem {
  id: string;
  title: string;
  authors: string[];
  cover_url?: string;
  series_index?: number;
  isbn?: string;
  claimed_by_name?: string;
  claimed_at?: string;
}

export interface Wishlist {
  id: string;
  collection_id: string;
  collection_name: string;
  owner_name: string;
  missing_items: WishlistItem[];
  created_at: string;
}

export interface SharedLibrary {
  wishlist_id: string;
  collection_name: string;
  owner_name: string;
  shared_at: string;
  missing_count: number;
  claimed_count: number;
  cover_url?: string;
}

// ─── API response ─────────────────────────────────────────────────────────────

export interface LookupResult {
  isbn: string;
  title: string;
  authors: string[];
  cover_url?: string;
  publisher?: string;
  published_year?: number;
  page_count?: number;
  description?: string;
  series_name?: string;
  series_index?: number;
  book_type: BookType;
  _unreliable?: boolean;
}

export interface ScanResult {
  book: LookupResult;
  collection?: Collection;
  isNewCollection: boolean;
  isNewVolume: boolean;
}
