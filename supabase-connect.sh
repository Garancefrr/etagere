#!/bin/bash
set -e
echo "🔌 Connexion Supabase — persistance des données..."
cd "$(git rev-parse --show-toplevel)"

mkdir -p src/app/api/library src/app/api/books src/app/api/wishlist
cat > "src/lib/supabase.ts" << 'FILEOF'
import { createClient, SupabaseClient } from "@supabase/supabase-js";

const url  = process.env.NEXT_PUBLIC_SUPABASE_URL  ?? "";
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

// Client-side (uses anon key + RLS)
export const supabase: SupabaseClient = url && anon
  ? createClient(url, anon)
  : null as any;

// Server-side (uses service role key, bypasses RLS — API routes only)
export function createServerClient(): SupabaseClient {
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
  return url && serviceKey
    ? createClient(url, serviceKey, { auth: { persistSession: false } })
    : null as any;
}
FILEOF
cat > "src/lib/db.ts" << 'FILEOF'
/**
 * Database access layer — all Supabase queries live here.
 * Every function returns typed data or throws.
 */
import { createServerClient } from "@/lib/supabase";
import { Book, Collection, Wishlist } from "@/types";

// ── Library ───────────────────────────────────────────────────────────────────

export async function getLibraryId(userId: string): Promise<string> {
  const db = createServerClient();
  const { data, error } = await db
    .from("libraries")
    .select("id")
    .eq("owner_id", userId)
    .single();
  if (error || !data) throw new Error(`Library not found for user ${userId}`);
  return data.id;
}

// ── Books ─────────────────────────────────────────────────────────────────────

export async function getBooks(libraryId: string): Promise<Book[]> {
  const db = createServerClient();
  const { data, error } = await db
    .from("books")
    .select("*")
    .eq("library_id", libraryId)
    .order("added_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Book[];
}

export async function insertBook(
  book: Omit<Book, "id" | "added_at" | "updated_at">
): Promise<Book> {
  const db = createServerClient();
  const { data, error } = await db
    .from("books")
    .insert(book)
    .select()
    .single();
  if (error) throw error;
  return data as Book;
}

export async function patchBook(id: string, updates: Partial<Book>): Promise<void> {
  const db = createServerClient();
  const { error } = await db
    .from("books")
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq("id", id);
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
    .from("collections")
    .select("*")
    .eq("library_id", libraryId)
    .order("name");
  if (error) throw error;
  return (data ?? []) as Collection[];
}

export async function findCollection(
  libraryId: string,
  name: string
): Promise<Collection | null> {
  const db = createServerClient();
  const { data } = await db
    .from("collections")
    .select("*")
    .eq("library_id", libraryId)
    .ilike("name", name)
    .maybeSingle();
  return data as Collection | null;
}

export async function insertCollection(
  col: Omit<Collection, "id" | "created_at" | "updated_at">
): Promise<Collection> {
  const db = createServerClient();
  const { data, error } = await db
    .from("collections")
    .insert(col)
    .select()
    .single();
  if (error) throw error;
  return data as Collection;
}

export async function addVolumeToCollection(
  id: string,
  currentVolumes: number[],
  newVolume: number
): Promise<void> {
  const db = createServerClient();
  const merged = currentVolumes.includes(newVolume) ? currentVolumes : [...currentVolumes, newVolume];
  const volumes = merged.sort((a, b) => a - b);
  const { error } = await db
    .from("collections")
    .update({ owned_volumes: volumes, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw error;
}

// ── Resolve collection (find or create + add volume) ─────────────────────────

export async function resolveCollection(
  libraryId: string,
  seriesName: string,
  seriesIndex: number,
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
    library_id:    libraryId,
    name:          seriesName,
    author:        opts.author,
    cover_url:     opts.cover_url,
    book_type:     opts.book_type ?? "bd",
    owned_volumes: [seriesIndex],
  });
  return { collection: newCol, isNew: true, isNewVolume: true };
}

// ── Wishlists ─────────────────────────────────────────────────────────────────

export async function getWishlist(id: string): Promise<Wishlist | null> {
  const db = createServerClient();
  const { data } = await db
    .from("wishlists")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (!data) return null;
  return {
    id:              data.id,
    collection_id:   data.collection_id,
    collection_name: data.collection_name,
    owner_name:      data.owner_name,
    missing_items:   data.missing_items ?? [],
    created_at:      data.created_at,
  } as Wishlist;
}
FILEOF
cat > "src/app/api/library/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getLibraryId } from "@/lib/db";

export async function GET(req: NextRequest) {
  const userId = req.nextUrl.searchParams.get("user_id");
  if (!userId) return NextResponse.json({ error: "user_id manquant" }, { status: 400 });
  try {
    const id = await getLibraryId(userId);
    return NextResponse.json({ id });
  } catch {
    return NextResponse.json({ error: "Bibliothèque introuvable" }, { status: 404 });
  }
}
FILEOF
cat > "src/app/api/books/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getBooks, patchBook, removeBook } from "@/lib/db";

export async function GET(req: NextRequest) {
  const libraryId = req.nextUrl.searchParams.get("library_id");
  if (!libraryId) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
  const books = await getBooks(libraryId);
  return NextResponse.json(books);
}

export async function PATCH(req: NextRequest) {
  const { id, ...updates } = await req.json();
  await patchBook(id, updates);
  return NextResponse.json({ ok: true });
}

export async function DELETE(req: NextRequest) {
  const { id } = await req.json();
  await removeBook(id);
  return NextResponse.json({ ok: true });
}
FILEOF
cat > "src/app/api/books/add/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { insertBook } from "@/lib/db";
import { Book } from "@/types";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as Omit<Book, "id" | "added_at" | "updated_at">;
    const book = await insertBook(body);
    return NextResponse.json(book);
  } catch (e) {
    console.error("Insert book error:", e);
    return NextResponse.json({ error: "Erreur lors de l'ajout" }, { status: 500 });
  }
}
FILEOF
cat > "src/app/api/books/lookup/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { lookupISBN } from "@/lib/isbn-lookup";
import { resolveCollection } from "@/lib/db";
import { ScanResult } from "@/types";

