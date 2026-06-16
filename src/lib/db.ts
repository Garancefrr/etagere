import { createServerClient } from "@/lib/supabase";
import { Book, Collection, Wishlist } from "@/types";

// ── Library ───────────────────────────────────────────────────────────────────

export async function getLibraryId(userId: string): Promise<string> {
  const db = createServerClient();
  const { data, error } = await db
    .from("libraries").select("id").eq("owner_id", userId).single();
  if (error || !data) throw new Error(`Library not found for user ${userId}`);
  return data.id;
}

// ── Books ─────────────────────────────────────────────────────────────────────

export async function getBooks(libraryId: string): Promise<Book[]> {
  const db = createServerClient();
  const { data, error } = await db
    .from("books").select("*").eq("library_id", libraryId).order("added_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Book[];
}

export async function insertBook(book: Omit<Book, "id" | "added_at" | "updated_at">): Promise<Book> {
  const db = createServerClient();
  const { data, error } = await db.from("books").insert(book).select().single();
  if (error) throw error;
  return data as Book;
}

export async function patchBook(id: string, updates: Partial<Book>): Promise<void> {
  const db = createServerClient();
  const { error } = await db.from("books")
    .update({ ...updates, updated_at: new Date().toISOString() }).eq("id", id);
  if (error) throw error;
}

export async function removeBook(id: string): Promise<void> {
  const db = createServerClient();
  const { error } = await db.from("books").delete().eq("id", id);
  if (error) throw error;
}

// ── Collections ───────────────────────────────────────────────────────────────

export async function getCollections(libraryId: string): Promise<Collection[]> {
  const db = createServerClient();
  const { data, error } = await db
    .from("collections").select("*").eq("library_id", libraryId).order("name");
  if (error) throw error;
  return (data ?? []) as Collection[];
}

export async function findCollection(libraryId: string, name: string): Promise<Collection | null> {
  const db = createServerClient();
  const { data } = await db
    .from("collections").select("*").eq("library_id", libraryId).ilike("name", name).maybeSingle();
  return data as Collection | null;
}

export async function insertCollection(col: Omit<Collection, "id" | "created_at" | "updated_at">): Promise<Collection> {
  const db = createServerClient();
  const { data, error } = await db.from("collections").insert(col).select().single();
  if (error) throw error;
  return data as Collection;
}

export async function addVolumeToCollection(id: string, currentVolumes: number[], newVolume: number): Promise<void> {
  const db = createServerClient();
  const merged  = currentVolumes.includes(newVolume) ? currentVolumes : [...currentVolumes, newVolume];
  const volumes = merged.sort((a, b) => a - b);
  const { error } = await db.from("collections")
    .update({ owned_volumes: volumes, updated_at: new Date().toISOString() }).eq("id", id);
  if (error) throw error;
}

export async function resolveCollection(
  libraryId: string, seriesName: string, seriesIndex: number,
  opts: { cover_url?: string; author?: string; book_type?: Collection["book_type"] }
): Promise<{ collection: Collection; isNew: boolean; isNewVolume: boolean }> {
  const existing = await findCollection(libraryId, seriesName);
  if (existing) {
    const isNewVolume = !existing.owned_volumes.includes(seriesIndex);
    if (isNewVolume) {
      await addVolumeToCollection(existing.id, existing.owned_volumes, seriesIndex);
      existing.owned_volumes = [...existing.owned_volumes, seriesIndex].sort((a, b) => a - b);
    }
    return { collection: existing, isNew: false, isNewVolume };
  }
  const newCol = await insertCollection({
    library_id: libraryId, name: seriesName, author: opts.author,
    cover_url: opts.cover_url, book_type: opts.book_type ?? "bd", owned_volumes: [seriesIndex],
  });
  return { collection: newCol, isNew: true, isNewVolume: true };
}

// ── Wishlists ─────────────────────────────────────────────────────────────────

export async function getWishlist(id: string): Promise<Wishlist | null> {
  const db = createServerClient();
  const { data } = await db.from("wishlists").select("*").eq("id", id).maybeSingle();
  if (!data) return null;
  return { id: data.id, collection_id: data.collection_id, collection_name: data.collection_name,
    owner_name: data.owner_name, missing_items: data.missing_items ?? [], created_at: data.created_at } as Wishlist;
}

// ── Shared collections ────────────────────────────────────────────────────────

export async function createShare(collectionId: string, ownerId: string): Promise<string> {
  const db = createServerClient();
  const { data: existing } = await db
    .from("shared_collections").select("token")
    .eq("collection_id", collectionId).eq("owner_id", ownerId).maybeSingle();
  if (existing) return existing.token;
  const { data, error } = await db
    .from("shared_collections").insert({ collection_id: collectionId, owner_id: ownerId })
    .select("token").single();
  if (error) throw error;
  return data.token;
}

export async function getShareByToken(token: string): Promise<{
  id: string; collection: Collection; owner_name: string;
} | null> {
  const db = createServerClient();
  const { data } = await db
    .from("shared_collections")
    .select(`id, owner:profiles!owner_id(name), collection:collections(*)`)
    .eq("token", token).gt("expires_at", new Date().toISOString()).maybeSingle();
  if (!data) return null;
  return { id: data.id, collection: data.collection as unknown as Collection, owner_name: (data.owner as any)?.name ?? "Quelqu'un" };
}

export async function registerViewer(shareId: string, viewerId: string): Promise<void> {
  const db = createServerClient();
  await db.from("collection_viewers")
    .upsert({ shared_id: shareId, viewer_id: viewerId, viewed_at: new Date().toISOString() },
             { onConflict: "shared_id,viewer_id" });
}

export interface SharedWithMe {
  token: string; collection_name: string; owner_name: string;
  shared_at: string; cover_url?: string; total_volumes?: number; owned_volumes: number[];
}

export async function getSharedWithMe(viewerId: string): Promise<SharedWithMe[]> {
  const db = createServerClient();
  const { data } = await db
    .from("collection_viewers")
    .select(`viewed_at, share:shared_collections(token, owner:profiles!owner_id(name), collection:collections(name, cover_url, total_volumes, owned_volumes))`)
    .eq("viewer_id", viewerId).order("viewed_at", { ascending: false });
  return (data ?? []).map((row: any) => ({
    token:           row.share.token,
    collection_name: row.share.collection.name,
    owner_name:      row.share.owner?.name ?? "Quelqu'un",
    shared_at:       row.viewed_at,
    cover_url:       row.share.collection.cover_url,
    total_volumes:   row.share.collection.total_volumes,
    owned_volumes:   row.share.collection.owned_volumes ?? [],
  }));
}

export async function patchCollection(id: string, updates: Partial<Collection>): Promise<void> {
  const db = createServerClient();
  const { error } = await db.from("collections")
    .update({ ...updates, updated_at: new Date().toISOString() }).eq("id", id);
  if (error) throw error;
}

export async function removeCollection(id: string): Promise<void> {
  const db = createServerClient();
  const { error } = await db.from("collections").delete().eq("id", id);
  if (error) throw error;
}
