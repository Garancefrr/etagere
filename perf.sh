#!/bin/bash
set -e
echo "⚡ Optimisations perf — cache, contexte partagé, API parallèles..."
cd "$(git rev-parse --show-toplevel)"
mkdir -p src/contexts
cat > "src/hooks/useLibrary.ts" << 'FILEOF'
"use client";
import { useState, useEffect } from "react";
import { useSession } from "next-auth/react";

interface LibState {
  library_id: string | null;
  profile_id: string | null;
  email: string | null;
  loading: boolean;
}

const CACHE_KEY = "folio_library";

export function useLibrary(): LibState {
  const { data: session, status } = useSession();
  const [state, setState] = useState<LibState>(() => {
    // Try sessionStorage first for instant load
    if (typeof window !== "undefined") {
      try {
        const cached = sessionStorage.getItem(CACHE_KEY);
        if (cached) {
          const parsed = JSON.parse(cached);
          return { ...parsed, loading: false };
        }
      } catch { /* ignore */ }
    }
    return { library_id: null, profile_id: null, email: null, loading: true };
  });

  useEffect(() => {
    if (status === "loading") return;
    const email = session?.user?.email;
    if (!email) { setState({ library_id: null, profile_id: null, email: null, loading: false }); return; }

    // If cached email matches, skip fetch
    if (state.library_id && state.email === email && !state.loading) return;

    fetch(`/api/library?email=${encodeURIComponent(email)}`)
      .then(r => r.json())
      .then(d => {
        const s = { library_id: d.id, profile_id: d.profile_id, email, loading: false };
        setState(s);
        try { sessionStorage.setItem(CACHE_KEY, JSON.stringify(s)); } catch { /* ignore */ }
      })
      .catch(() => setState(prev => ({ ...prev, loading: false })));
  }, [session?.user?.email, status]); // eslint-disable-line react-hooks/exhaustive-deps

  return state;
}
FILEOF
cat > "src/contexts/DataContext.tsx" << 'FILEOF'
"use client";
import { createContext, useContext, useState, useCallback, useEffect, useRef } from "react";
import { useLibrary } from "@/hooks/useLibrary";
import { Book, Collection } from "@/types";

interface DataState {
  books: Book[];
  collections: Collection[];
  loading: boolean;
  refreshBooks: () => Promise<void>;
  refreshCollections: () => Promise<void>;
  refreshAll: () => Promise<void>;
  setBooks: React.Dispatch<React.SetStateAction<Book[]>>;
  setCollections: React.Dispatch<React.SetStateAction<Collection[]>>;
  library_id: string | null;
  email: string | null;
}

const DataContext = createContext<DataState>({
  books: [], collections: [], loading: true,
  refreshBooks: async () => {}, refreshCollections: async () => {},
  refreshAll: async () => {}, setBooks: () => {}, setCollections: () => {},
  library_id: null, email: null,
});