export async function GET(req: NextRequest) {
  const isbn      = req.nextUrl.searchParams.get("isbn");
  const libraryId = req.nextUrl.searchParams.get("library_id");

  if (!isbn)      return NextResponse.json({ error: "ISBN manquant" },        { status: 400 });
  if (!libraryId) return NextResponse.json({ error: "library_id manquant" },  { status: 400 });

  const book = await lookupISBN(isbn);
  if (!book) return NextResponse.json({ error: "Livre introuvable" }, { status: 404 });

  // Auto-resolve collection for BD and manga with series info
  const isSeriesType = book.book_type === "bd" || book.book_type === "manga";
  if (book.series_name && book.series_index !== undefined && isSeriesType) {
    try {
      const { collection, isNew, isNewVolume } = await resolveCollection(
        libraryId,
        book.series_name,
        book.series_index,
        { cover_url: book.cover_url, author: book.authors[0], book_type: book.book_type }
      );
      return NextResponse.json({
        book,
        collection,
        isNewCollection: isNew,
        isNewVolume,
      } satisfies ScanResult);
    } catch (e) {
      console.error("Collection resolve error:", e);
    }
  }

  return NextResponse.json({ book, isNewCollection: false, isNewVolume: false } satisfies ScanResult);
}
FILEOF
cat > "src/app/api/collections/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getCollections } from "@/lib/db";

export async function GET(req: NextRequest) {
  const libraryId = req.nextUrl.searchParams.get("library_id");
  if (!libraryId) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
  const collections = await getCollections(libraryId);
  return NextResponse.json(collections);
}
FILEOF
cat > "src/app/api/wishlist/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getWishlist } from "@/lib/db";

