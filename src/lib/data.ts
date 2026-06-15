import { Book, Collection, Wishlist } from "@/types";
import { LIBRARY_ID, USER_ID } from "@/lib/constants";

// ─── Books ────────────────────────────────────────────────────────────────────
let books: Book[] = [
  { id:"b1", isbn:"9782070360024", title:"Le Seigneur des Anneaux", authors:["J.R.R. Tolkien"],  cover_url:"https://covers.openlibrary.org/b/isbn/9782070360024-M.jpg", book_type:"livre", status:"lu",       rating:5, library_id:LIBRARY_ID, added_by:USER_ID, added_at:"2025-01-10T00:00:00Z", updated_at:"2025-01-10T00:00:00Z" },
  { id:"b2", isbn:"9782205055375", title:"Astérix le Gaulois",      authors:["Goscinny","Uderzo"], cover_url:"https://covers.openlibrary.org/b/isbn/9782205055375-M.jpg", book_type:"bd",    status:"lu",       rating:4, library_id:LIBRARY_ID, added_by:USER_ID, added_at:"2025-02-01T00:00:00Z", updated_at:"2025-02-01T00:00:00Z", series_name:"Astérix", series_index:1 },
  { id:"b3", isbn:"9782012101562", title:"Harry Potter T.1",        authors:["J.K. Rowling"],     cover_url:"https://covers.openlibrary.org/b/isbn/9782012101562-M.jpg", book_type:"livre", status:"en_cours", rating:4, library_id:LIBRARY_ID, added_by:USER_ID, added_at:"2026-03-15T00:00:00Z", updated_at:"2026-03-15T00:00:00Z", series_name:"Harry Potter", series_index:1 },
  { id:"b4", isbn:"9782344009888", title:"Naruto, tome 1",          authors:["Kishimoto"],        cover_url:"https://covers.openlibrary.org/b/isbn/9782344009888-M.jpg", book_type:"manga", status:"a_lire",             library_id:LIBRARY_ID, added_by:USER_ID, added_at:"2026-04-20T00:00:00Z", updated_at:"2026-04-20T00:00:00Z", series_name:"Naruto", series_index:1 },
  { id:"b5", isbn:"9782070628070", title:"L'Étranger",              authors:["Albert Camus"],     cover_url:"https://covers.openlibrary.org/b/isbn/9782070628070-M.jpg", book_type:"livre", status:"lu",       rating:5, library_id:LIBRARY_ID, added_by:USER_ID, added_at:"2026-05-05T00:00:00Z", updated_at:"2026-05-05T00:00:00Z" },
  { id:"b6", isbn:"9782070413119", title:"Le Petit Prince",         authors:["Saint-Exupéry"],    cover_url:"https://covers.openlibrary.org/b/isbn/9782070413119-M.jpg", book_type:"livre", status:"lu",       rating:5, library_id:LIBRARY_ID, added_by:USER_ID, added_at:"2026-05-10T00:00:00Z", updated_at:"2026-05-10T00:00:00Z" },
  { id:"b7", isbn:"9782290349229", title:"Dune",                    authors:["Frank Herbert"],    cover_url:"https://covers.openlibrary.org/b/isbn/9782290349229-M.jpg", book_type:"livre", status:"a_lire",             library_id:LIBRARY_ID, added_by:USER_ID, added_at:"2026-05-20T00:00:00Z", updated_at:"2026-05-20T00:00:00Z" },
];
let bookId = 100;

export const getBooks   = (lid: string): Book[] => books.filter(b => b.library_id === lid);
export const addBook    = (b: Omit<Book, "id" | "added_at" | "updated_at">): Book => { const now = new Date().toISOString(); const nb = { ...b, id: `b${bookId++}`, added_at: now, updated_at: now }; books.push(nb); return nb; };
export const updateBook = (id: string, u: Partial<Book>): void => { books = books.map(b => b.id === id ? { ...b, ...u, updated_at: new Date().toISOString() } : b); };
export const deleteBook = (id: string): void => { books = books.filter(b => b.id !== id); };