export function DataProvider({ children }: { children: React.ReactNode }) {
  const { library_id, email, loading: libLoading } = useLibrary();
  const [books,       setBooks]       = useState<Book[]>([]);
  const [collections, setCollections] = useState<Collection[]>([]);
  const [dataLoaded,  setDataLoaded]  = useState(false);
  const fetchedRef = useRef(false);

  const refreshBooks = useCallback(async () => {
    if (!library_id) return;
    try {
      const res = await fetch(`/api/books?library_id=${library_id}`);
      if (res.ok) setBooks(await res.json());
    } catch { /* ignore */ }
  }, [library_id]);

  const refreshCollections = useCallback(async () => {
    if (!library_id) return;
    try {
      const res = await fetch(`/api/collections?library_id=${library_id}`);
      if (res.ok) { const d = await res.json(); if (Array.isArray(d)) setCollections(d); }
    } catch { /* ignore */ }
  }, [library_id]);

  const refreshAll = useCallback(async () => {
    await Promise.all([refreshBooks(), refreshCollections()]);
  }, [refreshBooks, refreshCollections]);

  // Initial fetch — once
  useEffect(() => {
    if (!library_id || fetchedRef.current) return;
    fetchedRef.current = true;
    Promise.all([
      fetch(`/api/books?library_id=${library_id}`).then(r => r.json()).then(d => Array.isArray(d) ? setBooks(d) : null),
      fetch(`/api/collections?library_id=${library_id}`).then(r => r.json()).then(d => Array.isArray(d) ? setCollections(d) : null),
    ]).finally(() => setDataLoaded(true));
  }, [library_id]);

  // Refresh on tab focus
  useEffect(() => {
    if (!library_id) return;
    const onVisible = () => { if (document.visibilityState === "visible") refreshAll(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }, [library_id, refreshAll]);

  const loading = libLoading || !dataLoaded;

  return (
    <DataContext.Provider value={{ books, collections, loading, refreshBooks, refreshCollections, refreshAll, setBooks, setCollections, library_id, email }}>
      {children}
    </DataContext.Provider>
  );
}

export const useData = () => useContext(DataContext);
FILEOF
cat > "src/app/providers.tsx" << 'FILEOF'
"use client";
import { SessionProvider } from "next-auth/react";
import { ThemeProvider } from "@/components/layout/ThemeProvider";
import { DataProvider } from "@/contexts/DataContext";

export default function Providers({ children }: { children: React.ReactNode }) {
  return (
    <SessionProvider>
      <ThemeProvider>
        <DataProvider>{children}</DataProvider>
      </ThemeProvider>
    </SessionProvider>
  );
}
FILEOF
cat > "src/lib/isbn-lookup.ts" << 'FILEOF'
import { LookupResult, BookType } from "@/types";

function detectType(terms: string): BookType {
  const t = terms.toLowerCase();
  if (/manga|manhwa|shonen|shojo|seinen|josei|kodansha|shueisha|viz|one.piece|naruto|dragon.ball/.test(t)) return "manga";
  if (/bande.dessin|bd|comics|dargaud|dupuis|lombard|casterman|lucky|schtroumpf|ast[eé]rix|tintin|spirou|blake|mortimer|franco.belge/.test(t)) return "bd";
  return "livre";
}

function extractSeries(title: string): { seriesName?: string; seriesIndex?: number } {
  const patterns = [
    /^(.+?)\s*[-–—]\s*(?:tome|t\.?|vol(?:ume)?\.?|#)\s*(\d+)/i,
    /^(.+?)\s*,\s*(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i,
    /^(.+?)\s+(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i,
    /^(.+?)\s*\((?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)\)/i,
  ];
  for (const re of patterns) {
    const m = title.match(re);
    if (m && parseInt(m[2]) <= 200) {
      return { seriesName: m[1].replace(/\s+$/, "").trim() || undefined, seriesIndex: parseInt(m[2]) };
    }
  }
  return {};
}

// ISBN = 978/979 (13 digits) or 10 digits
// ── Google Books ──────────────────────────────────────────────────────────────

async function fromGoogleBooks(code: string): Promise<LookupResult | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";
  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=isbn:${code}${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) { console.error("Google Books error:", res.status); return null; }
    const data = await res.json();
    const vol = data.items?.[0]?.volumeInfo;
    if (!vol?.title) return null;

    const categories = (vol.categories ?? []).join(" ").toLowerCase();
    const rawTitle   = vol.title ?? "";
    // Clean title: take first part before ";" (multi-story compilations)
    const cleanTitle = rawTitle.includes(";") ? rawTitle.split(";")[0].trim() : rawTitle;
    const fullTitle  = `${cleanTitle} ${vol.subtitle ?? ""}`.trim();

    let seriesName: string | undefined;
    let seriesIndex: number | undefined;
    const seriesInfo = data.items?.[0]?.volumeInfo?.seriesInfo;
    if (seriesInfo?.bookDisplayNumber) seriesIndex = parseInt(seriesInfo.bookDisplayNumber);

    // Try extracting series from "Series - Tome X - Title" pattern
    const parsed = extractSeries(fullTitle);
    seriesName  = parsed.seriesName ?? seriesName;
    seriesIndex = seriesIndex ?? parsed.seriesIndex;

    // If no series detected but it looks like a BD, try to extract series name
    // from the title pattern "Les X something" → series "Les X"
    if (!seriesName && seriesIndex) {
      // We have a volume number from seriesInfo but no name
      // Use the main title words as series name
      seriesName = cleanTitle.replace(/\s*[-–—].*$/, "").trim() || undefined;
    }

    let coverUrl = vol.imageLinks?.extraLarge ?? vol.imageLinks?.large ?? vol.imageLinks?.medium ?? vol.imageLinks?.thumbnail;
    if (coverUrl) coverUrl = coverUrl.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");

    return {
      isbn: code, title: cleanTitle, authors: vol.authors ?? [],
      cover_url: coverUrl, publisher: vol.publisher,
      published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : undefined,
      page_count: vol.pageCount, description: vol.description,
      series_name: seriesName, series_index: seriesIndex,
      book_type: detectType(categories + " " + fullTitle + " " + (vol.publisher ?? "")),
    };
  } catch { return null; }
}

// ── BnF SRU API ───────────────────────────────────────────────────────────────

async function fromBnF(code: string): Promise<LookupResult | null> {
  try {
    for (const field of ["bib.ean", "bib.isbn"]) {
      const url = `https://catalogue.bnf.fr/api/SRU?version=1.2&operation=searchRetrieve&query=${field}+adj+"${code}"&recordSchema=unimarcxchange&maximumRecords=1`;
      const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
      const text = await res.text();
      if (text.includes("<numberOfRecords>0")) continue;

      const titleA   = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
      const titleE   = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="e">([^<]+)/)?.[1]?.trim();
      if (!titleA) continue;
      const title    = titleE ? `${titleA} — ${titleE}` : titleA;

      const volStr    = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="h">([^<]+)/)?.[1]?.trim();
      const volNum    = volStr ? parseInt(volStr.replace(/\D/g, "")) : undefined;
      const seriesRaw = text.match(/<datafield tag="225"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
      const seriesVol = text.match(/<datafield tag="225"[^>]*>[\s\S]*?<subfield code="v">([^<]+)/)?.[1]?.trim();
      const authorB   = text.match(/<datafield tag="700"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
      const authorF   = text.match(/<datafield tag="700"[^>]*>[\s\S]*?<subfield code="b">([^<]+)/)?.[1]?.trim();
      const author    = authorB ? [authorF ? `${authorF} ${authorB}` : authorB] : [];
      const publisher = text.match(/<datafield tag="210"[^>]*>[\s\S]*?<subfield code="c">([^<]+)/)?.[1]?.trim();
      const yearStr   = text.match(/<datafield tag="210"[^>]*>[\s\S]*?<subfield code="d">(\d{4})/)?.[1];
      const subjects  = text.match(/<subfield code="a">([^<]+)/g)?.join(" ") ?? "";

      let seriesName  = seriesRaw?.replace(/\s*#?\d+.*$/, "").trim();
      let seriesIndex = seriesVol ? parseInt(seriesVol.replace(/\D/g, "")) : volNum;
      if (!seriesName) { const p = extractSeries(title); seriesName = p.seriesName; seriesIndex = p.seriesIndex ?? seriesIndex; }

      return {
        isbn: code, title, authors: author,
        cover_url: `https://catalogue.bnf.fr/couverture?&isbn=${code}&notoile=1`,
        publisher, published_year: yearStr ? parseInt(yearStr) : undefined,
        series_name: seriesName, series_index: seriesIndex,
        book_type: detectType(subjects + " " + title + " " + (publisher ?? "") + " " + (seriesName ?? "")),
      };
    }
    return null;
  } catch { return null; }
}

// ── Open Library ──────────────────────────────────────────────────────────────

async function fromOpenLibrary(isbn: string): Promise<LookupResult | null> {
  try {
    const res = await fetch(
      `https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`,
      { signal: AbortSignal.timeout(5000) }
    );
    const data = await res.json();
    const b    = data[`ISBN:${isbn}`];
    if (!b?.title) return null;

    const subjects   = (b.subjects ?? []).map((s: any) => typeof s === "string" ? s : s.name ?? "").join(" ").toLowerCase();
    const series     = Array.isArray(b.series) ? b.series[0] : b.series;
    const numMatch   = typeof series === "string" ? series.match(/#?(\d+)/) : null;
    const { seriesName: parsedName, seriesIndex: parsedIdx } = extractSeries(b.title);

    return {
      isbn, title: b.title,
      authors: (b.authors ?? []).map((a: any) => a.name),
      cover_url: b.cover?.large ?? b.cover?.medium ?? b.cover?.small,
      publisher: b.publishers?.[0]?.name,
      published_year: b.publish_date ? parseInt(b.publish_date.slice(-4)) : undefined,
      page_count: b.number_of_pages, description: b.excerpts?.[0]?.text,
      series_name: (typeof series === "string" ? series.replace(/\s*#?\d+.*$/, "").trim() || undefined : undefined) ?? parsedName,
      series_index: numMatch ? parseInt(numMatch[1]) : parsedIdx,
      book_type: detectType(subjects + " " + b.title),
    };
  } catch { return null; }
}

// ── Main lookup ───────────────────────────────────────────────────────────────

// Convert ISBN-10 to ISBN-13
function isbn10to13(isbn10: string): string {
  const base = "978" + isbn10.slice(0, 9);
  let sum = 0;
  for (let i = 0; i < 12; i++) sum += parseInt(base[i]) * (i % 2 === 0 ? 1 : 3);
  return base + ((10 - (sum % 10)) % 10);
}

export async function lookupISBN(code: string): Promise<LookupResult | null> {
  const clean = code.replace(/[-\s]/g, "");
  const isIsbn10 = /^\d{9}[\dXx]$/.test(clean);
  const isIsbn13 = /^(978|979)\d{10}$/.test(clean);
  const isbn13 = isIsbn10 ? isbn10to13(clean) : clean;

  // For valid ISBNs: try Google Books + BnF in PARALLEL (2-3x faster)
  if (isIsbn10 || isIsbn13) {
    const results = await Promise.allSettled([
      fromGoogleBooks(clean),
      isIsbn10 ? fromGoogleBooks(isbn13) : Promise.resolve(null),
      fromBnF(isbn13),
      isIsbn10 ? fromBnF(clean) : Promise.resolve(null),
    ]);
    for (const r of results) {
      if (r.status === "fulfilled" && r.value?.title) return r.value;
    }
  }

  // Fallback: BnF for non-ISBN 13-digit codes
  if (/^\d{13}$/.test(clean) && !isIsbn13) {
    const bnf = await fromBnF(clean);
    if (bnf?.title) return bnf;
  }

  // Last resort: Open Library
  const codes = [clean];
  if (isIsbn10) codes.push(isbn13);
  for (const c of codes) {
    const ol = await fromOpenLibrary(c);
    if (ol?.title) {
      if (!isIsbn10 && !isIsbn13) ol._unreliable = true;
      return ol;
    }
  }

  return null;
}
FILEOF
cat > "src/app/library/page.tsx" << 'FILEOF'
"use client";
import { useState, useMemo } from "react";
import { useSession } from "next-auth/react";
import { Book, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { useData } from "@/contexts/DataContext";
import BookCard from "@/components/book/BookCard";
import BookDetail from "@/components/book/BookDetail";
import BottomNav from "@/components/layout/BottomNav";
import { Search, SlidersHorizontal, LayoutGrid, List, RefreshCw } from "lucide-react";

type Layout       = "grid" | "list";
type FilterType   = BookType | "all";
type FilterStatus = ReadStatus | "all";

export default function LibraryPage() {
  const { data: session } = useSession();
  const { books, collections, loading, library_id, setBooks, refreshAll, refreshCollections } = useData();
  const [search,         setSearch]         = useState("");
  const [filterStatus,   setFilterStatus]   = useState<FilterStatus>("all");
  const [filterType,     setFilterType]     = useState<FilterType>("all");
  const [layout,         setLayout]         = useState<Layout>("grid");
  const [selected,       setSelected]       = useState<Book | null>(null);
  const [showFilters,    setShowFilters]    = useState(false);

  // ── Computed ────────────────────────────────────────────────────────────────
  const stats = useMemo(() => ({
    lu:       books.filter(b => b.status === "lu").length,
    en_cours: books.filter(b => b.status === "en_cours").length,
    a_lire:   books.filter(b => b.status === "a_lire").length,
  }), [books]);

  const filtered = useMemo(() => books.filter(b => {
    const q = search.toLowerCase();
    return (
      (!q || b.title.toLowerCase().includes(q) || b.authors.some(a => a.toLowerCase().includes(q))) &&
      (filterStatus === "all" || b.status === filterStatus) &&
      (filterType   === "all" || b.book_type === filterType)
    );
  }), [books, search, filterStatus, filterType]);

  // ── Mutations ───────────────────────────────────────────────────────────────
  const handleUpdate = async (id: string, updates: Partial<Book>) => {
    await fetch("/api/books", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, library_id, ...updates }),
    });
    setBooks(prev => prev.map(b => b.id === id ? { ...b, ...updates } : b));
    setSelected(prev => prev?.id === id ? { ...prev, ...updates } as Book : prev);
    if (updates.series_name || updates.series_index) refreshCollections();
  };

  const handleDelete = async (id: string) => {
    await fetch("/api/books", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    });
    setBooks(prev => prev.filter(b => b.id !== id));
    setSelected(null);
    refreshCollections();
  };

  const userName = session?.user?.name?.split(" ")[0] ?? "toi";

  // ── Render ──────────────────────────────────────────────────────────────────

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center" style={{ background: "var(--bg)" }}>
      <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
      <BottomNav />
    </div>
  );

  return (
    <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>

      {/* Sticky header */}
      <div className="sticky top-0 z-30 px-4 pt-12 pb-3" style={{ background: "var(--bg)" }}>

        {/* Hero banner */}
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
                  <p style={{ color: "rgba(255,255,255,0.6)", fontSize: 12, marginTop: 2 }}>
                    {STATUS_CONFIG[s].label}
                  </p>
                </div>
              ))}
            </div>
          </div>
          <div className="flex flex-col items-end gap-2">
            {session?.user?.image
              ? <img src={session.user.image} alt="" className="w-12 h-12 rounded-xl object-cover flex-shrink-0" />
              : <div className="w-12 h-12 rounded-xl flex items-center justify-center font-bold flex-shrink-0"
                  style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>
                  {userName[0]}
                </div>}
          </div>
        </div>

        {/* Search + controls */}
        <div className="flex gap-2 mb-3">
          <div className="flex-1 flex items-center gap-2 px-4 py-3 rounded-2xl"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <Search className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
            <input
              type="text" value={search} onChange={e => setSearch(e.target.value)}
              placeholder="Titre, auteur..."
              className="flex-1 outline-none bg-transparent"
              style={{ color: "var(--txt1)", fontSize: 15 }}
            />
          </div>
          <button
            onClick={() => refreshAll()}
            className="w-11 h-11 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <RefreshCw className="w-5 h-5" style={{ color: "var(--txt2)" }} />
          </button>
          <button
            onClick={() => setLayout(l => l === "grid" ? "list" : "grid")}
            className="w-11 h-11 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            {layout === "grid"
              ? <List className="w-5 h-5" style={{ color: "var(--txt2)" }} />
              : <LayoutGrid className="w-5 h-5" style={{ color: "var(--txt2)" }} />}
          </button>
          <button
            onClick={() => setShowFilters(f => !f)}
            className="w-11 h-11 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{
              background: showFilters ? "var(--accent)" : "var(--surface)",
              border: `1px solid ${showFilters ? "var(--accent)" : "var(--border)"}`,
            }}>
            <SlidersHorizontal className="w-5 h-5" style={{ color: showFilters ? "#fff" : "var(--txt2)" }} />
          </button>
        </div>

        {/* Filters */}
        {showFilters && (
          <div className="space-y-2 mb-2">
            <FilterRow
              options={[{ v:"all", l:"Tous" }, ...Object.entries(STATUS_CONFIG).map(([v,c]) => ({ v, l:`${c.emoji} ${c.label}` }))]}
              value={filterStatus}
              onChange={v => setFilterStatus(v as FilterStatus)}
            />
            <FilterRow
              options={[{ v:"all", l:"Tous types" }, ...Object.entries(TYPE_CONFIG).map(([v,c]) => ({ v, l:`${c.emoji} ${c.label}` }))]}
              value={filterType}
              onChange={v => setFilterType(v as FilterType)}
            />
          </div>
        )}
      </div>

      {/* Count */}
      <div className="flex justify-between items-center px-4 mb-3">
        <span className="font-bold" style={{ fontSize: 15, color: "var(--txt1)" }}>
          {loading ? "Chargement…" : `${filtered.length} ouvrage${filtered.length > 1 ? "s" : ""}`}
        </span>
      </div>

      {/* Book list */}
      <div className="px-4">
        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 rounded-full border-2 animate-spin"
              style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center py-20 gap-3">
            <p className="font-semibold" style={{ fontSize: 17, color: "var(--txt1)" }}>
              {books.length > 0 ? "Aucun résultat" : "Bibliothèque vide"}
            </p>
            <p style={{ fontSize: 14, color: "var(--txt3)" }}>
              {books.length > 0 ? "Essayez un autre filtre" : "Scannez votre premier livre !"}
            </p>
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

      {selected && (
        <BookDetail
          book={selected}
          collections={collections}
          onClose={() => setSelected(null)}
          onUpdate={handleUpdate}
          onDelete={handleDelete}
        />
      )}
      <BottomNav />
    </div>
  );
}

