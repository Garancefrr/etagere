import { Wishlist, WishlistItem, Collection } from "@/types";

// In-memory store (replace with Supabase)
const wishlists: Map<string, Wishlist> = new Map();

let idCounter = 1;

export function createWishlist(
  collection: Collection,
  ownerName: string,
  missingItems: WishlistItem[]
): Wishlist {
  const id = `wl_${Date.now()}_${idCounter++}`;
  const wishlist: Wishlist = {
    id,
    collection_id: collection.id,
    collection_name: collection.name,
    owner_name: ownerName,
    owner_id: collection.library_id,
    missing_items: missingItems,
    created_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(), // 30 days
  };
  wishlists.set(id, wishlist);
  return wishlist;
}

export function getWishlist(id: string): Wishlist | null {
  return wishlists.get(id) ?? null;
}

export function claimWishlistItem(
  wishlistId: string,
  itemId: string,
  claimerName: string
): boolean {
  const wl = wishlists.get(wishlistId);
  if (!wl) return false;
  const item = wl.missing_items.find(i => i.id === itemId);
  if (!item || item.claimed_by) return false;
  item.claimed_by = "user";
  item.claimed_by_name = claimerName;
  item.claimed_at = new Date().toISOString();
  return true;
}

export function getPublicWishlistUrl(wishlistId: string, baseUrl: string): string {
  return `${baseUrl}/wishlist/${wishlistId}`;
}

// Demo wishlist for testing
const demoWishlist: Wishlist = {
  id: "wl_demo",
  collection_id: "col_demo_1",
  collection_name: "Astérix",
  owner_name: "Garance",
  owner_id: "lib1",
  missing_items: [
    { id: "wi_1", title: "Astérix le Gaulois — Tome 6", authors: ["Goscinny", "Uderzo"], series_index: 6, isbn: "9782205004043" },
    { id: "wi_2", title: "Astérix le Gaulois — Tome 7", authors: ["Goscinny", "Uderzo"], series_index: 7, isbn: "9782205004050" },
  ],
  created_at: new Date().toISOString(),
};
wishlists.set("wl_demo", demoWishlist);
