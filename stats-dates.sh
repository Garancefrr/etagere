#!/bin/bash
set -e
echo "📊 Stats enrichies + dates de lecture..."
cd "$(git rev-parse --show-toplevel)"
cat > "src/types/index.ts" << 'FILEOF'
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
  finished_at?: string | null; // set when status becomes "lu"
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
  _createCollection?: boolean; // true only if a collection should be auto-created (saga or prolific author)
}

export interface ScanResult {
  book: LookupResult;
  collection?: Collection;
  isNewCollection: boolean;
  isNewVolume: boolean;
}
FILEOF
cat > "src/lib/db.ts" << 'FILEOF'
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
  const patch: any = { ...updates, updated_at: new Date().toISOString() };
  // Auto-set finished_at when marking as "lu"
  if (updates.status === "lu" && !updates.finished_at) {
    patch.finished_at = new Date().toISOString();
  }
  // Clear finished_at if un-marking as lu
  if (updates.status && updates.status !== "lu") {
    patch.finished_at = null;
  }
  const { error } = await db.from("books").update(patch).eq("id", id);
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

export async function removeVolumeFromCollection(id: string, currentVolumes: number[], volume: number): Promise<void> {
  const db = createServerClient();
  const volumes = currentVolumes.filter(v => v !== volume);
  const { error } = await db.from("collections")
    .update({ owned_volumes: volumes, updated_at: new Date().toISOString() }).eq("id", id);
  if (error) throw error;
}