// ── Internal components ───────────────────────────────────────────────────────

function FilterRow({ options, value, onChange }: {
  options: { v: string; l: string }[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="flex gap-2 overflow-x-auto pb-1" style={{ scrollbarWidth: "none" }}>
      {options.map(({ v, l }) => (
        <button key={v} onClick={() => onChange(v)}
          className="flex-shrink-0 px-4 py-2 rounded-full font-semibold"
          style={{
            fontSize: 13,
            background: value === v ? "var(--accent)" : "var(--surface)",
            color: value === v ? "#fff" : "var(--txt2)",
            border: `1px solid ${value === v ? "var(--accent)" : "var(--border)"}`,
          }}>
          {l}
        </button>
      ))}
    </div>
  );
}

function BookListRow({ book, onClick }: { book: Book; onClick: () => void }) {
  const { bg, color, label } = STATUS_CONFIG[book.status];
  return (
    <button onClick={onClick}
      className="flex items-center gap-3 p-3 rounded-2xl text-left active:scale-[0.98]"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
      <div className="rounded-xl overflow-hidden flex-shrink-0"
        style={{ width: 52, height: 72, background: "var(--placeholder)" }}>
        {book.cover_url && (
          <img src={book.cover_url} alt="" className="w-full h-full object-cover" />
        )}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-semibold truncate" style={{ fontSize: 15, color: "var(--txt1)" }}>
          {book.title}
        </p>
        <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{book.authors[0]}</p>
        {book.series_name && (
          <p style={{ fontSize: 12, color: "var(--accent)", marginTop: 2 }}>
            {book.series_name} #{book.series_index}
          </p>
        )}
      </div>
      <span className="px-3 py-1.5 rounded-full font-semibold flex-shrink-0"
        style={{ fontSize: 12, background: bg, color }}>
        {label}
      </span>
    </button>
  );
}
FILEOF
cat > "src/app/collections/page.tsx" << 'FILEOF'
"use client";
import { useState, useEffect, useRef } from "react";
import { Collection, BookType } from "@/types";
import { useLibrary } from "@/hooks/useLibrary";
import { useData } from "@/contexts/DataContext";
import CollectionCard from "@/components/collection/CollectionCard";
import BottomNav from "@/components/layout/BottomNav";
import { Button } from "@/components/ui/Button";
import { Cover } from "@/components/ui/Cover";
import { Search, Plus, X, Share2, Check, MessageCircle } from "lucide-react";

interface SeriesSuggestion {
  name: string;
  author?: string;
  total_volumes?: number;
  cover_url?: string;
  book_type: "livre" | "bd" | "manga";
}

function CreateModal({ onClose, onCreate }: { onClose: () => void; onCreate: (c: Partial<Collection>) => void }) {
  const [name,        setName]        = useState("");
  const [type,        setType]        = useState<BookType>("bd");
  const [author,      setAuthor]      = useState("");
  const [total,       setTotal]       = useState("");
  const [coverUrl,    setCoverUrl]    = useState<string | undefined>();
  const [suggestions, setSuggestions] = useState<SeriesSuggestion[]>([]);
  const [searching,   setSearching]   = useState(false);
  const timerRef = useRef<NodeJS.Timeout | null>(null);

  // Debounced search
  const handleNameChange = (value: string) => {
    setName(value);
    if (timerRef.current) clearTimeout(timerRef.current);
    if (value.length < 2) { setSuggestions([]); return; }
    setSearching(true);
    timerRef.current = setTimeout(async () => {
      try {
        const res = await fetch(`/api/series?q=${encodeURIComponent(value)}`);
        if (res.ok) setSuggestions(await res.json());
      } catch { /* ignore */ }
      setSearching(false);
    }, 400);
  };

  const selectSuggestion = (s: SeriesSuggestion) => {
    setName(s.name);
    setAuthor(s.author ?? "");
    setTotal(s.total_volumes?.toString() ?? "");
    setType(s.book_type);
    setCoverUrl(s.cover_url);
    setSuggestions([]);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)", maxHeight: "90vh", overflowY: "auto" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-5">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Nouvelle collection</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}>
            <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
          </button>
        </div>
        <div className="space-y-4">
          {/* Name with API search */}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>
              Nom de la série
            </label>
            <div className="relative">
              <div className="flex items-center gap-2 px-4 py-3 rounded-2xl"
                style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                <Search className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
                <input type="text" value={name} onChange={e => handleNameChange(e.target.value)}
                  placeholder="Rechercher une série..."
                  className="flex-1 outline-none bg-transparent"
                  style={{ color: "var(--txt1)", fontSize: 15 }} />
                {searching && (
                  <div className="w-4 h-4 rounded-full border-2 animate-spin flex-shrink-0"
                    style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
                )}
              </div>

              {/* Suggestions dropdown */}
              {suggestions.length > 0 && (
                <div className="absolute left-0 right-0 top-full mt-1 rounded-2xl overflow-hidden z-20 max-h-64 overflow-y-auto"
                  style={{ background: "var(--surface2)", border: "1px solid var(--border)", boxShadow: "0 8px 24px rgba(0,0,0,0.4)" }}>
                  {suggestions.map(s => (
                    <button key={s.name} onClick={() => selectSuggestion(s)}
                      className="w-full flex items-center gap-3 px-4 py-3 text-left active:opacity-70"
                      style={{ borderBottom: "1px solid var(--border)" }}>
                      <Cover src={s.cover_url} alt={s.name} width={36} height={50} className="rounded-lg flex-shrink-0" />
                      <div className="flex-1 min-w-0">
                        <p className="font-semibold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{s.name}</p>
                        <p style={{ fontSize: 12, color: "var(--txt2)", marginTop: 1 }}>
                          {s.author ?? ""}{s.total_volumes ? ` · ${s.total_volumes} tomes` : ""}
                        </p>
                      </div>
                      <span style={{ fontSize: 12, color: "var(--accent)", fontWeight: 600, flexShrink: 0 }}>
                        {s.book_type === "bd" ? "🎨" : s.book_type === "manga" ? "⛩️" : "📖"}
                      </span>
                    </button>
                  ))}
                </div>
              )}
            </div>
            <p style={{ fontSize: 11, color: "var(--txt3)", marginTop: 4 }}>
              Tape le nom pour chercher dans Google Books
            </p>
          </div>

          {/* Preview if suggestion selected */}
          {coverUrl && (
            <div className="flex items-center gap-3 p-3 rounded-2xl" style={{ background: "var(--have-bg)", border: "1px solid var(--have-b)" }}>
              <Check className="w-4 h-4 flex-shrink-0" style={{ color: "var(--have-t)" }} />
              <p style={{ fontSize: 13, color: "var(--have-t)", fontWeight: 600 }}>
                {name} — {total} tomes · {author}
              </p>
            </div>
          )}

          {/* Type */}
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

          {/* Author */}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Auteur</label>
            <input type="text" value={author} onChange={e => setAuthor(e.target.value)} placeholder="Ex: Peyo..."
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>

          {/* Total volumes */}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Nombre total de tomes</label>
            <input type="number" value={total} onChange={e => setTotal(e.target.value)} placeholder="Ex: 40"
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>

          <Button onClick={() => {
            if (name.trim()) {
              onCreate({
                name: name.trim(), book_type: type,
                author: author.trim() || undefined,
                total_volumes: total ? parseInt(total) : undefined,
                cover_url: coverUrl,
                owned_volumes: [],
              });
              onClose();
            }
          }} className="w-full py-4 rounded-2xl" style={{ fontSize: 15 }}>
            Créer la collection
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

function EditModal({ collection, onClose, onSave }: { collection: Collection; onClose: () => void; onSave: (id: string, updates: Partial<Collection>) => void }) {
  const [name,   setName]   = useState(collection.name);
  const [author, setAuthor] = useState(collection.author ?? "");
  const [total,  setTotal]  = useState(collection.total_volumes?.toString() ?? "");
  const [type,   setType]   = useState<BookType>(collection.book_type);
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-5">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Modifier</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}><X className="w-4 h-4" style={{ color: "var(--txt2)" }} /></button>
        </div>
        <div className="space-y-4">
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Nom</label>
            <input type="text" value={name} onChange={e => setName(e.target.value)} className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Auteur</label>
            <input type="text" value={author} onChange={e => setAuthor(e.target.value)} className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Nombre total de tomes</label>
            <input type="number" value={total} onChange={e => setTotal(e.target.value)} className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>
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
          <Button onClick={() => { if (name.trim()) onSave(collection.id, { name: name.trim(), author: author.trim() || undefined, total_volumes: total ? parseInt(total) : undefined, book_type: type }); }}
            className="w-full py-4 rounded-2xl" style={{ fontSize: 15 }}>Enregistrer</Button>
        </div>
      </div>
    </div>
  );
}

