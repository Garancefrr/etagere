#!/bin/bash
set -e
echo "🧹 Nettoyage complet + réécriture Folio..."
cd "$(git rev-parse --show-toplevel)"

# ── 1. Supprimer les fichiers obsolètes ───────────────────────────────────────
echo "🗑️  Suppression des fichiers obsolètes..."
rm -f src/app/api/share/token/route.ts
rm -f src/app/api/wishlist/route.ts
rm -rf src/app/wishlist
rm -f src/lib/data.ts

# ── 2. Recréer l'arborescence propre ─────────────────────────────────────────
echo "📁 Arborescence..."
mkdir -p \
  src/types \
  src/lib \
  src/hooks \
  src/middleware \
  src/components/ui \
  src/components/book \
  src/components/collection \
  src/components/scanner \
  src/components/layout \
  "src/app/api/auth/[...nextauth]" \
  src/app/api/library \
  src/app/api/books/add \
  src/app/api/books/lookup \
  src/app/api/collections \
  src/app/api/share \
  src/app/api/shared-with-me \
  src/app/library \
  src/app/collections \
  src/app/login \
  src/app/scan \
  src/app/stats \
  src/app/settings \
  "src/app/share/[token]"

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
}

export interface ScanResult {
  book: LookupResult;
  collection?: Collection;
  isNewCollection: boolean;
  isNewVolume: boolean;
}

FILEOF
cat > "src/types/next-auth.d.ts" << 'FILEOF'
import "next-auth";

declare module "next-auth" {
  interface Session {
    user: {
      id: string;
      name?: string | null;
      email?: string | null;
      image?: string | null;
    };
  }
}

FILEOF
cat > "src/lib/constants.ts" << 'FILEOF'
import { ReadStatus, BookType } from "@/types";

export const LIBRARY_ID = "lib1";
export const USER_ID    = "u1";

export const STATUS_CONFIG: Record<ReadStatus, { label: string; emoji: string; bg: string; color: string }> = {
  a_lire:   { label: "À lire",   emoji: "📌", bg: "var(--accent-l)", color: "var(--accent)"  },
  en_cours: { label: "En cours", emoji: "📖", bg: "#FEF9C3",         color: "#A16207"        },
  lu:       { label: "Lu",       emoji: "✅", bg: "var(--have-bg)",  color: "var(--have-t)"  },
};

export const TYPE_CONFIG: Record<BookType, { label: string; emoji: string }> = {
  livre: { label: "Livre", emoji: "📖" },
  bd:    { label: "BD",    emoji: "🎨" },
  manga: { label: "Manga", emoji: "⛩️" },
};

FILEOF
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
cat > "src/lib/isbn-lookup.ts" << 'FILEOF'
import { LookupResult, BookType } from "@/types";

function detectType(terms: string): BookType {
  if (/manga|manhwa|shonen|shojo|seinen|josei/.test(terms)) return "manga";
  if (/bande dessinée|comics|bd|graphic novel/.test(terms))  return "bd";
  return "livre";
}

