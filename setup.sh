#!/bin/bash
set -e
echo "🚀 Folio — nettoyage et déploiement..."
cd "$(git rev-parse --show-toplevel)"

# ── 1. Supprimer les anciens fichiers ─────────────────────────────────────────
echo "🗑️  Suppression des anciens fichiers..."
rm -f src/lib/store.ts
rm -f src/lib/collection-service.ts
rm -f src/lib/wishlist-service.ts
rm -f src/components/book/AddBookModal.tsx
rm -f src/components/layout/LoginPage.tsx
rm -f src/components/layout/LibraryPage.tsx
rm -f src/components/layout/ScanPage.tsx
rm -f src/components/layout/StatsPage.tsx
rm -f src/components/layout/SettingsPage.tsx
rm -rf "src/components/{ui,book,collection,scanner,layout}"

# ── 2. Créer les nouveaux dossiers ────────────────────────────────────────────
echo "📁 Création de l'arborescence..."
mkdir -p src/components/ui
mkdir -p src/hooks

# ── 3. lib/constants.ts ───────────────────────────────────────────────────────
cat > src/lib/constants.ts << 'EOF'
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
  manga: { label: "Manga", emoji: "⛩️"  },
};
EOF

# ── 4. lib/supabase.ts ────────────────────────────────────────────────────────
cat > src/lib/supabase.ts << 'EOF'
import { createClient } from "@supabase/supabase-js";
const url  = process.env.NEXT_PUBLIC_SUPABASE_URL  ?? "";
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
export const supabase = url && anon ? createClient(url, anon) : null as any;
EOF

# ── 5. lib/isbn-lookup.ts ─────────────────────────────────────────────────────
cat > src/lib/isbn-lookup.ts << 'EOF'
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
    name:  title.replace(/[,\s]*(?:vol(?:ume)?\.?\s*|tome\s*|t\.\s*|#\s*)\d+.*/i, "").trim() || undefined,
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
    title:          b.title,
    authors:        (b.authors ?? []).map((a: any) => a.name),
    cover_url:      b.cover?.large ?? b.cover?.medium ?? b.cover?.small,
    publisher:      b.publishers?.[0]?.name,
    published_year: b.publish_date ? parseInt(b.publish_date.slice(-4)) : undefined,
    page_count:     b.number_of_pages,
    description:    b.excerpts?.[0]?.text,
    series_name:    typeof series === "string" ? series.replace(/\s*#?\d+.*$/, "").trim() || undefined : undefined,
    series_index:   numMatch ? parseInt(numMatch[1]) : undefined,
    book_type:      detectType(subjects + " " + b.title),
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
    title:          vol.title,
    authors:        vol.authors ?? [],
    cover_url:      vol.imageLinks?.thumbnail?.replace("http:", "https:"),
    publisher:      vol.publisher,
    published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : undefined,
    page_count:     vol.pageCount,
    description:    vol.description,
    series_name:    parsed.name,
    series_index:   parsed.index,
    book_type:      detectType(categories + " " + vol.title),
  };
}

export async function lookupISBN(isbn: string): Promise<LookupResult | null> {
  const clean = isbn.replace(/[-\s]/g, "");
  try { const r = await fromOpenLibrary(clean); if (r) return r; } catch {}
  try { const r = await fromGoogleBooks(clean);  if (r) return r; } catch {}
  return null;
}
EOF

# ── 6. lib/data.ts ────────────────────────────────────────────────────────────
cat > src/lib/data.ts << 'EOF'
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

export const getBooks   = (lid: string): Book[]    => books.filter(b => b.library_id === lid);
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
const wishlists = new Map<string, Wishlist>([
  ["wl_demo", {
    id: "wl_demo", collection_id: "c1", collection_name: "Astérix", owner_name: "Garance",
    missing_items: [
      { id: "wi_1", title: "Astérix — Tome 6", authors: ["Goscinny", "Uderzo"], series_index: 6 },
      { id: "wi_2", title: "Astérix — Tome 7", authors: ["Goscinny", "Uderzo"], series_index: 7 },
    ],
    created_at: new Date().toISOString(),
  }],
]);

export const getWishlist    = (id: string): Wishlist | null => wishlists.get(id) ?? null;
export const claimItem      = (wid: string, iid: string, name: string): boolean => {
  const wl = wishlists.get(wid); if (!wl) return false;
  const it = wl.missing_items.find(i => i.id === iid); if (!it || it.claimed_by_name) return false;
  it.claimed_by_name = name; it.claimed_at = new Date().toISOString(); return true;
};
export const createWishlist = (col: Collection, owner: string): Wishlist => {
  const total   = col.total_volumes ?? 0;
  const missing = Array.from({ length: total }, (_, i) => i + 1).filter(n => !col.owned_volumes.includes(n));
  const wl: Wishlist = {
    id: `wl_${Date.now()}`, collection_id: col.id, collection_name: col.name, owner_name: owner,
    missing_items: missing.map((n, i) => ({ id: `wi_${i}`, title: `${col.name} — Tome ${n}`, authors: col.author ? [col.author] : [], series_index: n })),
    created_at: new Date().toISOString(),
  };
  wishlists.set(wl.id, wl);
  return wl;
};
EOF

# ── 7. hooks ──────────────────────────────────────────────────────────────────
cat > src/hooks/useToast.ts << 'EOF'
import { useState, useCallback, useRef } from "react";
import { ToastData } from "@/components/ui/Toast";

export function useToast() {
  const [toasts, setToasts] = useState<ToastData[]>([]);
  const counter = useRef(0);
  const push    = useCallback((title: string, subtitle?: string) => {
    const id = counter.current++;
    setToasts(prev => [...prev, { id, title, subtitle }]);
  }, []);
  const dismiss = useCallback((id: number) => {
    setToasts(prev => prev.filter(t => t.id !== id));
  }, []);
  return { toasts, push, dismiss };
}
EOF

cat > src/hooks/useFirstUse.ts << 'EOF'
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
EOF

# ── 8. components/ui ──────────────────────────────────────────────────────────
cat > src/components/ui/Button.tsx << 'EOF'
import { ButtonHTMLAttributes, ReactNode } from "react";

interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "ghost" | "danger";
  size?: "sm" | "md" | "lg";
  children: ReactNode;
}