export async function GET(req: NextRequest) {
  const id = req.nextUrl.searchParams.get("id");
  if (!id) return NextResponse.json({ error: "id manquant" }, { status: 400 });
  const wishlist = await getWishlist(id);
  if (!wishlist) return NextResponse.json({ error: "Wishlist introuvable" }, { status: 404 });
  return NextResponse.json(wishlist);
}
FILEOF
cat > "src/app/library/page.tsx" << 'FILEOF'
"use client";
import { useState, useMemo, useEffect, useCallback } from "react";
import { useSession } from "next-auth/react";
import { Book, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import BookCard from "@/components/book/BookCard";
import BookDetail from "@/components/book/BookDetail";
import BottomNav from "@/components/layout/BottomNav";
import { Search, SlidersHorizontal, LayoutGrid, List } from "lucide-react";

type Layout       = "grid" | "list";
type FilterType   = BookType | "all";
type FilterStatus = ReadStatus | "all";

export default function LibraryPage() {
  const { data: session } = useSession();
  const [books,        setBooks]        = useState<Book[]>([]);
  const [libraryId,    setLibraryId]    = useState<string | null>(null);
  const [loading,      setLoading]      = useState(true);
  const [search,       setSearch]       = useState("");
  const [filterStatus, setFilterStatus] = useState<FilterStatus>("all");
  const [filterType,   setFilterType]   = useState<FilterType>("all");
  const [layout,       setLayout]       = useState<Layout>("grid");
  const [selected,     setSelected]     = useState<Book | null>(null);
  const [showFilters,  setShowFilters]  = useState(false);

  // ── Fetch library + books ─────────────────────────────────────────────────
  const fetchBooks = useCallback(async (lid: string) => {
    const res = await fetch(`/api/books?library_id=${lid}`);
    if (res.ok) setBooks(await res.json());
  }, []);

  useEffect(() => {
    if (!session?.user?.id) return;
    (async () => {
      // Get the user's library id
      const res = await fetch(`/api/library?user_id=${session.user.id}`);
      if (res.ok) {
        const { id } = await res.json();
        setLibraryId(id);
        await fetchBooks(id);
      }
      setLoading(false);
    })();
  }, [session, fetchBooks]);

  const stats = useMemo(() => ({
    lu:       books.filter(b => b.status === "lu").length,
    en_cours: books.filter(b => b.status === "en_cours").length,
    a_lire:   books.filter(b => b.status === "a_lire").length,
  }), [books]);

  const filtered = useMemo(() => books.filter(b => {
    const matchSearch = !search
      || b.title.toLowerCase().includes(search.toLowerCase())
      || b.authors.some(a => a.toLowerCase().includes(search.toLowerCase()));
    const matchStatus = filterStatus === "all" || b.status === filterStatus;
    const matchType   = filterType   === "all" || b.book_type === filterType;
    return matchSearch && matchStatus && matchType;
  }), [books, search, filterStatus, filterType]);

  const handleUpdate = async (id: string, updates: Partial<Book>) => {
    await fetch("/api/books", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id, ...updates }) });
    setBooks(prev => prev.map(b => b.id === id ? { ...b, ...updates } : b));
    setSelected(prev => prev?.id === id ? { ...prev, ...updates } as Book : prev);
  };

  const handleDelete = async (id: string) => {
    await fetch("/api/books", { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id }) });
    setBooks(prev => prev.filter(b => b.id !== id));
    setSelected(null);
  };

  const userName = session?.user?.name?.split(" ")[0] ?? "Toi";

  return (
    <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>

      <div className="sticky top-0 z-30 px-4 pt-12 pb-3" style={{ background: "var(--bg)" }}>
        {/* Hero */}
        <div className="rounded-2xl p-4 mb-4 flex items-center justify-between relative overflow-hidden"
          style={{ background: "var(--accent)" }}>
          <div className="absolute right-[-20px] top-[-20px] w-28 h-28 rounded-full"
            style={{ background: "rgba(255,255,255,0.07)" }} />
          <div>
            <p className="font-bold text-white" style={{ fontSize: 16 }}>Bienvenue {userName} 👋</p>
            <div className="flex gap-5 mt-2">
              {(["lu","en_cours","a_lire"] as ReadStatus[]).map(s => (
                <div key={s}>
                  <p className="font-bold text-white leading-none" style={{ fontSize: 22 }}>{stats[s]}</p>
                  <p style={{ color: "rgba(255,255,255,0.6)", fontSize: 12, marginTop: 2 }}>{STATUS_CONFIG[s].label}</p>
                </div>
              ))}
            </div>
          </div>
          {session?.user?.image
            ? <img src={session.user.image} alt="" className="w-12 h-12 rounded-xl flex-shrink-0" />
            : <div className="w-12 h-12 rounded-xl flex items-center justify-center font-bold flex-shrink-0"
                style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>
                {userName[0]}
              </div>}
        </div>

        {/* Search row */}
        <div className="flex gap-2 mb-3">
          <div className="flex-1 flex items-center gap-2 px-4 py-3 rounded-2xl"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <Search className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
            <input type="text" value={search} onChange={e => setSearch(e.target.value)}
              placeholder="Titre, auteur..."
              className="flex-1 outline-none bg-transparent"
              style={{ color: "var(--txt1)", fontSize: 15 }} />
          </div>
          <button onClick={() => setLayout(l => l === "grid" ? "list" : "grid")}
            className="w-11 h-11 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            {layout === "grid" ? <List className="w-5 h-5" style={{ color: "var(--txt2)" }} /> : <LayoutGrid className="w-5 h-5" style={{ color: "var(--txt2)" }} />}
          </button>
          <button onClick={() => setShowFilters(f => !f)}
            className="w-11 h-11 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{ background: showFilters ? "var(--accent)" : "var(--surface)", border: `1px solid ${showFilters ? "var(--accent)" : "var(--border)"}` }}>
            <SlidersHorizontal className="w-5 h-5" style={{ color: showFilters ? "#fff" : "var(--txt2)" }} />
          </button>
        </div>

        {showFilters && (
          <div className="space-y-2 mb-2">
            <FilterRow
              options={[{ v: "all", l: "Tous" }, ...Object.entries(STATUS_CONFIG).map(([v, c]) => ({ v, l: `${c.emoji} ${c.label}` }))]}
              value={filterStatus} onChange={v => setFilterStatus(v as FilterStatus)} />
            <FilterRow
              options={[{ v: "all", l: "Tous types" }, ...Object.entries(TYPE_CONFIG).map(([v, c]) => ({ v, l: `${c.emoji} ${c.label}` }))]}
              value={filterType} onChange={v => setFilterType(v as FilterType)} />
          </div>
        )}
      </div>

      <div className="flex justify-between px-4 mb-3">
        <span className="font-bold" style={{ fontSize: 15, color: "var(--txt1)" }}>
          {loading ? "Chargement…" : `${filtered.length} ouvrage${filtered.length > 1 ? "s" : ""}`}
        </span>
      </div>

      <div className="px-4">
        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
          </div>
        ) : filtered.length === 0 ? (
          <Empty hasBooks={books.length > 0} />
        ) : layout === "grid" ? (
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: 12 }}>
            {filtered.map(b => <BookCard key={b.id} book={b} onClick={() => setSelected(b)} />)}
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {filtered.map(b => <BookListRow key={b.id} book={b} onClick={() => setSelected(b)} />)}
          </div>
        )}
      </div>

      {selected && (
        <BookDetail book={selected} onClose={() => setSelected(null)} onUpdate={handleUpdate} onDelete={handleDelete} />
      )}
      <BottomNav />
    </div>
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function FilterRow({ options, value, onChange }: { options: { v: string; l: string }[]; value: string; onChange: (v: string) => void }) {
  return (
    <div className="flex gap-2 overflow-x-auto pb-1" style={{ scrollbarWidth: "none" }}>
      {options.map(({ v, l }) => (
        <button key={v} onClick={() => onChange(v)}
          className="flex-shrink-0 px-4 py-2 rounded-full font-semibold"
          style={{ fontSize: 13, background: value === v ? "var(--accent)" : "var(--surface)", color: value === v ? "#fff" : "var(--txt2)", border: `1px solid ${value === v ? "var(--accent)" : "var(--border)"}` }}>
          {l}
        </button>
      ))}
    </div>
  );
}