type Filter = "all" | "bd" | "manga" | "livre";

export default function CollectionsPage() {
  const { collections, setCollections, loading: dataLoading, library_id } = useData();
  const { profile_id } = useLibrary();
  const [search,          setSearch]         = useState("");
  const [filter,          setFilter]         = useState<Filter>("all");
  const [showCreate,      setShowCreate]     = useState(false);
  const [shareCol,        setShareCol]       = useState<Collection | null>(null);
  const [editCol,         setEditCol]        = useState<Collection | null>(null);
  const [deleteId,        setDeleteId]       = useState<string | null>(null);

  const handleCreate = async (data: Partial<Collection>) => {
    if (!library_id) return;
    const res = await fetch("/api/collections", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...data, library_id, owned_volumes: data.owned_volumes ?? [] }) });
    if (res.ok) { const col = await res.json(); setCollections(prev => [col, ...prev]); }
  };

  const handleEdit = async (id: string, updates: Partial<Collection>) => {
    await fetch("/api/collections", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id, ...updates }) });
    setCollections(prev => prev.map(c => c.id === id ? { ...c, ...updates } : c));
    setEditCol(null);
  };

  const handleDelete = async (id: string) => {
    await fetch("/api/collections", { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id }) });
    setCollections(prev => prev.filter(c => c.id !== id));
    setDeleteId(null);
  };

  const filtered = collections.filter(c =>
    (filter === "all" || c.book_type === filter) &&
    (!search || c.name.toLowerCase().includes(search.toLowerCase()) || c.author?.toLowerCase().includes(search.toLowerCase()))
  );
  const loading = dataLoading;

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center" style={{ background: "var(--bg)" }}>
      <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
      <BottomNav />
    </div>
  );

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
            <CollectionCard collection={c} onEdit={() => setEditCol(c)} onDelete={() => setDeleteId(c.id)} />
            {deleteId === c.id && (
              <div className="flex gap-2 mt-2">
                <button onClick={() => handleDelete(c.id)} className="flex-1 py-3 rounded-2xl font-semibold"
                  style={{ background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px solid var(--miss-b)", fontSize: 13 }}>
                  Confirmer la suppression
                </button>
                <button onClick={() => setDeleteId(null)} className="px-4 py-3 rounded-2xl font-semibold"
                  style={{ background: "var(--surface)", color: "var(--txt2)", border: "1px solid var(--border)", fontSize: 13 }}>
                  Annuler
                </button>
              </div>
            )}
            <button onClick={() => setShareCol(c)} className="w-full mt-2 py-3 rounded-2xl font-semibold flex items-center justify-center gap-2 active:scale-95"
              style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt2)", fontSize: 13 }}>
              <Share2 className="w-4 h-4" style={{ color: "var(--accent)" }} /> Partager
            </button>
          </div>
        ))}
      </div>

      {showCreate && <CreateModal onClose={() => setShowCreate(false)} onCreate={handleCreate} />}
      {editCol && <EditModal collection={editCol} onClose={() => setEditCol(null)} onSave={handleEdit} />}
      {shareCol && profile_id && <ShareModal collection={shareCol} profileId={profile_id} onClose={() => setShareCol(null)} />}
      <BottomNav />
    </div>
  );
}
FILEOF
cat > "src/app/scan/page.tsx" << 'FILEOF'
"use client";
import { useState, useCallback } from "react";
import { useData } from "@/contexts/DataContext";
import { useLibrary } from "@/hooks/useLibrary";
import { useToast } from "@/hooks/useToast";
import { useFirstUse } from "@/hooks/useFirstUse";
import BottomNav from "@/components/layout/BottomNav";
import Scanner from "@/components/scanner/Scanner";
import { ToastStack } from "@/components/ui/Toast";
import { ScanLine, Zap, Settings2 } from "lucide-react";