const VARIANTS = {
  primary:   { background: "var(--accent)",   color: "#fff",          border: "none" },
  secondary: { background: "var(--surface2)", color: "var(--txt1)",   border: "1px solid var(--border)" },
  ghost:     { background: "transparent",     color: "var(--txt2)",   border: "1px solid var(--border)" },
  danger:    { background: "var(--miss-bg)",  color: "var(--miss-t)", border: "1px solid var(--miss-b)" },
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
EOF

cat > src/components/ui/Cover.tsx << 'EOF'
"use client";
import { useState } from "react";
import { BookOpen } from "lucide-react";

interface Props { src?: string; alt: string; width?: number; height?: number; className?: string; }

export function Cover({ src, alt, width, height, className = "" }: Props) {
  const [error, setError] = useState(false);
  if (src && !error) {
    return <img src={src} alt={alt} className={`object-cover ${className}`} style={{ width, height }} onError={() => setError(true)} />;
  }
  return (
    <div className={`flex items-center justify-center ${className}`} style={{ width, height, background: "var(--placeholder)" }}>
      <BookOpen style={{ width: "35%", height: "35%", color: "var(--txt3)" }} />
    </div>
  );
}
EOF

cat > src/components/ui/Toggle.tsx << 'EOF'
interface Props { checked: boolean; onChange: (v: boolean) => void; label?: string; }

export function Toggle({ checked, onChange, label }: Props) {
  return (
    <button role="switch" aria-checked={checked} aria-label={label} onClick={() => onChange(!checked)}
      style={{ width: 48, height: 28, borderRadius: 14, border: "none", cursor: "pointer", flexShrink: 0,
        background: checked ? "var(--accent)" : "var(--border)", position: "relative", transition: "background 0.2s" }}>
      <div style={{ position: "absolute", top: 3, left: 3, width: 22, height: 22, borderRadius: 11,
        background: "#fff", transition: "transform 0.2s", transform: checked ? "translateX(20px)" : "translateX(0)" }} />
    </button>
  );
}
EOF

cat > src/components/ui/Toast.tsx << 'EOF'
"use client";
import { useEffect } from "react";
import { Check } from "lucide-react";

export interface ToastData { id: number; title: string; subtitle?: string; }

export function Toast({ toast, onDismiss, duration = 3000 }: { toast: ToastData; onDismiss: () => void; duration?: number }) {
  useEffect(() => { const t = setTimeout(onDismiss, duration); return () => clearTimeout(t); }, [onDismiss, duration]);
  return (
    <div className="flex items-center gap-3 px-4 py-3 rounded-2xl shadow-lg"
      style={{ background: "var(--have-bg)", border: "1px solid var(--have-b)", minWidth: 260, maxWidth: 320 }}>
      <div className="w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0" style={{ background: "var(--have-t)" }}>
        <Check className="w-4 h-4 text-white" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{toast.title}</p>
        {toast.subtitle && <p className="truncate" style={{ fontSize: 12, color: "var(--txt2)", marginTop: 1 }}>{toast.subtitle}</p>}
      </div>
    </div>
  );
}

export function ToastStack({ toasts, onDismiss }: { toasts: ToastData[]; onDismiss: (id: number) => void }) {
  if (!toasts.length) return null;
  return (
    <div className="fixed bottom-24 left-0 right-0 z-50 flex flex-col items-center gap-2 px-4 pointer-events-none">
      {toasts.map(t => <Toast key={t.id} toast={t} onDismiss={() => onDismiss(t.id)} />)}
    </div>
  );
}
EOF

cat > src/components/ui/StatusBadge.tsx << 'EOF'
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
EOF

echo "✅ Composants UI créés"

# ── 9. Git ────────────────────────────────────────────────────────────────────
echo "📦 Commit et push..."
git add -A
git commit -m "refactor: clean architecture — atomic UI, hooks, constants, unified data layer"
git push
echo ""
echo "🎉 Déployé ! Vercel build en cours..."
echo "🔗 https://etagere.vercel.app"