function parseSeriesFromTitle(title: string): { name?: string; index?: number } {
  const match = title.match(/(?:vol(?:ume)?\.?\s*|tome\s*|t\.\s*|#\s*)(\d+)/i);
  if (!match) return {};
  return {
    index: parseInt(match[1]),
    name: title.replace(/[,\s]*(?:vol(?:ume)?\.?\s*|tome\s*|t\.\s*|#\s*)\d+.*/i, "").trim() || undefined,
  };
}

async function fromOpenLibrary(isbn: string): Promise<LookupResult | null> {
  const res  = await fetch(`https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`);
  const data = await res.json();
  const b    = data[`ISBN:${isbn}`];
  if (!b) return null;

  const subjects = (b.subjects ?? []).map((s: any) => (typeof s === "string" ? s : s.name ?? "")).join(" ").toLowerCase();
  const series   = Array.isArray(b.series) ? b.series[0] : b.series;
  const numMatch = typeof series === "string" ? series.match(/#?(\d+)/) : null;

  return {
    isbn,
    title: b.title,
    authors: (b.authors ?? []).map((a: any) => a.name),
    cover_url: b.cover?.large ?? b.cover?.medium ?? b.cover?.small,
    publisher: b.publishers?.[0]?.name,
    published_year: b.publish_date ? parseInt(b.publish_date.slice(-4)) : undefined,
    page_count: b.number_of_pages,
    description: b.excerpts?.[0]?.text,
    series_name: typeof series === "string" ? series.replace(/\s*#?\d+.*$/, "").trim() || undefined : undefined,
    series_index: numMatch ? parseInt(numMatch[1]) : undefined,
    book_type: detectType(subjects + " " + b.title),
  };
}

async function fromGoogleBooks(isbn: string): Promise<LookupResult | null> {
  const res  = await fetch(`https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}`);
  const data = await res.json();
  const vol  = data.items?.[0]?.volumeInfo;
  if (!vol) return null;

  const categories = (vol.categories ?? []).join(" ").toLowerCase();
  const parsed     = parseSeriesFromTitle(`${vol.title ?? ""} ${vol.subtitle ?? ""}`);

  return {
    isbn,
    title: vol.title,
    authors: vol.authors ?? [],
    cover_url: vol.imageLinks?.thumbnail?.replace("http:", "https:"),
    publisher: vol.publisher,
    published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : undefined,
    page_count: vol.pageCount,
    description: vol.description,
    series_name: parsed.name,
    series_index: parsed.index,
    book_type: detectType(categories + " " + vol.title),
  };
}

export async function lookupISBN(isbn: string): Promise<LookupResult | null> {
  const clean = isbn.replace(/[-\s]/g, "");
  try { const r = await fromOpenLibrary(clean); if (r) return r; } catch {}
  try { const r = await fromGoogleBooks(clean);  if (r) return r; } catch {}
  return null;
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

FILEOF
cat > "src/lib/auth.ts" << 'FILEOF'
/**
 * Server-side auth utilities.
 * Resolves NextAuth email → Supabase profile_id + library_id.
 * Auto-creates profile and library on first login.
 */
import { createServerClient } from "@/lib/supabase";

export interface UserContext {
  profile_id: string;
  library_id: string;
  email: string;
}

export async function resolveUser(email: string): Promise<UserContext | null> {
  if (!email) return null;
  const db = createServerClient();

  // 1. Find or create profile
  let { data: profile } = await db
    .from("profiles")
    .select("id")
    .eq("email", email)
    .maybeSingle();

  if (!profile) {
    const { data } = await db
      .from("profiles")
      .insert({ id: crypto.randomUUID(), email, name: email.split("@")[0] })
      .select("id")
      .single();
    profile = data;
  }

  if (!profile) return null;

  // 2. Find or create library
  let { data: library } = await db
    .from("libraries")
    .select("id")
    .eq("owner_id", profile.id)
    .maybeSingle();

  if (!library) {
    const { data } = await db
      .from("libraries")
      .insert({ owner_id: profile.id, name: "Ma Bibliothèque" })
      .select("id")
      .single();
    library = data;
  }

  if (!library) return null;

  return { profile_id: profile.id, library_id: library.id, email };
}

export async function getProfileId(email: string): Promise<string | null> {
  if (!email) return null;
  const db = createServerClient();
  const { data } = await db
    .from("profiles")
    .select("id")
    .eq("email", email)
    .maybeSingle();
  return data?.id ?? null;
}

FILEOF
cat > "src/hooks/useToast.ts" << 'FILEOF'
import { useState, useCallback, useRef } from "react";
import { ToastData } from "@/components/ui/Toast";

export function useToast() {
  const [toasts, setToasts] = useState<ToastData[]>([]);
  const counter = useRef(0);

  const push = useCallback((title: string, subtitle?: string) => {
    const id = counter.current++;
    setToasts(prev => [...prev, { id, title, subtitle }]);
  }, []);

  const dismiss = useCallback((id: number) => {
    setToasts(prev => prev.filter(t => t.id !== id));
  }, []);

  return { toasts, push, dismiss };
}

FILEOF
cat > "src/hooks/useFirstUse.ts" << 'FILEOF'
import { useState, useEffect } from "react";

export function useFirstUse(key: string): boolean | null {
  const [isFirst, setIsFirst] = useState<boolean | null>(null);

  useEffect(() => {
    const seen = localStorage.getItem(key);
    setIsFirst(!seen);
    if (!seen) localStorage.setItem(key, "1");
  }, [key]);

  return isFirst;
}

FILEOF
cat > "src/hooks/useLibrary.ts" << 'FILEOF'
/**
 * Resolves the current user's library_id and profile_id from their email.
 * Used by all pages that need to interact with the database.
 */
import { useState, useEffect } from "react";
import { useSession } from "next-auth/react";

export interface LibraryContext {
  library_id: string | null;
  profile_id: string | null;
  email: string | null;
  loading: boolean;
}

export function useLibrary(): LibraryContext {
  const { data: session }             = useSession();
  const [library_id, setLibraryId]   = useState<string | null>(null);
  const [profile_id, setProfileId]   = useState<string | null>(null);
  const [loading,    setLoading]      = useState(true);

  useEffect(() => {
    const email = session?.user?.email;
    if (!email) { setLoading(false); return; }

    fetch(`/api/library?email=${encodeURIComponent(email)}`)
      .then(r => r.json())
      .then(d => {
        if (d.id)         setLibraryId(d.id);
        if (d.profile_id) setProfileId(d.profile_id);
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [session]);

  return {
    library_id,
    profile_id,
    email: session?.user?.email ?? null,
    loading,
  };
}

FILEOF
cat > "src/middleware.ts" << 'FILEOF'
export { default } from "next-auth/middleware";

export const config = {
  matcher: ["/library/:path*", "/collections/:path*", "/scan/:path*", "/stats/:path*", "/settings/:path*"],
};

FILEOF
cat > "src/components/ui/Button.tsx" << 'FILEOF'
import { ButtonHTMLAttributes, ReactNode } from "react";

interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "ghost" | "danger";
  size?: "sm" | "md" | "lg";
  children: ReactNode;
}

const VARIANTS = {
  primary:   { background: "var(--accent)",   color: "#fff",            border: "none" },
  secondary: { background: "var(--surface2)", color: "var(--txt1)",     border: "1px solid var(--border)" },
  ghost:     { background: "transparent",     color: "var(--txt2)",     border: "1px solid var(--border)" },
  danger:    { background: "var(--miss-bg)",  color: "var(--miss-t)",   border: "1px solid var(--miss-b)" },
};

const SIZES = {
  sm: { padding: "6px 12px",  borderRadius: 10, fontSize: 12 },
  md: { padding: "10px 16px", borderRadius: 14, fontSize: 14 },
  lg: { padding: "14px 20px", borderRadius: 18, fontSize: 15 },
};

export function Button({ variant = "primary", size = "md", style, className = "", ...props }: Props) {
  return (
    <button
      className={`font-semibold flex items-center justify-center gap-2 active:scale-95 transition-transform ${className}`}
      style={{ ...VARIANTS[variant], ...SIZES[size], cursor: "pointer", ...style }}
      {...props}
    />
  );
}

FILEOF
cat > "src/components/ui/Cover.tsx" << 'FILEOF'
"use client";
import { useState } from "react";
import { BookOpen } from "lucide-react";

interface Props {
  src?: string;
  alt: string;
  width?: number;
  height?: number;
  className?: string;
}

export function Cover({ src, alt, width, height, className = "" }: Props) {
  const [error, setError] = useState(false);

  if (src && !error) {
    return (
      <img
        src={src}
        alt={alt}
        className={`object-cover ${className}`}
        style={{ width, height }}
        onError={() => setError(true)}
      />
    );
  }

  return (
    <div
      className={`flex items-center justify-center ${className}`}
      style={{ width, height, background: "var(--placeholder)" }}
    >
      <BookOpen style={{ width: "35%", height: "35%", color: "var(--txt3)" }} />
    </div>
  );
}

FILEOF
cat > "src/components/ui/Toggle.tsx" << 'FILEOF'
interface Props {
  checked: boolean;
  onChange: (v: boolean) => void;
  label?: string;
}

export function Toggle({ checked, onChange, label }: Props) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={() => onChange(!checked)}
      style={{
        width: 48, height: 28, borderRadius: 14, border: "none", cursor: "pointer",
        background: checked ? "var(--accent)" : "var(--border)",
        position: "relative", flexShrink: 0, transition: "background 0.2s",
      }}
    >
      <div style={{
        position: "absolute", top: 3, left: 3,
        width: 22, height: 22, borderRadius: 11, background: "#fff",
        transition: "transform 0.2s",
        transform: checked ? "translateX(20px)" : "translateX(0)",
      }} />
    </button>
  );
}

FILEOF
cat > "src/components/ui/Toast.tsx" << 'FILEOF'
"use client";
import { useEffect } from "react";
import { Check } from "lucide-react";

export interface ToastData {
  id: number;
  title: string;
  subtitle?: string;
}

interface Props {
  toast: ToastData;
  onDismiss: () => void;
  duration?: number;
}

export function Toast({ toast, onDismiss, duration = 3000 }: Props) {
  useEffect(() => {
    const timer = setTimeout(onDismiss, duration);
    return () => clearTimeout(timer);
  }, [onDismiss, duration]);

  return (
    <div
      className="flex items-center gap-3 px-4 py-3 rounded-2xl shadow-lg"
      style={{
        background: "var(--have-bg)",
        border: "1px solid var(--have-b)",
        minWidth: 260, maxWidth: 320,
      }}
    >
      <div
        className="w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0"
        style={{ background: "var(--have-t)" }}
      >
        <Check className="w-4 h-4 text-white" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{toast.title}</p>
        {toast.subtitle && (
          <p className="truncate" style={{ fontSize: 12, color: "var(--txt2)", marginTop: 1 }}>{toast.subtitle}</p>
        )}
      </div>
    </div>
  );
}

export function ToastStack({ toasts, onDismiss }: { toasts: ToastData[]; onDismiss: (id: number) => void }) {
  if (toasts.length === 0) return null;
  return (
    <div className="fixed bottom-24 left-0 right-0 z-50 flex flex-col items-center gap-2 px-4 pointer-events-none">
      {toasts.map(t => <Toast key={t.id} toast={t} onDismiss={() => onDismiss(t.id)} />)}
    </div>
  );
}

FILEOF
cat > "src/components/ui/StatusBadge.tsx" << 'FILEOF'
import { ReadStatus } from "@/types";
import { STATUS_CONFIG } from "@/lib/constants";

export function StatusBadge({ status }: { status: ReadStatus }) {
  const { label, bg, color } = STATUS_CONFIG[status];
  return (
    <span style={{ background: bg, color, fontSize: 10, fontWeight: 700, padding: "2px 6px", borderRadius: 6 }}>
      {label}
    </span>
  );
}

FILEOF
cat > "src/components/book/BookCard.tsx" << 'FILEOF'
"use client";
import { Book } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Star } from "lucide-react";

interface Props {
  book: Book;
  onClick?: () => void;
}

export default function BookCard({ book, onClick }: Props) {
  const { bg, color, label } = STATUS_CONFIG[book.status];
  const { emoji } = TYPE_CONFIG[book.book_type];

  return (
    <button
      onClick={onClick}
      className="flex flex-col rounded-2xl overflow-hidden text-left w-full active:scale-95 transition-transform"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}
    >
      {/* Cover */}
      <div className="relative w-full" style={{ aspectRatio: "2/3" }}>
        <Cover src={book.cover_url} alt={book.title} className="w-full h-full" />

        <span className="absolute bottom-0 left-0 right-0 text-center"
          style={{ background: bg, color, fontSize: 10, fontWeight: 700, padding: "3px 0" }}>
          {label}
        </span>

        <span className="absolute top-1.5 right-1.5" style={{ fontSize: 11 }}>
          {emoji}
        </span>
      </div>

      {/* Info */}
      <div style={{ padding: "8px 8px 10px" }}>
        <p className="font-semibold line-clamp-2" style={{ fontSize: 12, color: "var(--txt1)", lineHeight: 1.3 }}>
          {book.title}
        </p>
        <p className="truncate mt-1" style={{ fontSize: 11, color: "var(--txt2)" }}>
          {book.authors[0]}
        </p>
        {book.rating && (
          <div className="flex gap-0.5 mt-1.5">
            {Array.from({ length: 5 }).map((_, i) => (
              <Star key={i} style={{
                width: 9, height: 9,
                color: i < book.rating! ? "#FBBF24" : "var(--border)",
                fill:  i < book.rating! ? "#FBBF24" : "var(--border)",
              }} />
            ))}
          </div>
        )}
      </div>
    </button>
  );
}

FILEOF
cat > "src/components/book/BookDetail.tsx" << 'FILEOF'
"use client";
import { useState } from "react";
import { Book, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";
import { X, Star, Trash2, Save } from "lucide-react";

interface Props {
  book: Book;
  onClose: () => void;
  onUpdate: (id: string, updates: Partial<Book>) => void;
  onDelete: (id: string) => void;
}

export default function BookDetail({ book, onClose, onUpdate, onDelete }: Props) {
  const [status,       setStatus]       = useState<ReadStatus>(book.status);
  const [bookType,     setBookType]     = useState<BookType>(book.book_type);
  const [rating,       setRating]       = useState(book.rating ?? 0);
  const [note,         setNote]         = useState(book.note ?? "");
  const [confirmDel,   setConfirmDel]   = useState(false);

  const handleSave = () => {
    onUpdate(book.id, { status, book_type: bookType, rating: rating || undefined, note: note || undefined });
    onClose();
  };

  const handleDelete = () => {
    onDelete(book.id);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 backdrop-blur-sm"
        style={{ background: "rgba(10,13,31,0.6)" }}
        onClick={onClose}
      />

      {/* Sheet */}
      <div
        className="relative w-full sm:max-w-md rounded-t-3xl sm:rounded-3xl overflow-hidden"
        style={{ background: "var(--surface)", maxHeight: "92vh" }}
      >
        {/* Drag handle */}
        <div className="flex justify-center pt-3 sm:hidden">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>

        <button
          onClick={onClose}
          className="absolute top-4 right-4 w-8 h-8 rounded-full flex items-center justify-center z-10"
          style={{ background: "var(--surface2)" }}
        >
          <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
        </button>

        <div className="overflow-y-auto" style={{ maxHeight: "calc(92vh - 32px)" }}>
          {/* Header */}
          <div className="flex gap-4 p-5 pt-3">
            <Cover
              src={book.cover_url}
              alt={book.title}
              width={80}
              height={112}
              className="rounded-xl shadow-md flex-shrink-0"
            />
            <div className="flex-1 min-w-0 pt-1">
              <h2 className="font-bold text-lg leading-tight" style={{ color: "var(--txt1)" }}>
                {book.title}
              </h2>
              <p className="text-sm mt-1" style={{ color: "var(--txt2)" }}>{book.authors.join(", ")}</p>
              {book.publisher && (
                <p className="text-xs mt-0.5" style={{ color: "var(--txt3)" }}>
                  {book.publisher}{book.published_year ? ` · ${book.published_year}` : ""}
                </p>
              )}
              {book.page_count && (
                <p className="text-xs" style={{ color: "var(--txt3)" }}>{book.page_count} pages</p>
              )}
              {book.series_name && (
                <p className="text-xs mt-1 font-semibold" style={{ color: "var(--accent)" }}>
                  {book.series_name} — Tome {book.series_index}
                </p>
              )}
            </div>
          </div>

          <div className="px-5 pb-6 space-y-5">
            {/* Type */}
            <Section label="Type">
              <SegmentedControl
                options={Object.entries(TYPE_CONFIG).map(([v, { label, emoji }]) => ({ value: v, label: `${emoji} ${label}` }))}
                value={bookType}
                onChange={(v) => setBookType(v as BookType)}
              />
            </Section>

            {/* Status */}
            <Section label="Statut">
              <SegmentedControl
                options={Object.entries(STATUS_CONFIG).map(([v, { emoji, label }]) => ({ value: v, label: `${emoji} ${label}` }))}
                value={status}
                onChange={(v) => setStatus(v as ReadStatus)}
              />
            </Section>

            {/* Rating */}
            <Section label="Note">
              <div className="flex gap-2">
                {Array.from({ length: 5 }).map((_, i) => (
                  <button
                    key={i}
                    onClick={() => setRating(i + 1 === rating ? 0 : i + 1)}
                    className="flex-1 py-2 rounded-xl flex items-center justify-center"
                    style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}
                  >
                    <Star style={{ width: 18, height: 18, color: i < rating ? "#FBBF24" : "var(--border)", fill: i < rating ? "#FBBF24" : "none" }} />
                  </button>
                ))}
              </div>
            </Section>

            {/* Note */}
            <Section label="Mon avis">
              <textarea
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="Vos impressions..."
                rows={3}
                className="w-full p-3 rounded-xl text-sm resize-none outline-none"
                style={{
                  background: "var(--surface2)", color: "var(--txt1)",
                  border: "1px solid var(--border)", fontFamily: "inherit",
                }}
              />
            </Section>

            {/* Description */}
            {book.description && (
              <Section label="Résumé">
                <p className="text-sm leading-relaxed line-clamp-4" style={{ color: "var(--txt2)" }}>
                  {book.description}
                </p>
              </Section>
            )}

            {/* Actions */}
            <div className="flex gap-3 pt-1">
              <Button onClick={handleSave} className="flex-1 py-3.5 rounded-2xl">
                <Save className="w-4 h-4" /> Enregistrer
              </Button>
              {!confirmDel ? (
                <Button
                  variant="ghost"
                  onClick={() => setConfirmDel(true)}
                  className="w-12 h-12 rounded-2xl"
                >
                  <Trash2 className="w-4 h-4" style={{ color: "var(--miss-t)" }} />
                </Button>
              ) : (
                <Button variant="danger" onClick={handleDelete} className="px-4 rounded-2xl text-xs">
                  Confirmer ?
                </Button>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Internal helpers ──────────────────────────────────────────────────────────

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs font-bold uppercase tracking-wider mb-2" style={{ color: "var(--txt3)" }}>{label}</p>
      {children}
    </div>
  );
}

function SegmentedControl({ options, value, onChange }: {
  options: { value: string; label: string }[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="flex gap-2">
      {options.map((o) => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          className="flex-1 py-2.5 rounded-xl text-sm font-semibold transition-all"
          style={{
            background: value === o.value ? "var(--accent)" : "var(--surface2)",
            color:      value === o.value ? "#fff"          : "var(--txt2)",
            border:     `1px solid ${value === o.value ? "var(--accent)" : "var(--border)"}`,
          }}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

FILEOF
cat > "src/components/collection/CollectionCard.tsx" << 'FILEOF'
"use client";
import { Collection } from "@/types";
import { TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";

interface Props {
  collection: Collection;
  onClick?: () => void;
}

export default function CollectionCard({ collection, onClick }: Props) {
  const owned   = collection.owned_volumes.length;
  const total   = collection.total_volumes;
  const pct     = total ? Math.round((owned / total) * 100) : 0;
  const missing = total
    ? Array.from({ length: total }, (_, i) => i + 1).filter(n => !collection.owned_volumes.includes(n))
    : [];

  return (
    <div
      className="rounded-2xl overflow-hidden cursor-pointer active:scale-[0.98] transition-transform"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}
      onClick={onClick}
    >
      {/* Header */}
      <div className="flex gap-3 p-3">
        <Cover
          src={collection.cover_url}
          alt={collection.name}
          width={48}
          height={64}
          className="rounded-lg shadow-sm flex-shrink-0"
        />

        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <h3 className="font-bold text-sm leading-tight" style={{ color: "var(--txt1)" }}>
              {collection.name}
            </h3>
            <span style={{ fontSize: 11, flexShrink: 0, marginTop: 1 }}>
              {TYPE_CONFIG[collection.book_type].emoji}
            </span>
          </div>

          {collection.author && (
            <p className="text-xs mt-0.5 truncate" style={{ color: "var(--txt2)" }}>{collection.author}</p>
          )}

          {/* Progress */}
          <div className="flex items-center gap-2 mt-2">
            <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
              <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
            </div>
            <span className="text-xs font-bold flex-shrink-0" style={{ color: "var(--accent)" }}>
              {owned}{total ? `/${total}` : ""}
            </span>
            {missing.length > 0 && (
              <span
                className="text-xs font-bold px-2 py-0.5 rounded-full flex-shrink-0"
                style={{ background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px solid var(--miss-b)" }}
              >
                {missing.length} manquant{missing.length > 1 ? "s" : ""}
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Volume chips — only if collection has ≤ 40 volumes */}
      {total && total <= 40 && (
        <div className="flex flex-wrap gap-1.5 px-3 pb-3">
          {Array.from({ length: Math.min(total, 20) }, (_, i) => i + 1).map(n => (
            <VolumeChip key={n} n={n} owned={collection.owned_volumes.includes(n)} />
          ))}
          {total > 20 && (
            <div
              className="flex items-center justify-center font-bold"
              style={{ width: 28, height: 28, borderRadius: 7, background: "var(--accent-l)", color: "var(--accent)", fontSize: 10 }}
            >
              +{total - 20}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function VolumeChip({ n, owned }: { n: number; owned: boolean }) {
  return (
    <div
      className="flex items-center justify-center font-bold"
      style={{
        width: 28, height: 28, borderRadius: 7, fontSize: 10,
        background: owned ? "var(--have-bg)" : "var(--miss-bg)",
        color:      owned ? "var(--have-t)"  : "var(--miss-t)",
        border:     owned ? "1px solid var(--have-b)" : "1px dashed var(--miss-b)",
      }}
    >
      {n}
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

type Phase = "scanning" | "loading" | "confirm" | "not_found" | "error" | "success";

const CORNERS = [
  { top: -2,    left: -2,  borderTop: "3px solid",    borderLeft: "3px solid",    borderRadius: "6px 0 0 0" },
  { top: -2,    right: -2, borderTop: "3px solid",    borderRight: "3px solid",   borderRadius: "0 6px 0 0" },
  { bottom: -2, left: -2,  borderBottom: "3px solid", borderLeft: "3px solid",    borderRadius: "0 0 0 6px" },
  { bottom: -2, right: -2, borderBottom: "3px solid", borderRight: "3px solid",   borderRadius: "0 0 6px 0" },
];

interface Props {
  rapidMode: boolean;
  libraryId: string;
  userEmail: string;
  onSuccess: (result: ScanResult, status: ReadStatus, bookType: BookType) => void;
  onClose: () => void;
}

export default function Scanner({ rapidMode, libraryId, userEmail, onSuccess, onClose }: Props) {
  const videoRef      = useRef<HTMLVideoElement>(null);
  const processingRef = useRef(false);

  const [phase,      setPhase]      = useState<Phase>("scanning");
  const [isbn,       setIsbn]       = useState("");
  const [result,     setResult]     = useState<ScanResult | null>(null);
  const [status,     setStatus]     = useState<ReadStatus>("a_lire");
  const [bookType,   setBookType]   = useState<BookType>("livre");
  const [manual,     setManual]     = useState("");
  const [showManual, setShowManual] = useState(false);

  const frameColor = phase === "success" ? "#22C55E"
    : (phase === "not_found" || phase === "error") ? "#EF4444"
    : "#5B7AFF";

  // Camera starts once, never stops
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
        const ok = await saveBook(data, "a_lire", data.book.book_type);
        if (ok) {
          setPhase("success");
          setTimeout(() => { setPhase("scanning"); setResult(null); setIsbn(""); processingRef.current = false; }, 800);
        } else {
          setPhase("error"); processingRef.current = false;
        }
      } else {
        setPhase("confirm"); processingRef.current = false;
      }
    } catch {
      setPhase("error"); processingRef.current = false;
    }
  }, [rapidMode, libraryId]); // eslint-disable-line react-hooks/exhaustive-deps

  const saveBook = async (r: ScanResult, s: ReadStatus, bt: BookType): Promise<boolean> => {
    try {
      const res = await fetch("/api/books/add", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          isbn: r.book.isbn, title: r.book.title, authors: r.book.authors,
          cover_url: r.book.cover_url, publisher: r.book.publisher,
          published_year: r.book.published_year, page_count: r.book.page_count,
          description: r.book.description, book_type: bt, status: s,
          series_name: r.book.series_name, series_index: r.book.series_index,
          collection_id: r.collection?.id,
          library_id: libraryId,
          email: userEmail, // API resolves email → profile UUID
        }),
      });
      if (!res.ok) { const e = await res.json(); console.error("saveBook:", e); return false; }
      onSuccess(r, s, bt);
      return true;
    } catch (e) { console.error("saveBook exception:", e); return false; }
  };

  const reset = () => { setPhase("scanning"); setResult(null); setIsbn(""); processingRef.current = false; };
  const handleConfirm = async () => {
    if (!result) return;
    setPhase("loading");
    const ok = await saveBook(result, status, bookType);
    if (ok) { setPhase("success"); setTimeout(() => { reset(); onClose(); }, 600); }
    else setPhase("error");
  };

  return (
    <div className="fixed inset-0 z-50 flex flex-col overflow-hidden" style={{ background: "#060818" }}>

      {/* Top bar */}
      <div className="flex items-center justify-between px-5 pt-12 pb-2 flex-shrink-0">
        <button onClick={onClose} className="w-10 h-10 rounded-full flex items-center justify-center" style={{ background: "rgba(255,255,255,0.08)" }}>
          <X className="w-5 h-5 text-white" />
        </button>
        <span className="font-bold text-white" style={{ fontSize: 16 }}>{rapidMode ? "⚡ Mode rapide" : "Scanner"}</span>
        <button onClick={() => setShowManual(v => !v)} className="w-10 h-10 rounded-full flex items-center justify-center" style={{ background: "rgba(255,255,255,0.08)" }}>
          <Keyboard className="w-5 h-5 text-white" />
        </button>
      </div>

      {rapidMode && (
        <div className="mx-5 mb-1 px-3 py-2 rounded-xl flex-shrink-0" style={{ background: "rgba(59,91,255,0.18)", border: "1px solid rgba(91,122,255,0.3)" }}>
          <span style={{ fontSize: 12, color: "#7B80FF" }}>Scan continu — ajout instantané</span>
        </div>
      )}

      {/* Camera */}
      <div className="flex-1 flex items-center justify-center relative min-h-0">
        <div className="relative">
          <video ref={videoRef} style={{ width: 300, height: 220, objectFit: "cover", borderRadius: 12, display: "block" }} />
          <div className="absolute inset-0 pointer-events-none">
            {CORNERS.map((s, i) => (
              <div key={i} className="absolute" style={{
                width: 20, height: 20, ...s,
                borderTopColor:    s.borderTop    ? frameColor : undefined,
                borderBottomColor: s.borderBottom ? frameColor : undefined,
                borderLeftColor:   s.borderLeft   ? frameColor : undefined,
                borderRightColor:  s.borderRight  ? frameColor : undefined,
                transition: "border-color 0.3s",
              }} />
            ))}
            {(phase === "scanning" || phase === "loading") && (
              <div className="scan-line absolute left-0 right-0" style={{ height: 2, background: `linear-gradient(90deg,transparent,${frameColor},transparent)` }} />
            )}
            {phase === "success" && (
              <div className="absolute inset-0 flex items-center justify-center rounded-xl" style={{ background: "rgba(34,197,94,0.2)" }}>
                <div className="w-14 h-14 rounded-full flex items-center justify-center" style={{ background: "#22C55E" }}>
                  <Check className="w-8 h-8 text-white" />
                </div>
              </div>
            )}
          </div>
          {phase === "loading" && (
            <div className="absolute top-2 right-2">
              <div className="w-5 h-5 rounded-full border-2 animate-spin" style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
            </div>
          )}
        </div>
      </div>

      {/* Manual ISBN */}
      {showManual && (
        <div className="flex gap-2 px-5 mb-2 flex-shrink-0">
          <input type="text" value={manual} onChange={e => setManual(e.target.value)} placeholder="Saisir ISBN..."
            onKeyDown={e => { if (e.key === "Enter" && manual) { processingRef.current = true; lookup(manual); }}}
            className="flex-1 px-4 py-3 rounded-2xl outline-none"
            style={{ background: "rgba(255,255,255,0.08)", color: "white", border: "1px solid rgba(91,122,255,0.3)", fontSize: 15 }} />
          <button onClick={() => { if (manual) { processingRef.current = true; lookup(manual); }}} className="px-5 py-3 rounded-2xl font-bold" style={{ background: "var(--accent)", color: "#fff" }}>OK</button>
        </div>
      )}

      {/* Bottom panel */}
      <div className="flex-shrink-0 rounded-t-3xl p-4 flex flex-col gap-3" style={{ background: "var(--surface)", maxHeight: "45vh", overflow: "hidden" }}>

        {phase === "scanning" && <p className="text-center py-2" style={{ fontSize: 14, color: "var(--txt2)" }}>Centrez le code-barres dans le cadre</p>}

        {phase === "loading" && (
          <div className="flex items-center justify-center gap-3 py-2">
            <div className="w-5 h-5 rounded-full border-2 animate-spin flex-shrink-0" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
            <p style={{ fontSize: 14, color: "var(--txt2)" }}>Recherche {isbn}…</p>
          </div>
        )}

        {phase === "success" && <p className="text-center py-2 font-semibold" style={{ fontSize: 14, color: "#22C55E" }}>✅ Ajouté !</p>}

        {(phase === "not_found" || phase === "error") && (
          <div className="flex items-center justify-between gap-3 py-1">
            <p style={{ fontSize: 14, color: "var(--miss-t)" }}>
              {phase === "error" ? "Erreur lors de l'ajout" : `Introuvable — ${isbn}`}
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
            <div className="flex gap-3 p-3 rounded-2xl flex-shrink-0" style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
              <Cover src={result.book.cover_url} alt={result.book.title} width={44} height={62} className="rounded-lg flex-shrink-0" />
              <div className="flex-1 min-w-0">
                <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{result.book.title}</p>
                <p className="truncate" style={{ fontSize: 12, color: "var(--txt2)", marginTop: 2 }}>{result.book.authors.join(", ")}</p>
                {result.book.series_name && <p style={{ fontSize: 11, color: "var(--accent)", marginTop: 2 }}>{result.book.series_name} #{result.book.series_index}</p>}
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
cat > "src/components/layout/BottomNav.tsx" << 'FILEOF'
"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { BookOpen, Layers, ScanLine, BarChart2, User } from "lucide-react";

const NAV_ITEMS = [
  { href: "/library",     icon: BookOpen,  label: "Biblio" },
  { href: "/collections", icon: Layers,    label: "Collections" },
  { href: "/scan",        icon: ScanLine,  label: "Scanner", primary: true },
  { href: "/stats",       icon: BarChart2, label: "Stats" },
  { href: "/settings",    icon: User,      label: "Compte" },
];

export default function BottomNav() {
  const pathname = usePathname();

  return (
    <nav
      className="fixed bottom-0 left-0 right-0 z-40"
      style={{
        background: "var(--nav-bg)",
        borderTop: "1px solid var(--border)",
        paddingBottom: "env(safe-area-inset-bottom, 0px)",
      }}
    >
      <div className="flex items-center justify-around" style={{ height: 68 }}>
        {NAV_ITEMS.map(({ href, icon: Icon, label, primary }) => {
          const active = pathname === href;

          if (primary) {
            return (
              <Link key={href} href={href} className="flex flex-col items-center gap-1" style={{ marginTop: -22 }}>
                <div style={{
                  width: 54, height: 54, borderRadius: 17,
                  background: "var(--accent)",
                  display: "flex", alignItems: "center", justifyContent: "center",
                  boxShadow: "0 0 0 4px var(--bg), 0 4px 18px rgba(59,91,255,0.4)",
                }}>
                  <Icon style={{ width: 24, height: 24, color: "#fff" }} />
                </div>
                <span style={{ fontSize: 11, fontWeight: 600, color: "var(--txt2)" }}>{label}</span>
              </Link>
            );
          }

          return (
            <Link
              key={href}
              href={href}
              className="flex flex-col items-center gap-1"
              style={{ padding: "8px 12px" }}
            >
              <Icon style={{
                width: 24, height: 24,
                color: active ? "var(--accent)" : "var(--txt3)",
                strokeWidth: active ? 2.5 : 1.5,
              }} />
              <span style={{ fontSize: 11, fontWeight: 600, color: active ? "var(--accent)" : "var(--txt3)" }}>
                {label}
              </span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}

FILEOF
cat > "src/components/layout/ThemeProvider.tsx" << 'FILEOF'
"use client";
import { createContext, useContext, useEffect, useState } from "react";

type Theme = "light" | "dark";
const ThemeContext = createContext<{ theme: Theme; toggle: () => void }>({
  theme: "light",
  toggle: () => {},
});

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>("light");

  useEffect(() => {
    const saved = localStorage.getItem("etagere-theme") as Theme | null;
    const preferred = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    const initial = saved ?? preferred;
    setTheme(initial);
    document.documentElement.setAttribute("data-theme", initial);
  }, []);

  const toggle = () => {
    setTheme(prev => {
      const next = prev === "light" ? "dark" : "light";
      document.documentElement.setAttribute("data-theme", next);
      localStorage.setItem("etagere-theme", next);
      return next;
    });
  };

  return (
    <ThemeContext.Provider value={{ theme, toggle }}>
      {children}
    </ThemeContext.Provider>
  );
}

export const useTheme = () => useContext(ThemeContext);

FILEOF
cat > "src/app/layout.tsx" << 'FILEOF'
import type { Metadata, Viewport } from "next";
import "./globals.css";
import Providers from "./providers";

export const metadata: Metadata = {
  title: "Folio",
  description: "Votre bibliothèque personnelle, toujours avec vous.",
  manifest: "/manifest.json",
  appleWebApp: { capable: true, statusBarStyle: "default", title: "Folio" },
};

export const viewport: Viewport = {
  themeColor: "#3B5BFF",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet" />
      </head>
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}

FILEOF
cat > "src/app/page.tsx" << 'FILEOF'
import { redirect } from "next/navigation";
export default function Root() { redirect("/library"); }

FILEOF
cat > "src/app/providers.tsx" << 'FILEOF'
"use client";
import { SessionProvider } from "next-auth/react";
import { ThemeProvider } from "@/components/layout/ThemeProvider";

export default function Providers({ children }: { children: React.ReactNode }) {
  return (
    <SessionProvider>
      <ThemeProvider>{children}</ThemeProvider>
    </SessionProvider>
  );
}

FILEOF
cat > "src/app/globals.css" << 'FILEOF'
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600;700&display=swap');

@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  --bg: #F0F4FF;
  --surface: #FFFFFF;
  --surface2: #F5F7FF;
  --border: #E4E9FF;
  --border2: #C8D1F8;
  --txt1: #0D1240;
  --txt2: #5A6080;
  --txt3: #9BA3C8;
  --accent: #3B5BFF;
  --accent-l: #EEF1FF;
  --nav-bg: #FFFFFF;
  --card-bg: #FFFFFF;
  --placeholder: #EEF1FF;
  --miss-bg: #FFF1F1;
  --miss-b: #FECACA;
  --miss-t: #DC2626;
  --have-bg: #F0FDF4;
  --have-b: #86EFAC;
  --have-t: #16A34A;
}

[data-theme="dark"] {
  --bg: #0A0D1F;
  --surface: #131729;
  --surface2: #1A1F38;
  --border: #232848;
  --border2: #3040A0;
  --txt1: #E8ECFF;
  --txt2: #8890C0;
  --txt3: #454D80;
  --accent: #5B7AFF;
  --accent-l: #141A40;
  --nav-bg: #131729;
  --card-bg: #131729;
  --placeholder: #1A1F38;
  --miss-bg: rgba(220,38,38,0.15);
  --miss-b: rgba(252,165,165,0.3);
  --miss-t: #F87171;
  --have-bg: rgba(22,163,74,0.15);
  --have-b: rgba(134,239,172,0.3);
  --have-t: #4ADE80;
}

* { box-sizing: border-box; }

body {
  font-family: 'DM Sans', sans-serif;
  background: var(--bg);
  color: var(--txt1);
  -webkit-font-smoothing: antialiased;
}

/* Scanner animation */
.scan-line {
  animation: scanline 2s ease-in-out infinite;
}
@keyframes scanline {
  0% { top: 5%; opacity: 1; }
  50% { top: 90%; opacity: 0.7; }
  100% { top: 5%; opacity: 1; }
}

/* Vol chip */
.vol-chip {
  width: 28px; height: 28px;
  border-radius: 7px;
  display: flex; align-items: center; justify-content: center;
  font-size: 10px; font-weight: 700;
  flex-shrink: 0;
}
.vol-have { background: var(--have-bg); color: var(--have-t); border: 1px solid var(--have-b); }
.vol-miss { background: var(--miss-bg); color: var(--miss-t); border: 1px dashed var(--miss-b); }
.vol-new  { background: var(--accent); color: #fff; box-shadow: 0 0 0 2px var(--accent-l); }

/* Scrollbar */
::-webkit-scrollbar { width: 4px; height: 4px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--border2); border-radius: 2px; }

/* PWA safe area */
.pb-safe { padding-bottom: env(safe-area-inset-bottom, 16px); }

FILEOF
cat > "src/app/api/auth/[...nextauth]/route.ts" << 'FILEOF'
import NextAuth from "next-auth";
import GoogleProvider from "next-auth/providers/google";
import { supabase } from "@/lib/supabase";

const handler = NextAuth({
  providers: [
    GoogleProvider({
      clientId: process.env.GOOGLE_CLIENT_ID!,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
    }),
  ],
  pages: {
    signIn: "/login",
    error: "/login",
  },
  callbacks: {
    async signIn({ account }) {
      if (account?.provider !== "google") return false;
      if (account.id_token) {
        await supabase.auth.signInWithIdToken({
          provider: "google",
          token: account.id_token,
        });
      }
      return true;
    },
    async session({ session, token }) {
      if (session.user && token.sub) session.user.id = token.sub;
      return session;
    },
    async jwt({ token, account }) {
      if (account) token.idToken = account.id_token;
      return token;
    },
  },
  session: { strategy: "jwt" },
  secret: process.env.NEXTAUTH_SECRET,
});

export { handler as GET, handler as POST };

FILEOF
cat > "src/app/api/library/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { resolveUser } from "@/lib/auth";

export async function GET(req: NextRequest) {
  const email = req.nextUrl.searchParams.get("email");
  if (!email) return NextResponse.json({ error: "email manquant" }, { status: 400 });
  const ctx = await resolveUser(email);
  if (!ctx) return NextResponse.json({ error: "Impossible de créer le profil" }, { status: 500 });
  return NextResponse.json({ id: ctx.library_id, profile_id: ctx.profile_id });
}

FILEOF
cat > "src/app/api/books/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getBooks, patchBook, removeBook } from "@/lib/db";

export async function GET(req: NextRequest) {
  const library_id = req.nextUrl.searchParams.get("library_id");
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
  try {
    return NextResponse.json(await getBooks(library_id));
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
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
import { getProfileId } from "@/lib/auth";
import { insertBook } from "@/lib/db";
import { Book } from "@/types";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as Omit<Book, "id" | "added_at" | "updated_at"> & { email?: string };
    const { email, ...bookData } = body;

    // Resolve added_by: email → profile UUID
    if (email) {
      const profileId = await getProfileId(email);
      if (profileId) bookData.added_by = profileId;
    }

    const book = await insertBook(bookData);
    return NextResponse.json(book);
  } catch (e: any) {
    console.error("POST /api/books/add:", e);
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

FILEOF
cat > "src/app/api/books/lookup/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { lookupISBN } from "@/lib/isbn-lookup";
import { resolveCollection } from "@/lib/db";
import { ScanResult } from "@/types";

export async function GET(req: NextRequest) {
  const isbn       = req.nextUrl.searchParams.get("isbn");
  const library_id = req.nextUrl.searchParams.get("library_id");
  if (!isbn)       return NextResponse.json({ error: "isbn manquant" },       { status: 400 });
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });

  const book = await lookupISBN(isbn);
  if (!book) return NextResponse.json({ error: "Livre introuvable" }, { status: 404 });

  // Auto-resolve collection for BD/manga series
  const isSeries = (book.book_type === "bd" || book.book_type === "manga")
    && book.series_name && book.series_index !== undefined;

  if (isSeries) {
    try {
      const { collection, isNew, isNewVolume } = await resolveCollection(
        library_id, book.series_name!, book.series_index!,
        { cover_url: book.cover_url, author: book.authors[0], book_type: book.book_type }
      );
      return NextResponse.json({ book, collection, isNewCollection: isNew, isNewVolume } satisfies ScanResult);
    } catch (e: any) {
      console.error("resolveCollection:", e);
    }
  }

  return NextResponse.json({ book, isNewCollection: false, isNewVolume: false } satisfies ScanResult);
}

FILEOF
cat > "src/app/api/collections/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getCollections, insertCollection } from "@/lib/db";
import { Collection } from "@/types";

export async function GET(req: NextRequest) {
  const library_id = req.nextUrl.searchParams.get("library_id");
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
  try {
    return NextResponse.json(await getCollections(library_id));
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as Omit<Collection, "id" | "created_at" | "updated_at">;
    if (!body.library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
    return NextResponse.json(await insertCollection(body));
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

FILEOF
cat > "src/app/api/share/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { createShare, getShareByToken, registerViewer } from "@/lib/db";

export async function POST(req: NextRequest) {
  const { collection_id, profile_id } = await req.json();
  if (!collection_id || !profile_id)
    return NextResponse.json({ error: "Paramètres manquants" }, { status: 400 });
  try {
    const token = await createShare(collection_id, profile_id);
    return NextResponse.json({ token });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function GET(req: NextRequest) {
  const token        = req.nextUrl.searchParams.get("token");
  const viewer_email = req.nextUrl.searchParams.get("viewer_email");
  if (!token) return NextResponse.json({ error: "Token manquant" }, { status: 400 });
  try {
    const share = await getShareByToken(token);
    if (!share) return NextResponse.json({ error: "Lien invalide ou expiré" }, { status: 404 });
    if (viewer_email) {
      const viewer_id = await getProfileId(viewer_email);
      if (viewer_id) await registerViewer(share.id, viewer_id);
    }
    return NextResponse.json(share);
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

FILEOF
cat > "src/app/api/shared-with-me/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { getSharedWithMe } from "@/lib/db";

export async function GET(req: NextRequest) {
  const email = req.nextUrl.searchParams.get("email");
  if (!email) return NextResponse.json([]);
  const profile_id = await getProfileId(email);
  if (!profile_id) return NextResponse.json([]);
  return NextResponse.json(await getSharedWithMe(profile_id));
}

FILEOF
cat > "src/app/library/page.tsx" << 'FILEOF'
"use client";
import { useState, useMemo, useEffect, useCallback } from "react";
import { useSession } from "next-auth/react";
import { Book, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { useLibrary } from "@/hooks/useLibrary";
import BookCard from "@/components/book/BookCard";
import BookDetail from "@/components/book/BookDetail";
import BottomNav from "@/components/layout/BottomNav";
import { Search, SlidersHorizontal, LayoutGrid, List } from "lucide-react";

type Layout       = "grid" | "list";
type FilterType   = BookType | "all";
type FilterStatus = ReadStatus | "all";

export default function LibraryPage() {
  const { data: session }                       = useSession();
  const { library_id, loading: libLoading }     = useLibrary();
  const [books,        setBooks]                = useState<Book[]>([]);
  const [booksLoading, setBooksLoading]         = useState(false);
  const [search,       setSearch]               = useState("");
  const [filterStatus, setFilterStatus]         = useState<FilterStatus>("all");
  const [filterType,   setFilterType]           = useState<FilterType>("all");
  const [layout,       setLayout]               = useState<Layout>("grid");
  const [selected,     setSelected]             = useState<Book | null>(null);
  const [showFilters,  setShowFilters]          = useState(false);

  const fetchBooks = useCallback(async (lid: string) => {
    setBooksLoading(true);
    const res = await fetch(`/api/books?library_id=${lid}`);
    if (res.ok) setBooks(await res.json());
    setBooksLoading(false);
  }, []);

  useEffect(() => {
    if (library_id) fetchBooks(library_id);
  }, [library_id, fetchBooks]);

  const stats = useMemo(() => ({
    lu:       books.filter(b => b.status === "lu").length,
    en_cours: books.filter(b => b.status === "en_cours").length,
    a_lire:   books.filter(b => b.status === "a_lire").length,
  }), [books]);

  const filtered = useMemo(() => books.filter(b => {
    const q = search.toLowerCase();
    return (!q || b.title.toLowerCase().includes(q) || b.authors.some(a => a.toLowerCase().includes(q)))
      && (filterStatus === "all" || b.status === filterStatus)
      && (filterType   === "all" || b.book_type === filterType);
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

  const userName = session?.user?.name?.split(" ")[0] ?? "toi";
  const loading  = libLoading || booksLoading;

  return (
    <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="sticky top-0 z-30 px-4 pt-12 pb-3" style={{ background: "var(--bg)" }}>
        {/* Hero */}
        <div className="rounded-2xl p-4 mb-4 flex items-center justify-between relative overflow-hidden" style={{ background: "var(--accent)" }}>
          <div className="absolute right-[-20px] top-[-20px] w-28 h-28 rounded-full" style={{ background: "rgba(255,255,255,0.07)" }} />
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
            ? <img src={session.user.image} alt="" className="w-12 h-12 rounded-xl flex-shrink-0 object-cover" />
            : <div className="w-12 h-12 rounded-xl flex items-center justify-center font-bold flex-shrink-0"
                style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>{userName[0]}</div>}
        </div>

        {/* Search */}
        <div className="flex gap-2 mb-3">
          <div className="flex-1 flex items-center gap-2 px-4 py-3 rounded-2xl" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <Search className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
            <input type="text" value={search} onChange={e => setSearch(e.target.value)} placeholder="Titre, auteur..."
              className="flex-1 outline-none bg-transparent" style={{ color: "var(--txt1)", fontSize: 15 }} />
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
            <FilterRow options={[{ v:"all", l:"Tous" }, ...Object.entries(STATUS_CONFIG).map(([v,c]) => ({ v, l:`${c.emoji} ${c.label}` }))]} value={filterStatus} onChange={v => setFilterStatus(v as FilterStatus)} />
            <FilterRow options={[{ v:"all", l:"Tous types" }, ...Object.entries(TYPE_CONFIG).map(([v,c]) => ({ v, l:`${c.emoji} ${c.label}` }))]} value={filterType} onChange={v => setFilterType(v as FilterType)} />
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
          <div className="flex flex-col items-center py-20 gap-3">
            <p className="font-semibold" style={{ fontSize: 17, color: "var(--txt1)" }}>{books.length > 0 ? "Aucun résultat" : "Bibliothèque vide"}</p>
            <p style={{ fontSize: 14, color: "var(--txt3)" }}>{books.length > 0 ? "Essayez un autre filtre" : "Scannez votre premier livre !"}</p>
          </div>
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

      {selected && <BookDetail book={selected} onClose={() => setSelected(null)} onUpdate={handleUpdate} onDelete={handleDelete} />}
      <BottomNav />
    </div>
  );
}

function FilterRow({ options, value, onChange }: { options: { v: string; l: string }[]; value: string; onChange: (v: string) => void }) {
  return (
    <div className="flex gap-2 overflow-x-auto pb-1" style={{ scrollbarWidth: "none" }}>
      {options.map(({ v, l }) => (
        <button key={v} onClick={() => onChange(v)} className="flex-shrink-0 px-4 py-2 rounded-full font-semibold"
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

FILEOF
cat > "src/app/collections/page.tsx" << 'FILEOF'
"use client";
import { useState, useEffect } from "react";
import { Collection, BookType } from "@/types";
import { useLibrary } from "@/hooks/useLibrary";
import CollectionCard from "@/components/collection/CollectionCard";
import BottomNav from "@/components/layout/BottomNav";
import { Button } from "@/components/ui/Button";
import { Search, Plus, X, Share2, Check, MessageCircle } from "lucide-react";

function CreateModal({ onClose, onCreate }: { onClose: () => void; onCreate: (c: Partial<Collection>) => void }) {
  const [name, setName]     = useState("");
  const [type, setType]     = useState<BookType>("livre");
  const [author, setAuthor] = useState("");
  const [total, setTotal]   = useState("");
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-5">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Nouvelle collection</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}><X className="w-4 h-4" style={{ color: "var(--txt2)" }} /></button>
        </div>
        <div className="space-y-4">
          {[
            { label: "Nom", el: <input type="text" value={name} onChange={e => setName(e.target.value)} placeholder="Ex: Astérix, Saga Dune..." className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} /> },
            { label: "Auteur (optionnel)", el: <input type="text" value={author} onChange={e => setAuthor(e.target.value)} placeholder="Ex: Goscinny..." className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} /> },
            { label: "Nombre de tomes (optionnel)", el: <input type="number" value={total} onChange={e => setTotal(e.target.value)} placeholder="Ex: 40" className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} /> },
          ].map(({ label, el }) => (
            <div key={label}>
              <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>{label}</label>
              {el}
            </div>
          ))}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Type</label>
            <div className="flex gap-2">
              {(["livre","bd","manga"] as BookType[]).map(t => (
                <button key={t} onClick={() => setType(t)} className="flex-1 py-2.5 rounded-xl font-semibold"
                  style={{ fontSize: 13, background: type === t ? "var(--accent)" : "var(--surface2)", color: type === t ? "#fff" : "var(--txt2)", border: `1px solid ${type === t ? "var(--accent)" : "var(--border)"}` }}>
                  {t === "livre" ? "📖 Livre" : t === "bd" ? "🎨 BD" : "⛩️ Manga"}
                </button>
              ))}
            </div>
          </div>
          <Button onClick={() => { if (name.trim()) { onCreate({ name: name.trim(), book_type: type, author: author.trim() || undefined, total_volumes: total ? parseInt(total) : undefined, owned_volumes: [] }); onClose(); }}} className="w-full py-4 rounded-2xl" style={{ fontSize: 15 }}>
            Créer
          </Button>
        </div>
      </div>
    </div>
  );
}

function ShareModal({ collection, profileId, onClose }: { collection: Collection; profileId: string; onClose: () => void }) {
  const [link, setLink]     = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    fetch("/api/share", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ collection_id: collection.id, profile_id: profileId }) })
      .then(r => r.json()).then(d => setLink(`${window.location.origin}/share/${d.token}`));
  }, [collection.id, profileId]);
  const copy = () => { if (!link) return; navigator.clipboard.writeText(link); setCopied(true); setTimeout(() => setCopied(false), 2000); };
  const shareVia = (m: "whatsapp"|"sms") => { if (!link) return; const t = `👀 Regarde ma collection "${collection.name}" sur Folio : ${link}`; window.open(m === "whatsapp" ? `https://wa.me/?text=${encodeURIComponent(t)}` : `sms:?body=${encodeURIComponent(t)}`); };
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Partager</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}><X className="w-4 h-4" style={{ color: "var(--txt2)" }} /></button>
        </div>
        {!link ? <div className="flex justify-center py-6"><div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} /></div> : (
          <div className="flex flex-col gap-3">
            <div className="px-3 py-2 rounded-xl truncate" style={{ background: "var(--surface2)", border: "1px solid var(--border)", fontSize: 12, color: "var(--txt3)" }}>{link}</div>
            <button onClick={() => shareVia("whatsapp")} className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3" style={{ background: "#25D366", color: "#fff", fontSize: 15 }}><MessageCircle className="w-5 h-5" /> WhatsApp</button>
            <button onClick={() => shareVia("sms")} className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3" style={{ background: "var(--surface2)", color: "var(--txt1)", fontSize: 15, border: "1px solid var(--border)" }}><MessageCircle className="w-5 h-5" /> SMS / iMessage</button>
            <button onClick={copy} className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3" style={{ background: copied ? "var(--have-bg)" : "var(--accent-l)", color: copied ? "var(--have-t)" : "var(--accent)", fontSize: 15 }}>
              {copied ? <Check className="w-5 h-5" /> : <Share2 className="w-5 h-5" />}{copied ? "Copié !" : "Copier le lien"}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

type Filter = "all" | "bd" | "manga" | "livre";

export default function CollectionsPage() {
  const { library_id, profile_id, loading: libLoading } = useLibrary();
  const [collections,     setCollections]    = useState<Collection[]>([]);
  const [colLoading,      setColLoading]     = useState(false);
  const [search,          setSearch]         = useState("");
  const [filter,          setFilter]         = useState<Filter>("all");
  const [showCreate,      setShowCreate]     = useState(false);
  const [shareCol,        setShareCol]       = useState<Collection | null>(null);

  useEffect(() => {
    if (!library_id) return;
    setColLoading(true);
    fetch(`/api/collections?library_id=${library_id}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setCollections(d) : [])
      .catch(console.error)
      .finally(() => setColLoading(false));
  }, [library_id]);

  const handleCreate = async (data: Partial<Collection>) => {
    if (!library_id) return;
    const res = await fetch("/api/collections", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...data, library_id, owned_volumes: data.owned_volumes ?? [] }) });
    if (res.ok) { const col = await res.json(); setCollections(prev => [col, ...prev]); }
  };

  const filtered = collections.filter(c =>
    (filter === "all" || c.book_type === filter) &&
    (!search || c.name.toLowerCase().includes(search.toLowerCase()) || c.author?.toLowerCase().includes(search.toLowerCase()))
  );

  const loading = libLoading || colLoading;

  return (
    <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="sticky top-0 z-30 px-4 pt-12 pb-3" style={{ background: "var(--bg)" }}>
        <div className="flex items-center justify-between mb-4">
          <div>
            <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Collections</p>
            <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>{collections.length} <span style={{ fontSize: 16, fontWeight: 400, opacity: 0.35 }}>séries</span></h1>
          </div>
          <button onClick={() => setShowCreate(true)} className="w-11 h-11 rounded-2xl flex items-center justify-center active:scale-95" style={{ background: "var(--accent)" }}><Plus className="w-5 h-5 text-white" /></button>
        </div>
        <div className="flex items-center gap-2 px-4 py-3 rounded-2xl mb-3" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          <Search className="w-5 h-5" style={{ color: "var(--txt3)" }} />
          <input type="text" value={search} onChange={e => setSearch(e.target.value)} placeholder="Rechercher..." className="flex-1 outline-none bg-transparent" style={{ color: "var(--txt1)", fontSize: 15 }} />
        </div>
        <div className="flex gap-2 overflow-x-auto pb-1" style={{ scrollbarWidth: "none" }}>
          {(["all","livre","bd","manga"] as Filter[]).map(f => (
            <button key={f} onClick={() => setFilter(f)} className="flex-shrink-0 px-4 py-2 rounded-full font-semibold"
              style={{ fontSize: 13, background: filter === f ? "var(--accent)" : "var(--surface)", color: filter === f ? "#fff" : "var(--txt2)", border: `1px solid ${filter === f ? "var(--accent)" : "var(--border)"}` }}>
              {f === "all" ? "Toutes" : f === "livre" ? "📖 Livres" : f === "bd" ? "🎨 BD" : "⛩️ Manga"}
            </button>
          ))}
        </div>
      </div>

      <div className="px-4 flex flex-col gap-4">
        {loading ? (
          <div className="flex justify-center py-20"><div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} /></div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center py-20 gap-4">
            <p className="font-semibold" style={{ fontSize: 17, color: "var(--txt1)" }}>Aucune collection</p>
            <Button onClick={() => setShowCreate(true)}>+ Créer une collection</Button>
          </div>
        ) : filtered.map(c => (
          <div key={c.id}>
            <CollectionCard collection={c} />
            <button onClick={() => setShareCol(c)} className="w-full mt-2 py-3 rounded-2xl font-semibold flex items-center justify-center gap-2 active:scale-95"
              style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt2)", fontSize: 13 }}>
              <Share2 className="w-4 h-4" style={{ color: "var(--accent)" }} /> Partager cette collection
            </button>
          </div>
        ))}
      </div>

      {showCreate && <CreateModal onClose={() => setShowCreate(false)} onCreate={handleCreate} />}
      {shareCol && profile_id && <ShareModal collection={shareCol} profileId={profile_id} onClose={() => setShareCol(null)} />}
      <BottomNav />
    </div>
  );
}

FILEOF
cat > "src/app/login/page.tsx" << 'FILEOF'
"use client";
import { signIn } from "next-auth/react";
import { BookOpen } from "lucide-react";
import { Button } from "@/components/ui/Button";

const FEATURES = [
  { icon: "📷", text: "Scannez les codes-barres de vos livres" },
  { icon: "📚", text: "Collections BD et manga automatiques" },
  { icon: "✨", text: "Partagez avec famille et amis" },
];

export default function LoginPage() {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center px-6" style={{ background: "var(--bg)" }}>
      <div className="flex flex-col items-center gap-8 max-w-sm w-full">

        {/* Logo */}
        <div className="flex flex-col items-center gap-3">
          <div className="w-16 h-16 rounded-2xl flex items-center justify-center"
            style={{ background: "var(--accent)", boxShadow: "0 4px 20px rgba(59,91,255,0.35)" }}>
            <BookOpen className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-4xl font-bold" style={{ color: "var(--txt1)" }}>Folio</h1>
          <p className="text-sm text-center" style={{ color: "var(--txt2)" }}>
            Votre bibliothèque partagée, toujours avec vous.
          </p>
        </div>

        {/* Divider */}
        <div className="flex items-center gap-3 w-full">
          <div className="flex-1 h-px" style={{ background: "var(--border)" }} />
          <span className="text-xs font-semibold uppercase tracking-widest" style={{ color: "var(--txt3)" }}>
            Collection
          </span>
          <div className="flex-1 h-px" style={{ background: "var(--border)" }} />
        </div>

        {/* Features */}
        <div className="w-full space-y-2">
          {FEATURES.map(({ icon, text }) => (
            <div key={text} className="flex items-center gap-3 px-4 py-3 rounded-xl"
              style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
              <span className="text-lg">{icon}</span>
              <span style={{ fontSize: 14, fontWeight: 500, color: "var(--txt2)" }}>{text}</span>
            </div>
          ))}
        </div>

        {/* Google sign-in */}
        <Button
          onClick={() => signIn("google", { callbackUrl: "/library" })}
          className="w-full py-4 rounded-2xl gap-3"
          style={{ fontSize: 15, boxShadow: "0 4px 16px rgba(59,91,255,0.3)" }}
        >
          <GoogleIcon />
          Continuer avec Google
        </Button>

        <p style={{ fontSize: 12, color: "var(--txt3)", textAlign: "center" }}>
          Accès sécurisé · Données privées · Gratuit
        </p>
      </div>
    </div>
  );
}

function GoogleIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#fff" fillOpacity="0.9" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
      <path fill="#fff" fillOpacity="0.75" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
      <path fill="#fff" fillOpacity="0.6" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
      <path fill="#fff" fillOpacity="0.5" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
    </svg>
  );
}

FILEOF
cat > "src/app/scan/page.tsx" << 'FILEOF'
"use client";
import { useState, useCallback } from "react";
import { useSession } from "next-auth/react";
import { ScanResult, ReadStatus, BookType } from "@/types";
import { useLibrary } from "@/hooks/useLibrary";
import { useToast } from "@/hooks/useToast";
import { useFirstUse } from "@/hooks/useFirstUse";
import BottomNav from "@/components/layout/BottomNav";
import Scanner from "@/components/scanner/Scanner";
import { ToastStack } from "@/components/ui/Toast";
import { ScanLine, Zap, Settings2 } from "lucide-react";

const MODES = [
  { key: false, icon: Settings2, label: "Mode classique", sub: "Confirmation avant ajout" },
  { key: true,  icon: Zap,       label: "Mode rapide",    sub: "Ajout instantané en série" },
] as const;

export default function ScanPage() {
  const { data: session }                   = useSession();
  const { library_id, email, loading }      = useLibrary();
  const [scanning,  setScanning]            = useState(false);
  const [rapidMode, setRapidMode]           = useState(false);
  const isFirstUse                          = useFirstUse("folio_scan_seen");
  const { toasts, push, dismiss }           = useToast();

  const handleSuccess = useCallback((result: ScanResult) => {
    if (rapidMode) {
      push(result.book.title, result.isNewCollection
        ? `Collection « ${result.collection?.name} » créée`
        : result.isNewVolume ? `Ajouté à ${result.collection?.name}` : undefined);
    } else {
      setScanning(false);
      push("Ajouté !", result.book.title);
    }
  }, [rapidMode, push]);

  if (isFirstUse === null) return null;
  const ready = !!library_id && !loading;

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
              className="flex-1 flex items-center gap-3 px-3 py-3 rounded-xl"
              style={{ background: rapidMode === key ? "var(--accent)" : "transparent" }}>
              <Icon className="w-5 h-5 flex-shrink-0" style={{ color: rapidMode === key ? "#fff" : "var(--txt3)" }} />
              <div className="text-left">
                <p className="font-bold" style={{ fontSize: 13, color: rapidMode === key ? "#fff" : "var(--txt1)" }}>{label}</p>
                <p style={{ fontSize: 11, color: rapidMode === key ? "rgba(255,255,255,0.7)" : "var(--txt3)" }}>{sub}</p>
              </div>
            </button>
          ))}
        </div>

        {isFirstUse
          ? <FirstUseView onStart={() => ready && setScanning(true)} ready={ready} />
          : <ScanButton rapidMode={rapidMode} onStart={() => ready && setScanning(true)} ready={ready} />}
      </div>

      {scanning && library_id && email && (
        <Scanner
          rapidMode={rapidMode}
          libraryId={library_id}
          userEmail={email}
          onSuccess={handleSuccess}
          onClose={() => setScanning(false)}
        />
      )}

      <ToastStack toasts={toasts} onDismiss={dismiss} />
      <BottomNav />
    </>
  );
}

function ScanButton({ rapidMode, onStart, ready }: { rapidMode: boolean; onStart: () => void; ready: boolean }) {
  return (
    <div className="flex flex-col items-center gap-4 px-5">
      <button onClick={onStart} disabled={!ready}
        className="w-full py-5 rounded-3xl flex items-center justify-center gap-3 active:scale-95"
        style={{ background: ready ? "var(--accent)" : "var(--surface)", boxShadow: ready ? "0 8px 32px rgba(59,91,255,0.35)" : "none", opacity: ready ? 1 : 0.6 }}>
        {!ready
          ? <div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
          : <ScanLine className="w-7 h-7 text-white" />}
        <span className="font-bold text-white" style={{ fontSize: 17 }}>
          {!ready ? "Chargement…" : rapidMode ? "Lancer le mode rapide" : "Ouvrir le scanner"}
        </span>
      </button>
      {ready && <p className="text-center" style={{ fontSize: 13, color: "var(--txt3)" }}>
        {rapidMode ? "Chaque scan est ajouté immédiatement" : "ISBN détecté automatiquement"}
      </p>}
    </div>
  );
}

function FirstUseView({ onStart, ready }: { onStart: () => void; ready: boolean }) {
  return (
    <div className="flex flex-col items-center gap-6 px-5">
      <button onClick={onStart} disabled={!ready}
        className="w-32 h-32 rounded-3xl flex flex-col items-center justify-center gap-2 active:scale-95"
        style={{ background: ready ? "var(--accent)" : "var(--surface)", boxShadow: ready ? "0 8px 32px rgba(59,91,255,0.35)" : "none", opacity: ready ? 1 : 0.6 }}>
        {!ready
          ? <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
          : <ScanLine className="w-12 h-12 text-white" />}
        <span className="font-bold text-white text-sm">{ready ? "Scanner" : "..."}</span>
      </button>
      <div className="text-center">
        <p className="font-bold" style={{ fontSize: 17, color: "var(--txt1)" }}>Scannez le code-barres</p>
        <p style={{ fontSize: 14, color: "var(--txt3)", marginTop: 4 }}>ISBN au dos du livre ou de la BD</p>
      </div>
      <div className="w-full space-y-2">
        {["Pointez la caméra vers le code-barres", "La détection est automatique", "Les BD créent leur collection automatiquement"].map((text, i) => (
          <div key={i} className="flex items-center gap-3 p-4 rounded-2xl" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
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
cat > "src/app/stats/page.tsx" << 'FILEOF'
"use client";
import BottomNav from "@/components/layout/BottomNav";
import { BookOpen, TrendingUp, FileText, Star } from "lucide-react";

// ─── Static demo data (replace with Supabase aggregation) ────────────────────
const STATS = { total: 38, lu: 24, en_cours: 3, a_lire: 11, pages: 8429, this_year: 12, avg_rating: 4.3 };

const KPI_ITEMS = [
  { icon: BookOpen,   label: "Lus au total",  value: STATS.lu,                          sub: `sur ${STATS.total} ouvrages`, color: "var(--accent)" },
  { icon: TrendingUp, label: "Cette année",   value: STATS.this_year,                   sub: "livres terminés",             color: "#22C55E"       },
  { icon: FileText,   label: "Pages lues",    value: STATS.pages.toLocaleString("fr"),  sub: "toutes éditions",             color: "#FB923C"       },
  { icon: Star,       label: "Note moyenne",  value: STATS.avg_rating,                  sub: "sur 5 étoiles",               color: "#FBBF24"       },
];

const TYPE_BARS = [
  { label: "📖 Livres", value: 22, color: "var(--accent)" },
  { label: "🎨 BD",     value: 11, color: "#FB923C"       },
  { label: "⛩️ Manga",  value: 5,  color: "#22C55E"       },
];

const TOP_AUTHORS = [
  { name: "J.R.R. Tolkien", count: 4 },
  { name: "Albert Camus",   count: 3 },
  { name: "René Goscinny",  count: 2 },
];

export default function StatsPage() {
  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-12 pb-4">
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>
          Vos stats
        </p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Tableau de bord</h1>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-3 px-4 mb-4">
        {KPI_ITEMS.map(({ icon: Icon, label, value, sub, color }) => (
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

      {/* Avancement */}
      <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Avancement</h3>
        <div className="flex gap-3">
          {[
            { label: "Lus",      n: STATS.lu,        emoji: "✅", bg: "var(--have-bg)", color: "var(--have-t)" },
            { label: "En cours", n: STATS.en_cours,  emoji: "📖", bg: "#FEF9C3",        color: "#A16207"       },
            { label: "À lire",   n: STATS.a_lire,    emoji: "📌", bg: "var(--accent-l)", color: "var(--accent)" },
          ].map(({ label, n, emoji, bg, color }) => (
            <div key={label} className="flex-1 flex flex-col items-center p-3 rounded-xl" style={{ background: bg }}>
              <span className="text-xl">{emoji}</span>
              <span className="text-xl font-bold mt-1" style={{ color }}>{n}</span>
              <span className="text-xs mt-0.5" style={{ color, opacity: 0.8 }}>{label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Répartition */}
      <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Répartition par type</h3>
        <div className="flex flex-col gap-3">
          {TYPE_BARS.map(({ label, value, color }) => (
            <div key={label}>
              <div className="flex justify-between mb-1.5">
                <span style={{ fontSize: 13, color: "var(--txt2)" }}>{label}</span>
                <span className="font-bold" style={{ fontSize: 13, color }}>{value}</span>
              </div>
              <div className="h-2 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
                <div className="h-full rounded-full" style={{ width: `${(value / STATS.total) * 100}%`, background: color }} />
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Top auteurs */}
      <div className="mx-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Auteurs favoris</h3>
        {TOP_AUTHORS.map(({ name, count }, i) => (
          <div key={name} className="flex items-center gap-3 py-2">
            <span className="font-bold text-sm w-4 text-center"
              style={{ color: i === 0 ? "var(--accent)" : "var(--txt3)" }}>
              {i + 1}
            </span>
            <span className="flex-1 text-sm" style={{ color: "var(--txt2)" }}>{name}</span>
            <span className="text-xs font-semibold px-2 py-0.5 rounded-full"
              style={{ background: "var(--accent-l)", color: "var(--accent)" }}>
              {count} livre{count > 1 ? "s" : ""}
            </span>
          </div>
        ))}
      </div>

      <BottomNav />
    </div>
  );
}

FILEOF
cat > "src/app/settings/page.tsx" << 'FILEOF'
"use client";
import { useState, useEffect } from "react";
import { useSession, signOut } from "next-auth/react";
import { useLibrary } from "@/hooks/useLibrary";
import BottomNav from "@/components/layout/BottomNav";
import { useTheme } from "@/components/layout/ThemeProvider";
import { Toggle } from "@/components/ui/Toggle";
import { Cover } from "@/components/ui/Cover";
import { SharedWithMe } from "@/lib/db";
import { Moon, LogOut, ChevronRight, Gift, BookOpen } from "lucide-react";

export default function SettingsPage() {
  const { data: session }         = useSession();
  const { email }                 = useLibrary();
  const { theme, toggle }         = useTheme();
  const [shared, setShared]       = useState<SharedWithMe[]>([]);

  useEffect(() => {
    if (!email) return;
    fetch(`/api/shared-with-me?email=${encodeURIComponent(email)}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setShared(d) : [])
      .catch(console.error);
  }, [email]);

  const userName = session?.user?.name ?? "Utilisateur";

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-12 pb-4">
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Compte</p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Réglages</h1>
      </div>

      <div className="mx-4 mb-4 p-4 rounded-2xl flex items-center gap-3" style={{ background: "var(--accent)" }}>
        {session?.user?.image
          ? <img src={session.user.image} alt="" className="w-14 h-14 rounded-2xl flex-shrink-0 object-cover" />
          : <div className="w-14 h-14 rounded-2xl flex items-center justify-center font-bold flex-shrink-0" style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>{userName[0]}</div>}
        <div className="min-w-0">
          <p className="font-bold text-white truncate" style={{ fontSize: 17 }}>{userName}</p>
          <p className="truncate" style={{ color: "rgba(255,255,255,0.65)", fontSize: 13 }}>{session?.user?.email}</p>
        </div>
      </div>

      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5 flex items-center gap-2" style={{ borderBottom: "1px solid var(--border)" }}>
          <Gift className="w-4 h-4" style={{ color: "var(--accent)" }} />
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Bibliothèques partagées</span>
        </div>
        {shared.length === 0 ? (
          <div className="px-4 py-6 flex flex-col items-center gap-2">
            <BookOpen className="w-8 h-8" style={{ color: "var(--txt3)", opacity: 0.3 }} />
            <p className="text-center" style={{ fontSize: 14, color: "var(--txt3)" }}>Personne n&apos;a encore partagé de collection avec toi</p>
          </div>
        ) : shared.map(lib => (
          <a key={lib.token} href={`/share/${lib.token}`} className="flex items-center gap-3 px-4 py-3.5 active:opacity-70"
            style={{ borderTop: "1px solid var(--border)", textDecoration: "none" }}>
            <Cover src={lib.cover_url} alt={lib.collection_name} width={44} height={60} className="rounded-xl flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="font-semibold truncate" style={{ fontSize: 15, color: "var(--txt1)" }}>{lib.collection_name} <span style={{ fontWeight: 400, opacity: 0.5 }}>de {lib.owner_name}</span></p>
              <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{lib.owned_volumes.length}{lib.total_volumes ? `/${lib.total_volumes}` : ""} tomes</p>
            </div>
            <ChevronRight className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          </a>
        ))}
      </div>

      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5" style={{ borderBottom: "1px solid var(--border)" }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Préférences</span>
        </div>
        <div className="flex items-center gap-3 px-4 py-4">
          <Moon className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          <div className="flex-1">
            <p style={{ fontSize: 15, fontWeight: 500, color: "var(--txt1)" }}>Mode sombre</p>
            <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{"Thème de l'interface"}</p>
          </div>
          <Toggle checked={theme === "dark"} onChange={() => toggle()} label="Basculer mode sombre" />
        </div>
      </div>

      <button onClick={() => signOut({ callbackUrl: "/login" })}
        className="mx-4 py-4 rounded-2xl flex items-center justify-center gap-2 active:scale-95"
        style={{ width: "calc(100% - 2rem)", background: "var(--miss-bg)", border: "1px solid var(--miss-b)" }}>
        <LogOut className="w-5 h-5" style={{ color: "var(--miss-t)" }} />
        <span style={{ fontSize: 15, fontWeight: 700, color: "var(--miss-t)" }}>Se déconnecter</span>
      </button>

      <p className="text-center mt-4" style={{ fontSize: 12, color: "var(--txt3)", opacity: 0.4 }}>Folio · v1.0.0</p>
      <BottomNav />
    </div>
  );
}

FILEOF
cat > "src/app/share/[token]/page.tsx" << 'FILEOF'
"use client";
import { useEffect, useState } from "react";
import { useSession } from "next-auth/react";
import { useParams, useRouter } from "next/navigation";
import { Collection } from "@/types";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";
import { LogIn } from "lucide-react";

interface ShareData { id: string; collection: Collection; owner_name: string; }

export default function SharedCollectionPage() {
  const { token }                         = useParams<{ token: string }>();
  const { data: session, status }         = useSession();
  const router                            = useRouter();
  const [data,    setData]                = useState<ShareData | null>(null);
  const [loading, setLoading]             = useState(true);
  const [error,   setError]               = useState<string | null>(null);

  useEffect(() => {
    if (status === "loading") return;
    const viewer_email = session?.user?.email ?? "";
    fetch(`/api/share?token=${token}&viewer_email=${viewer_email}`)
      .then(r => r.json())
      .then(d => { if (d.error) setError(d.error); else setData(d); })
      .catch(() => setError("Erreur de connexion"))
      .finally(() => setLoading(false));
  }, [token, session, status]);

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center" style={{ background: "var(--bg)" }}>
      <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
    </div>
  );

  if (error || !data) return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4 px-6" style={{ background: "var(--bg)" }}>
      <p className="font-bold text-lg" style={{ color: "var(--txt1)" }}>Lien invalide ou expiré</p>
      <Button onClick={() => router.push("/library")}>Aller à ma bibliothèque</Button>
    </div>
  );

  const { collection, owner_name } = data;
  const owned   = collection.owned_volumes ?? [];
  const total   = collection.total_volumes ?? 0;
  const missing = total > 0 ? Array.from({ length: total }, (_, i) => i + 1).filter(n => !owned.includes(n)) : [];
  const pct     = total > 0 ? Math.round((owned.length / total) * 100) : 0;

  return (
    <div className="min-h-screen pb-10" style={{ background: "var(--bg)" }}>
      <div className="px-5 pt-14 pb-6" style={{ background: "var(--accent)" }}>
        <p style={{ color: "rgba(255,255,255,0.65)", fontSize: 13 }}>Collection de</p>
        <h1 className="text-3xl font-bold text-white mt-1">{owner_name}</h1>
        <p style={{ color: "rgba(255,255,255,0.75)", fontSize: 14, marginTop: 4 }}>{collection.name}</p>
      </div>

      {!session && (
        <div className="mx-4 -mt-4 mb-6 p-4 rounded-2xl shadow-sm"
          style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          <div className="flex items-start gap-3">
            <div className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0" style={{ background: "var(--accent-l)" }}>
              <LogIn className="w-5 h-5" style={{ color: "var(--accent)" }} />
            </div>
            <div className="flex-1">
              <p className="font-semibold" style={{ fontSize: 14, color: "var(--txt1)" }}>Connecte-toi pour sauvegarder</p>
              <Button onClick={() => router.push(`/login?callbackUrl=/share/${token}`)} className="mt-3 px-4 py-2 rounded-xl" size="sm">
                Se connecter avec Google
              </Button>
            </div>
          </div>
        </div>
      )}

      {session && (
        <div className="mx-4 -mt-4 mb-6 p-3 rounded-2xl"
          style={{ background: "var(--have-bg)", border: "1px solid var(--have-b)" }}>
          <p style={{ fontSize: 14, color: "var(--have-t)", fontWeight: 600 }}>✅ Ajoutée à vos bibliothèques partagées</p>
        </div>
      )}

      {/* Collection */}
      <div className="mx-4 mb-4 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="flex gap-3 p-4">
          <Cover src={collection.cover_url} alt={collection.name} width={56} height={78} className="rounded-xl flex-shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="font-bold" style={{ fontSize: 16, color: "var(--txt1)" }}>{collection.name}</p>
            {collection.author && <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{collection.author}</p>}
            <div className="flex items-center gap-2 mt-3">
              <div className="flex-1 h-2 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
                <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
              </div>
              <span className="font-bold" style={{ fontSize: 13, color: "var(--accent)" }}>{owned.length}{total ? `/${total}` : ""}</span>
            </div>
          </div>
        </div>
        {total > 0 && (
          <div className="flex flex-wrap gap-1.5 px-4 pb-4">
            {Array.from({ length: Math.min(total, 30) }, (_, i) => i + 1).map(n => (
              <div key={n} className="flex items-center justify-center font-bold"
                style={{ width: 30, height: 30, borderRadius: 8, fontSize: 11,
                  background: owned.includes(n) ? "var(--have-bg)" : "var(--miss-bg)",
                  color:      owned.includes(n) ? "var(--have-t)"  : "var(--miss-t)",
                  border:     owned.includes(n) ? "1px solid var(--have-b)" : "1px dashed var(--miss-b)" }}>
                {n}
              </div>
            ))}
          </div>
        )}
      </div>

      {missing.length > 0 && (
        <div className="mx-4">
          <p className="font-bold mb-3" style={{ fontSize: 15, color: "var(--txt1)" }}>
            {missing.length} tome{missing.length > 1 ? "s" : ""} manquant{missing.length > 1 ? "s" : ""}
          </p>
          <div className="flex flex-wrap gap-2">
            {missing.map(n => (
              <div key={n} className="px-3 py-1.5 rounded-xl font-semibold"
                style={{ background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px dashed var(--miss-b)", fontSize: 13 }}>
                Tome {n}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

FILEOF

echo "✅ Tous les fichiers écrits"
git add -A
git status --short
git commit -m "refactor: clean rebuild — remove obsolete files, unified auth architecture"
git push
echo ""
echo "🎉 Déployé sur https://etagere.vercel.app"
echo ""
echo "Architecture finale :"
echo "  src/lib/auth.ts          → resolveUser() — source unique de vérité"
echo "  src/hooks/useLibrary.ts  → hook partagé par toutes les pages"
echo "  src/app/api/             → routes propres, zéro duplication"
