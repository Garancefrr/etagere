export type ReadStatus = "lu" | "en_cours" | "a_lire";
export type BookType = "livre" | "bd" | "manga";

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
  rating?: number;
  note?: string;
  series_name?: string;
  series_index?: number;
  collection_id?: string;
  added_by: string;
  added_at: string;
  updated_at: string;
  library_id: string;
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

export interface Library {
  id: string;
  name: string;
  owner_id: string;
  created_at: string;
}

export interface LibraryMember {
  library_id: string;
  user_id: string;
  role: "owner" | "member";
  joined_at: string;
}

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
}

export interface ScanResult {
  book: LookupResult;
  collection?: Collection;
  isNewCollection: boolean;
  isNewVolume: boolean;
}