function BookListRow({ book, onClick }: { book: Book; onClick: () => void }) {
  const { bg, color, label } = STATUS_CONFIG[book.status];
  return (
    <button onClick={onClick} className="flex items-center gap-3 p-3 rounded-2xl text-left active:scale-[0.98]"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
      <div className="rounded-xl overflow-hidden flex-shrink-0" style={{ width: 52, height: 72, background: "var(--placeholder)" }}>
        {book.cover_url && <img src={book.cover_url} alt="" className="w-full h-full object-cover" />}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-semibold truncate" style={{ fontSize: 15, color: "var(--txt1)" }}>{book.title}</p>
        <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{book.authors[0]}</p>
        {book.series_name && <p style={{ fontSize: 12, color: "var(--accent)", marginTop: 2 }}>{book.series_name} #{book.series_index}</p>}
      </div>
      <span className="px-3 py-1.5 rounded-full font-semibold flex-shrink-0" style={{ fontSize: 12, background: bg, color }}>{label}</span>
    </button>
  );
}

function Empty({ hasBooks }: { hasBooks: boolean }) {
  return (
    <div className="flex flex-col items-center py-20 gap-3">
      <p className="font-semibold" style={{ fontSize: 17, color: "var(--txt1)" }}>
        {hasBooks ? "Aucun résultat" : "Bibliothèque vide"}
      </p>
      <p style={{ fontSize: 14, color: "var(--txt3)" }}>
        {hasBooks ? "Essayez un autre filtre" : "Scannez votre premier livre !"}
      </p>
    </div>
  );
}
FILEOF
cat > "src/app/scan/page.tsx" << 'FILEOF'
"use client";
import { useState, useCallback, useEffect } from "react";
import { useSession } from "next-auth/react";
import { ScanResult, ReadStatus, BookType } from "@/types";
import BottomNav from "@/components/layout/BottomNav";
import Scanner from "@/components/scanner/Scanner";
import { ToastStack } from "@/components/ui/Toast";
import { useToast } from "@/hooks/useToast";
import { useFirstUse } from "@/hooks/useFirstUse";
import { ScanLine, Zap, Settings2 } from "lucide-react";

const MODES = [
  { key: false, icon: Settings2, label: "Mode classique", sub: "Confirmation avant ajout" },
  { key: true,  icon: Zap,       label: "Mode rapide",    sub: "Ajout instantané en série" },
] as const;

export default function ScanPage() {
  const { data: session } = useSession();
  const [scanning,  setScanning]  = useState(false);
  const [rapidMode, setRapidMode] = useState(false);
  const [libraryId, setLibraryId] = useState<string | null>(null);
  const isFirstUse = useFirstUse("folio_scan_seen");
  const { toasts, push, dismiss } = useToast();

  useEffect(() => {
    if (!session?.user?.id) return;
    fetch(`/api/library?user_id=${session.user.id}`)
      .then(r => r.json())
      .then(d => setLibraryId(d.id))
      .catch(() => {});
  }, [session]);

  const handleSuccess = useCallback((result: ScanResult) => {
    if (rapidMode) {
      push(result.book.title, result.isNewCollection ? `Collection « ${result.collection?.name} » créée` : result.isNewVolume ? `Ajouté à ${result.collection?.name}` : undefined);
    } else {
      setScanning(false);
      push("Ajouté !", result.book.title);
    }
  }, [rapidMode, push]);

  if (isFirstUse === null) return null;

  return (
    <>
      <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>
        <div className="px-4 pt-12 pb-4">
          <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Ajouter</p>
          <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Scanner</h1>
        </div>

        {/* Mode toggle */}
        <div className="mx-4 mb-6 flex p-1 rounded-2xl" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          {MODES.map(({ key, icon: Icon, label, sub }) => (
            <button key={String(key)} onClick={() => setRapidMode(key)}
              className="flex-1 flex items-center gap-3 px-3 py-3 rounded-xl transition-all"
              style={{ background: rapidMode === key ? "var(--accent)" : "transparent" }}>
              <Icon className="w-5 h-5 flex-shrink-0" style={{ color: rapidMode === key ? "#fff" : "var(--txt3)" }} />
              <div className="text-left">
                <p className="font-bold" style={{ fontSize: 13, color: rapidMode === key ? "#fff" : "var(--txt1)" }}>{label}</p>
                <p style={{ fontSize: 11, color: rapidMode === key ? "rgba(255,255,255,0.7)" : "var(--txt3)" }}>{sub}</p>
              </div>
            </button>
          ))}
        </div>

        {isFirstUse ? (
          <FirstUseInstructions onStart={() => setScanning(true)} />
        ) : (
          <ScanButton rapidMode={rapidMode} onStart={() => setScanning(true)} />
        )}
      </div>

      {scanning && libraryId && (
        <Scanner
          rapidMode={rapidMode}
          libraryId={libraryId}
          userId={session?.user?.id ?? ""}
          onSuccess={handleSuccess}
          onClose={() => setScanning(false)}
        />
      )}

      <ToastStack toasts={toasts} onDismiss={dismiss} />
      <BottomNav />
    </>
  );
}

function ScanButton({ rapidMode, onStart }: { rapidMode: boolean; onStart: () => void }) {
  return (
    <div className="flex flex-col items-center gap-4 px-5">
      <button onClick={onStart}
        className="w-full py-5 rounded-3xl flex items-center justify-center gap-3 active:scale-95"
        style={{ background: "var(--accent)", boxShadow: "0 8px 32px rgba(59,91,255,0.35)" }}>
        <ScanLine className="w-7 h-7 text-white" />
        <span className="font-bold text-white" style={{ fontSize: 17 }}>
          {rapidMode ? "Lancer le mode rapide" : "Ouvrir le scanner"}
        </span>
      </button>
      <p className="text-center" style={{ fontSize: 13, color: "var(--txt3)" }}>
        {rapidMode ? "Chaque scan est ajouté immédiatement" : "ISBN détecté automatiquement"}
      </p>
    </div>
  );
}

function FirstUseInstructions({ onStart }: { onStart: () => void }) {
  const STEPS = [
    "Pointez la caméra vers le code-barres",
    "La détection est automatique",
    "Les BD créent leur collection automatiquement",
  ];
  return (
    <div className="flex flex-col items-center gap-6 px-5">
      <button onClick={onStart}
        className="w-32 h-32 rounded-3xl flex flex-col items-center justify-center gap-2 active:scale-95"
        style={{ background: "var(--accent)", boxShadow: "0 8px 32px rgba(59,91,255,0.35)" }}>
        <ScanLine className="w-12 h-12 text-white" />
        <span className="font-bold text-white text-sm">Scanner</span>
      </button>
      <div className="text-center">
        <p className="font-bold" style={{ fontSize: 17, color: "var(--txt1)" }}>Scannez le code-barres</p>
        <p style={{ fontSize: 14, color: "var(--txt3)", marginTop: 4 }}>ISBN au dos du livre ou de la BD</p>
      </div>
      <div className="w-full space-y-2">
        {STEPS.map((text, i) => (
          <div key={i} className="flex items-center gap-3 p-4 rounded-2xl"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <span className="w-7 h-7 rounded-full flex items-center justify-center font-bold text-white flex-shrink-0"
              style={{ background: "var(--accent)", fontSize: 13 }}>{i + 1}</span>
            <span style={{ fontSize: 14, color: "var(--txt2)" }}>{text}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
FILEOF
cat > "src/components/scanner/Scanner.tsx" << 'FILEOF'
"use client";
import { useEffect, useRef, useState, useCallback } from "react";
import { BrowserMultiFormatReader } from "@zxing/library";
import { X, Keyboard, Check, Plus, RefreshCw } from "lucide-react";
import { ScanResult, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";

type Phase = "scanning" | "loading" | "confirm" | "not_found" | "error";

interface Props {
  rapidMode: boolean;
  libraryId: string;
  userId: string;
  onSuccess: (result: ScanResult, status: ReadStatus, bookType: BookType) => void;
  onClose: () => void;
}

const CORNERS = [
  { top: -2,    left: -2,  borderTop:    "3px solid #5B7AFF", borderLeft:   "3px solid #5B7AFF", borderRadius: "6px 0 0 0" },
  { top: -2,    right: -2, borderTop:    "3px solid #5B7AFF", borderRight:  "3px solid #5B7AFF", borderRadius: "0 6px 0 0" },
  { bottom: -2, left: -2,  borderBottom: "3px solid #5B7AFF", borderLeft:   "3px solid #5B7AFF", borderRadius: "0 0 0 6px" },
  { bottom: -2, right: -2, borderBottom: "3px solid #5B7AFF", borderRight:  "3px solid #5B7AFF", borderRadius: "0 0 6px 0" },
];

export default function Scanner({ rapidMode, libraryId, userId, onSuccess, onClose }: Props) {
  const videoRef      = useRef<HTMLVideoElement>(null);
  const processingRef = useRef(false);

  const [phase,      setPhase]      = useState<Phase>("scanning");
  const [isbn,       setIsbn]       = useState("");
  const [result,     setResult]     = useState<ScanResult | null>(null);
  const [status,     setStatus]     = useState<ReadStatus>("a_lire");
  const [bookType,   setBookType]   = useState<BookType>("livre");
  const [manual,     setManual]     = useState("");
  const [showManual, setShowManual] = useState(false);

  // ── Camera: start once, never stop ───────────────────────────────────────
  useEffect(() => {
    const reader = new BrowserMultiFormatReader();
    reader.decodeFromVideoDevice(null, videoRef.current!, (r) => {
      if (!r || processingRef.current) return;
      processingRef.current = true;
      lookup(r.getText());
    });
    return () => reader.reset();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const lookup = useCallback(async (code: string) => {
    setIsbn(code);
    setPhase("loading");
    try {
      const res  = await fetch(`/api/books/lookup?isbn=${code}&library_id=${libraryId}`);
      if (!res.ok) { setPhase("not_found"); processingRef.current = false; return; }
      const data: ScanResult = await res.json();
      setResult(data);
      setBookType(data.book.book_type);
      if (rapidMode) {
        await saveBook(data, "a_lire", data.book.book_type);
        setPhase("scanning"); setResult(null); setIsbn("");
        processingRef.current = false;
      } else {
        setPhase("confirm");
        processingRef.current = false; // allow next scan while reading
      }
    } catch {
      setPhase("error");
      processingRef.current = false;
    }
  }, [rapidMode, libraryId]); // eslint-disable-line react-hooks/exhaustive-deps

  const saveBook = async (r: ScanResult, s: ReadStatus, bt: BookType) => {
    await fetch("/api/books/add", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ...r.book,
        book_type:     bt,
        status:        s,
        library_id:    libraryId,
        added_by:      userId,
        collection_id: r.collection?.id,
      }),
    });
    onSuccess(r, s, bt);
  };

  const reset = () => { setPhase("scanning"); setResult(null); setIsbn(""); processingRef.current = false; };
  const handleConfirm = async () => { if (result) { await saveBook(result, status, bookType); reset(); } };

  return (
    <div className="fixed inset-0 z-50 flex flex-col overflow-hidden" style={{ background: "#060818" }}>

      {/* Top bar */}
      <div className="flex items-center justify-between px-5 pt-12 pb-2 flex-shrink-0">
        <button onClick={onClose} className="w-10 h-10 rounded-full flex items-center justify-center"
          style={{ background: "rgba(255,255,255,0.08)" }}>
          <X className="w-5 h-5 text-white" />
        </button>
        <span className="font-bold text-white" style={{ fontSize: 16 }}>{rapidMode ? "⚡ Mode rapide" : "Scanner"}</span>
        <button onClick={() => setShowManual(v => !v)} className="w-10 h-10 rounded-full flex items-center justify-center"
          style={{ background: "rgba(255,255,255,0.08)" }}>
          <Keyboard className="w-5 h-5 text-white" />
        </button>
      </div>

      {rapidMode && (
        <div className="mx-5 mb-1 px-3 py-2 rounded-xl flex-shrink-0"
          style={{ background: "rgba(59,91,255,0.18)", border: "1px solid rgba(91,122,255,0.3)" }}>
          <span style={{ fontSize: 12, color: "#7B80FF" }}>Scan continu — ajout instantané</span>
        </div>
      )}

      {/* Camera — always running */}
      <div className="flex-1 flex items-center justify-center relative min-h-0">
        <div className="relative">
          <video ref={videoRef} style={{ width: 300, height: 220, objectFit: "cover", borderRadius: 12, display: "block" }} />
          <div className="absolute inset-0 pointer-events-none">
            {CORNERS.map((s, i) => <div key={i} className="absolute" style={{ width: 20, height: 20, ...s }} />)}
            <div className="scan-line absolute left-0 right-0"
              style={{ height: 2, background: "linear-gradient(90deg,transparent,#5B7AFF,transparent)" }} />
          </div>
          {phase === "loading" && (
            <div className="absolute top-2 right-2">
              <div className="w-5 h-5 rounded-full border-2 animate-spin"
                style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
            </div>
          )}
        </div>
      </div>

      {/* Manual ISBN */}
      {showManual && (
        <div className="flex gap-2 px-5 mb-2 flex-shrink-0">
          <input type="text" value={manual} onChange={e => setManual(e.target.value)}
            placeholder="Saisir ISBN..." onKeyDown={e => { if (e.key === "Enter" && manual) { processingRef.current = true; lookup(manual); }}}
            className="flex-1 px-4 py-3 rounded-2xl outline-none"
            style={{ background: "rgba(255,255,255,0.08)", color: "white", border: "1px solid rgba(91,122,255,0.3)", fontSize: 15 }} />
          <button onClick={() => { if (manual) { processingRef.current = true; lookup(manual); }}}
            className="px-5 py-3 rounded-2xl font-bold" style={{ background: "var(--accent)", color: "#fff" }}>OK</button>
        </div>
      )}

      {/* Bottom panel — no scroll */}
      <div className="flex-shrink-0 rounded-t-3xl p-4 flex flex-col gap-3"
        style={{ background: "var(--surface)", maxHeight: "45vh", overflow: "hidden" }}>

        {phase === "scanning" && (
          <p className="text-center py-2" style={{ fontSize: 14, color: "var(--txt2)" }}>Centrez le code-barres dans le cadre</p>
        )}
        {phase === "loading" && (
          <div className="flex items-center justify-center gap-3 py-2">
            <div className="w-5 h-5 rounded-full border-2 animate-spin flex-shrink-0"
              style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
            <p style={{ fontSize: 14, color: "var(--txt2)" }}>Recherche {isbn}…</p>
          </div>
        )}
        {(phase === "not_found" || phase === "error") && (
          <div className="flex items-center justify-between gap-3 py-1">
            <p style={{ fontSize: 14, color: phase === "error" ? "var(--miss-t)" : "var(--txt1)" }}>
              {phase === "error" ? "Erreur de connexion" : `Introuvable — ${isbn}`}
            </p>
            <Button onClick={reset} size="sm" variant="secondary"><RefreshCw className="w-4 h-4" /> OK</Button>
          </div>
        )}
        {phase === "confirm" && result && (
          <>
            {result.collection && (
              <div className="flex items-center gap-2 px-3 py-2 rounded-xl flex-shrink-0"
                style={{ background: result.isNewCollection ? "var(--accent-l)" : "var(--have-bg)", border: `1px solid ${result.isNewCollection ? "var(--border)" : "var(--have-b)"}` }}>
                {result.isNewCollection
                  ? <Plus className="w-4 h-4 flex-shrink-0" style={{ color: "var(--accent)" }} />
                  : <Check className="w-4 h-4 flex-shrink-0" style={{ color: "var(--have-t)" }} />}
                <p className="truncate" style={{ fontSize: 13, fontWeight: 600, color: result.isNewCollection ? "var(--accent)" : "var(--have-t)" }}>
                  {result.isNewCollection ? `Collection « ${result.collection.name} » créée` : `Tome ${result.book.series_index} → ${result.collection.name}`}
                </p>
              </div>
            )}
            <div className="flex gap-3 p-3 rounded-2xl flex-shrink-0"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
              <Cover src={result.book.cover_url} alt={result.book.title} width={44} height={62} className="rounded-lg flex-shrink-0" />
              <div className="flex-1 min-w-0">
                <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{result.book.title}</p>
                <p className="truncate" style={{ fontSize: 12, color: "var(--txt2)", marginTop: 2 }}>{result.book.authors.join(", ")}</p>
                {result.book.series_name && (
                  <p style={{ fontSize: 11, color: "var(--accent)", marginTop: 2 }}>{result.book.series_name} #{result.book.series_index}</p>
                )}
              </div>
            </div>
            <div className="flex gap-2 flex-shrink-0">
              {(Object.entries(STATUS_CONFIG) as [ReadStatus, { emoji: string; label: string }][]).map(([v, { emoji, label }]) => (
                <button key={v} onClick={() => setStatus(v)} className="flex-1 py-2 rounded-xl font-semibold"
                  style={{ fontSize: 12, background: status === v ? "var(--accent)" : "var(--surface2)", color: status === v ? "#fff" : "var(--txt2)", border: `1px solid ${status === v ? "var(--accent)" : "var(--border)"}` }}>
                  {emoji} {label}
                </button>
              ))}
            </div>
            <Button onClick={handleConfirm} className="w-full py-3 rounded-2xl flex-shrink-0" style={{ fontSize: 14 }}>
              <Check className="w-4 h-4" /> Ajouter
            </Button>
          </>
        )}
      </div>
    </div>
  );
}
FILEOF

echo "✅ Fichiers mis à jour"
git add -A
git commit -m "feat: connect Supabase — books and collections persist after scan"
git push
echo "🎉 Déployé ! https://etagere.vercel.app"