interface SavedBook {
  title: string;
  collection_name?: string;
  is_new_collection?: boolean;
}

const MODES = [
  { key: false, icon: Settings2, label: "Mode classique", sub: "Confirmation avant ajout" },
  { key: true,  icon: Zap,       label: "Mode rapide",    sub: "Ajout instantané si fiable" },
] as const;

export default function ScanPage() {
  const { library_id, email } = useLibrary();
  const { collections, refreshAll, loading: dataLoading } = useData();
  const [scanning,    setScanning]        = useState(false);
  const [rapidMode,   setRapidMode]       = useState(false);
  const isFirstUse                        = useFirstUse("folio_scan_seen");
  const { toasts, push, dismiss }         = useToast();

  const handleSuccess = useCallback((saved: SavedBook) => {
    push(saved.title, saved.is_new_collection
      ? `Collection « ${saved.collection_name} » créée`
      : saved.collection_name
        ? `Ajouté à ${saved.collection_name}`
        : undefined);
    if (!rapidMode) setScanning(false);
    refreshAll(); // Refresh shared context
  }, [rapidMode, push, refreshAll]);

  if (isFirstUse === null) return null;
  const ready = !!library_id && !!email && !dataLoading;

  return (
    <>
      <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>
        <div className="px-4 pt-12 pb-4">
          <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Ajouter</p>
          <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Scanner</h1>
        </div>

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
          collections={collections}
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
        style={{ background: ready ? "var(--accent)" : "var(--surface)", boxShadow: ready ? "0 8px 32px rgba(59,91,255,0.35)" : "none", opacity: ready ? 1 : 0.6, cursor: ready ? "pointer" : "default" }}>
        {!ready
          ? <div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
          : <ScanLine className="w-7 h-7 text-white" />}
        <span className="font-bold text-white" style={{ fontSize: 17 }}>
          {!ready ? "Chargement…" : rapidMode ? "Lancer le mode rapide" : "Ouvrir le scanner"}
        </span>
      </button>
      {ready && <p className="text-center" style={{ fontSize: 13, color: "var(--txt3)" }}>
        {rapidMode ? "Ajout auto si fiable, sinon correction" : "ISBN ou EAN détecté automatiquement"}
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
        <span className="font-bold text-white text-sm">{ready ? "Scanner" : "…"}</span>
      </button>
      <div className="text-center">
        <p className="font-bold" style={{ fontSize: 17, color: "var(--txt1)" }}>Scannez le code-barres</p>
        <p style={{ fontSize: 14, color: "var(--txt3)", marginTop: 4 }}>ISBN ou EAN au dos du livre</p>
      </div>
      <div className="w-full space-y-2">
        {["Pointez la caméra vers le code-barres", "La détection est automatique", "Corrigez si besoin, la collection se crée toute seule"].map((text, i) => (
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
cat > "src/app/stats/page.tsx" << 'FILEOF'
"use client";
import { useMemo } from "react";
import { useData } from "@/contexts/DataContext";
import BottomNav from "@/components/layout/BottomNav";
import { BookOpen, TrendingUp, FileText, Star } from "lucide-react";

export default function StatsPage() {
  const { books, loading } = useData();

  const stats = useMemo(() => {
    const lu      = books.filter(b => b.status === "lu");
    const pages   = lu.reduce((s, b) => s + (b.page_count ?? 0), 0);
    const ratings = lu.filter(b => b.rating).map(b => b.rating!);
    const avg     = ratings.length ? (ratings.reduce((a, b) => a + b, 0) / ratings.length).toFixed(1) : null;
    const thisYear = new Date().getFullYear();
    const luThisYear = lu.filter(b => new Date(b.updated_at).getFullYear() === thisYear).length;
    const authorCount: Record<string, number> = {};
    books.forEach(b => b.authors.forEach(a => { authorCount[a] = (authorCount[a] ?? 0) + 1; }));
    const topAuthors = Object.entries(authorCount).sort((a, b) => b[1] - a[1]).slice(0, 5);
    return {
      total: books.length,
      lu: lu.length,
      en_cours: books.filter(b => b.status === "en_cours").length,
      a_lire: books.filter(b => b.status === "a_lire").length,
      livres: books.filter(b => b.book_type === "livre").length,
      bds: books.filter(b => b.book_type === "bd").length,
      mangas: books.filter(b => b.book_type === "manga").length,
      pages, avg, luThisYear, topAuthors,
    };
  }, [books]);

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

  const KPI_ITEMS = [
    { icon: BookOpen,   label: "Lus au total",  value: stats.lu,                                        sub: `sur ${stats.total} ouvrages`, color: "var(--accent)" },
    { icon: TrendingUp, label: "Cette année",   value: stats.luThisYear,                                sub: "livres terminés",             color: "#22C55E"       },
    { icon: FileText,   label: "Pages lues",    value: stats.pages > 0 ? stats.pages.toLocaleString("fr") : "—", sub: "livres terminés",    color: "#FB923C"       },
    { icon: Star,       label: "Note moyenne",  value: stats.avg ?? "—",                                sub: "sur 5 étoiles",               color: "#FBBF24"       },
  ];

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-12 pb-4">
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Vos stats</p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Tableau de bord</h1>
      </div>

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

      <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Avancement</h3>
        <div className="flex gap-3">
          {[
            { label: "Lus",      n: stats.lu,       emoji: "✅", bg: "var(--have-bg)", color: "var(--have-t)" },
            { label: "En cours", n: stats.en_cours,  emoji: "📖", bg: "#FEF9C3",        color: "#A16207"       },
            { label: "À lire",   n: stats.a_lire,    emoji: "📌", bg: "var(--accent-l)", color: "var(--accent)" },
          ].map(({ label, n, emoji, bg, color }) => (
            <div key={label} className="flex-1 flex flex-col items-center p-3 rounded-xl" style={{ background: bg }}>
              <span className="text-xl">{emoji}</span>
              <span className="text-xl font-bold mt-1" style={{ color }}>{n}</span>
              <span className="text-xs mt-0.5" style={{ color, opacity: 0.8 }}>{label}</span>
            </div>
          ))}
        </div>
      </div>

      {stats.total > 0 && (
        <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Répartition par type</h3>
          {[
            { label: "📖 Livres", value: stats.livres, color: "var(--accent)" },
            { label: "🎨 BD",     value: stats.bds,    color: "#FB923C"       },
            { label: "⛩️ Manga",  value: stats.mangas, color: "#22C55E"       },
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

      {stats.topAuthors.length > 0 && (
        <div className="mx-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Auteurs favoris</h3>
          {stats.topAuthors.map(([name, count], i) => (
            <div key={name} className="flex items-center gap-3 py-2">
              <span className="font-bold text-sm w-4 text-center" style={{ color: i === 0 ? "var(--accent)" : "var(--txt3)" }}>{i + 1}</span>
              <span className="flex-1 text-sm" style={{ color: "var(--txt2)" }}>{name}</span>
              <span className="text-xs font-semibold px-2 py-0.5 rounded-full" style={{ background: "var(--accent-l)", color: "var(--accent)" }}>
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
git commit -m "perf: shared DataContext, sessionStorage cache, parallel ISBN lookup"
git push
echo "🎉 Déployé !"