export async function getBook(id: string): Promise<Book | null> {
  const db = createServerClient();
  const { data } = await db.from("books").select("*").eq("id", id).maybeSingle();
  return data as Book | null;
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
FILEOF
cat > "src/app/stats/page.tsx" << 'FILEOF'
"use client";
import { useMemo } from "react";
import { useData } from "@/contexts/DataContext";
import BottomNav from "@/components/layout/BottomNav";
import { BookOpen, TrendingUp, FileText, Star, Calendar, Clock } from "lucide-react";

function monthName(m: number) {
  return ["Jan","Fév","Mar","Avr","Mai","Juin","Juil","Aoû","Sep","Oct","Nov","Déc"][m];
}

export default function StatsPage() {
  const { books, loading } = useData();
  const thisYear = new Date().getFullYear();

  const stats = useMemo(() => {
    const lu      = books.filter(b => b.status === "lu");
    const pages   = lu.reduce((s, b) => s + (b.page_count ?? 0), 0);
    const ratings = lu.filter(b => b.rating).map(b => b.rating!);
    const avg     = ratings.length ? (ratings.reduce((a, b) => a + b, 0) / ratings.length).toFixed(1) : null;

    // Use finished_at if available, otherwise added_at for "lu" books
    const finishedThisYear = lu.filter(b => {
      const d = b.finished_at ?? (b.status === "lu" ? b.updated_at : null);
      return d && new Date(d).getFullYear() === thisYear;
    });

    // Added this year (all statuses)
    const addedThisYear = books.filter(b => new Date(b.added_at).getFullYear() === thisYear);

    // Monthly reading activity (finished_at)
    const byMonth: number[] = Array(12).fill(0);
    lu.forEach(b => {
      const d = b.finished_at ?? b.updated_at;
      if (d && new Date(d).getFullYear() === thisYear) {
        byMonth[new Date(d).getMonth()]++;
      }
    });

    // Best reading month
    const bestMonthIdx = byMonth.indexOf(Math.max(...byMonth));
    const bestMonth = byMonth[bestMonthIdx] > 0 ? { name: monthName(bestMonthIdx), count: byMonth[bestMonthIdx] } : null;

    // Type breakdown
    const livres = books.filter(b => b.book_type === "livre").length;
    const bds    = books.filter(b => b.book_type === "bd").length;
    const mangas = books.filter(b => b.book_type === "manga").length;

    // Favorite type
    const typeMax = Math.max(livres, bds, mangas);
    const favType = typeMax === 0 ? null :
      livres === typeMax ? "📖 Livres" :
      bds    === typeMax ? "🎨 BD" : "⛩️ Manga";

    // Top authors
    const authorCount: Record<string, number> = {};
    books.forEach(b => b.authors.forEach(a => { authorCount[a] = (authorCount[a] ?? 0) + 1; }));
    const topAuthors = Object.entries(authorCount).sort((a, b) => b[1] - a[1]).slice(0, 5);

    // Top collection
    const colCount: Record<string, number> = {};
    books.filter(b => b.series_name).forEach(b => {
      const k = b.series_name!;
      colCount[k] = (colCount[k] ?? 0) + 1;
    });
    const topCollection = Object.entries(colCount).sort((a, b) => b[1] - a[1])[0] ?? null;

    // Reading pace (books/month for finished this year)
    const monthsElapsed = new Date().getMonth() + 1;
    const pace = finishedThisYear.length > 0 ? (finishedThisYear.length / monthsElapsed).toFixed(1) : null;

    return {
      total: books.length, lu: lu.length,
      en_cours: books.filter(b => b.status === "en_cours").length,
      a_lire: books.filter(b => b.status === "a_lire").length,
      pages, avg, livres, bds, mangas, favType,
      topAuthors, topCollection,
      finishedThisYear: finishedThisYear.length,
      addedThisYear: addedThisYear.length,
      byMonth, bestMonth, pace,
    };
  }, [books, thisYear]);

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center" style={{ background: "var(--bg)" }}>
      <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
      <BottomNav />
    </div>
  );

  if (stats.total === 0) return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4 pb-24" style={{ background: "var(--bg)" }}>
      <BookOpen className="w-12 h-12" style={{ color: "var(--txt3)", opacity: 0.3 }} />
      <p className="font-bold" style={{ fontSize: 17, color: "var(--txt1)" }}>Aucune stat pour l&apos;instant</p>
      <p className="text-center px-8" style={{ fontSize: 14, color: "var(--txt3)" }}>Scannez vos premiers livres pour voir vos statistiques</p>
      <BottomNav />
    </div>
  );

  const maxMonth = Math.max(...stats.byMonth, 1);

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-12 pb-4">
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Vos stats</p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Tableau de bord</h1>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-3 px-4 mb-4">
        {[
          { icon: BookOpen,   label: "Lus au total",    value: stats.lu,                                          sub: `sur ${stats.total} ouvrages`,  color: "var(--accent)" },
          { icon: TrendingUp, label: `Terminés ${thisYear}`, value: stats.finishedThisYear,                      sub: `ajoutés: ${stats.addedThisYear}`, color: "#22C55E" },
          { icon: FileText,   label: "Pages lues",      value: stats.pages > 0 ? stats.pages.toLocaleString("fr") : "—", sub: "livres terminés",     color: "#FB923C" },
          { icon: Star,       label: "Note moyenne",    value: stats.avg ?? "—",                                  sub: "sur 5 étoiles",                color: "#FBBF24" },
        ].map(({ icon: Icon, label, value, sub, color }) => (
          <div key={label} className="p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
            <div className="w-7 h-7 rounded-lg flex items-center justify-center mb-3" style={{ background: `${color}18` }}>
              <Icon style={{ width: 15, height: 15, color }} />
            </div>
            <p className="text-xl font-bold" style={{ color: "var(--txt1)" }}>{value}</p>
            <p className="text-xs font-bold mt-0.5" style={{ color }}>{label}</p>
            <p className="text-xs mt-0.5" style={{ color: "var(--txt3)" }}>{sub}</p>
          </div>
        ))}
      </div>

      {/* Monthly chart */}
      {stats.finishedThisYear > 0 && (
        <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-bold text-sm" style={{ color: "var(--txt1)" }}>📅 Lectures {thisYear}</h3>
            {stats.bestMonth && (
              <span className="text-xs px-2 py-1 rounded-full font-semibold"
                style={{ background: "var(--accent-l)", color: "var(--accent)" }}>
                🏆 {stats.bestMonth.name} · {stats.bestMonth.count} livre{stats.bestMonth.count > 1 ? "s" : ""}
              </span>
            )}
          </div>
          <div className="flex items-end gap-1.5" style={{ height: 80 }}>
            {stats.byMonth.map((count, i) => (
              <div key={i} className="flex-1 flex flex-col items-center gap-1">
                <div className="w-full rounded-t-md"
                  style={{
                    height: count > 0 ? Math.max(6, (count / maxMonth) * 64) : 4,
                    background: count > 0 ? "var(--accent)" : "var(--border)",
                    opacity: i > new Date().getMonth() ? 0.3 : 1,
                  }} />
                <span style={{ fontSize: 8, color: "var(--txt3)" }}>{monthName(i)}</span>
              </div>
            ))}
          </div>
          {stats.pace && (
            <p className="text-center mt-3" style={{ fontSize: 12, color: "var(--txt3)" }}>
              Rythme : <span style={{ color: "var(--accent)", fontWeight: 700 }}>{stats.pace}</span> livre/mois
            </p>
          )}
        </div>
      )}

      {/* Status */}
      <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Avancement</h3>
        <div className="flex gap-3">
          {[
            { label: "Lus",      n: stats.lu,       emoji: "✅", bg: "var(--have-bg)", color: "var(--have-t)" },
            { label: "En cours", n: stats.en_cours, emoji: "📖", bg: "#FEF9C3",        color: "#A16207" },
            { label: "À lire",   n: stats.a_lire,   emoji: "📌", bg: "var(--accent-l)", color: "var(--accent)" },
          ].map(({ label, n, emoji, bg, color }) => (
            <div key={label} className="flex-1 flex flex-col items-center p-3 rounded-xl" style={{ background: bg }}>
              <span className="text-xl">{emoji}</span>
              <span className="text-xl font-bold mt-1" style={{ color }}>{n}</span>
              <span className="text-xs mt-0.5" style={{ color, opacity: 0.8 }}>{label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Type breakdown */}
      {stats.total > 0 && (
        <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <div className="flex items-center justify-between mb-3">
            <h3 className="font-bold text-sm" style={{ color: "var(--txt1)" }}>Répartition</h3>
            {stats.favType && <span className="text-xs font-semibold" style={{ color: "var(--accent)" }}>Favori : {stats.favType}</span>}
          </div>
          {[
            { label: "📖 Livres", value: stats.livres, color: "var(--accent)" },
            { label: "🎨 BD",     value: stats.bds,    color: "#FB923C" },
            { label: "⛩️ Manga",  value: stats.mangas, color: "#22C55E" },
          ].filter(t => t.value > 0).map(({ label, value, color }) => (
            <div key={label} className="mb-3">
              <div className="flex justify-between mb-1.5">
                <span style={{ fontSize: 13, color: "var(--txt2)" }}>{label}</span>
                <span className="font-bold" style={{ fontSize: 13, color }}>{value}</span>
              </div>
              <div className="h-2 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
                <div className="h-full rounded-full" style={{ width: `${(value / stats.total) * 100}%`, background: color }} />
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Top collection */}
      {stats.topCollection && (
        <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <h3 className="font-bold text-sm mb-2" style={{ color: "var(--txt1)" }}>📚 Collection favorite</h3>
          <div className="flex items-center justify-between">
            <p style={{ fontSize: 15, fontWeight: 600, color: "var(--txt1)" }}>{stats.topCollection[0]}</p>
            <span className="px-2 py-1 rounded-full text-xs font-bold"
              style={{ background: "var(--accent-l)", color: "var(--accent)" }}>
              {stats.topCollection[1]} tome{stats.topCollection[1] > 1 ? "s" : ""}
            </span>
          </div>
        </div>
      )}

      {/* Top authors */}
      {stats.topAuthors.length > 0 && (
        <div className="mx-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>✍️ Auteurs favoris</h3>
          {stats.topAuthors.map(([name, count], i) => (
            <div key={name} className="flex items-center gap-3 py-2">
              <span className="font-bold text-sm w-5 text-center flex-shrink-0" style={{ color: i === 0 ? "#FBBF24" : "var(--txt3)" }}>
                {i === 0 ? "🥇" : i === 1 ? "🥈" : i === 2 ? "🥉" : `${i + 1}`}
              </span>
              <span className="flex-1 text-sm truncate" style={{ color: "var(--txt2)" }}>{name}</span>
              <span className="text-xs font-semibold px-2 py-0.5 rounded-full flex-shrink-0"
                style={{ background: "var(--accent-l)", color: "var(--accent)" }}>
                {count} livre{count > 1 ? "s" : ""}
              </span>
            </div>
          ))}
        </div>
      )}

      <BottomNav />
    </div>
  );
}
FILEOF
git add -A
git commit -m "feat: finished_at date tracking, monthly chart, reading pace, top collection"
git push
echo "🎉 Déployé !"