// ─── Collections ──────────────────────────────────────────────────────────────
let collections: Collection[] = [
  { id:"c1", library_id:LIBRARY_ID, name:"Astérix",     author:"Goscinny & Uderzo", cover_url:"https://covers.openlibrary.org/b/isbn/9782205055375-M.jpg", book_type:"bd",    total_volumes:40, owned_volumes:[1,2,3,4,5,8,10,12], created_at:"2024-01-01T00:00:00Z", updated_at:"2024-06-01T00:00:00Z" },
  { id:"c2", library_id:LIBRARY_ID, name:"Naruto",       author:"Masashi Kishimoto", cover_url:"https://covers.openlibrary.org/b/isbn/9782344009888-M.jpg", book_type:"manga", total_volumes:72, owned_volumes:[1,2,3,4,5,11,12],  created_at:"2024-01-01T00:00:00Z", updated_at:"2024-06-01T00:00:00Z" },
  { id:"c3", library_id:LIBRARY_ID, name:"Harry Potter", author:"J.K. Rowling",      cover_url:"https://covers.openlibrary.org/b/isbn/9782012101562-M.jpg", book_type:"livre", total_volumes:7,  owned_volumes:[1,2,3],            created_at:"2024-01-01T00:00:00Z", updated_at:"2024-06-01T00:00:00Z" },
];
let colId = 100;

export const getCollections   = (lid: string): Collection[] => collections.filter(c => c.library_id === lid);
export const addCollection    = (c: Omit<Collection, "id" | "created_at" | "updated_at">): Collection => { const now = new Date().toISOString(); const nc = { ...c, id: `c${colId++}`, created_at: now, updated_at: now }; collections.push(nc); return nc; };
export const updateCollection = (id: string, vols: number[]): void => { collections = collections.map(c => c.id === id ? { ...c, owned_volumes: vols, updated_at: new Date().toISOString() } : c); };

export function resolveCollection(
  lid: string, name: string, idx: number,
  cover?: string, author?: string, type: Book["book_type"] = "bd"
): { collection: Collection; isNew: boolean; isNewVolume: boolean } {
  const existing = collections.find(c => c.library_id === lid && c.name.toLowerCase() === name.toLowerCase());
  if (existing) {
    const isNewVolume = !existing.owned_volumes.includes(idx);
    if (isNewVolume) updateCollection(existing.id, [...existing.owned_volumes, idx].sort((a, b) => a - b));
    return { collection: existing, isNew: false, isNewVolume };
  }
  const nc = addCollection({ library_id: lid, name, author, cover_url: cover, book_type: type, owned_volumes: [idx] });
  return { collection: nc, isNew: true, isNewVolume: true };
}

// ─── Wishlists ────────────────────────────────────────────────────────────────
const wishlists = new Map<string, Wishlist>();

wishlists.set("wl_demo", {
  id: "wl_demo",
  collection_id: "c1",
  collection_name: "Astérix",
  owner_name: "Garance",
  missing_items: [
    { id: "wi_1", title: "Astérix — Tome 6", authors: ["Goscinny", "Uderzo"], series_index: 6 },
    { id: "wi_2", title: "Astérix — Tome 7", authors: ["Goscinny", "Uderzo"], series_index: 7 },
  ],
  created_at: new Date().toISOString(),
});

export const getWishlist = (id: string): Wishlist | null => wishlists.get(id) ?? null;

export const claimItem = (wid: string, iid: string, name: string): boolean => {
  const wl = wishlists.get(wid);
  if (!wl) return false;
  const it = wl.missing_items.find(i => i.id === iid);
  if (!it || it.claimed_by_name) return false;
  it.claimed_by_name = name;
  it.claimed_at = new Date().toISOString();
  return true;
};

export const createWishlist = (col: Collection, owner: string): Wishlist => {
  const total   = col.total_volumes ?? 0;
  const missing = Array.from({ length: total }, (_, i) => i + 1).filter(n => !col.owned_volumes.includes(n));
  const wl: Wishlist = {
    id: `wl_${Date.now()}`,
    collection_id: col.id,
    collection_name: col.name,
    owner_name: owner,
    missing_items: missing.map((n, i) => ({
      id: `wi_${i}`,
      title: `${col.name} — Tome ${n}`,
      authors: col.author ? [col.author] : [],
      series_index: n,
    })),
    created_at: new Date().toISOString(),
  };
  wishlists.set(wl.id, wl);
  return wl;
};
