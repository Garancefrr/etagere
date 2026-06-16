"use client";
import { useState, useMemo, useEffect, useCallback } from "react";
import { useSession } from "next-auth/react";
import { Book, ReadStatus, BookType, Collection } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { useLibrary } from "@/hooks/useLibrary";
import BookCard from "@/components/book/BookCard";
import BookDetail from "@/components/book/BookDetail";
import BottomNav from "@/components/layout/BottomNav";
import { Search, SlidersHorizontal, LayoutGrid, List, RefreshCw } from "lucide-react";

type Layout       = "grid" | "list";
type FilterType   = BookType | "all";
type FilterStatus = ReadStatus | "all";

export default function LibraryPage() {
  const { data: session }                   = useSession();
  const { library_id, loading: libLoading } = useLibrary();
  const [books,        setBooks]            = useState<Book[]>([]);
  const [booksLoading, setBooksLoading]     = useState(false);
  const [search,       setSearch]           = useState("");
  const [filterStatus, setFilterStatus]     = useState<FilterStatus>("all");
  const [filterType,   setFilterType]       = useState<FilterType>("all");
  const [layout,       setLayout]           = useState<Layout>("grid");
  const [selected,     setSelected]         = useState<Book | null>(null);
  const [showFilters,  setShowFilters]      = useState(false);
  const [collections,  setCollections]      = useState<Collection[]>([]);

  // ── Fetch from Supabase ─────────────────────────────────────────────────────
  const fetchBooks = useCallback(async (lid: string) => {
    setBooksLoading(true);
    try {
      const res = await fetch(`/api/books?library_id=${lid}`);
      if (res.ok) setBooks(await res.json());
    } finally {
      setBooksLoading(false);
    }
  }, []);

  // Load on mount
  useEffect(() => {
    if (library_id) {
      fetchBooks(library_id);
      fetch(`/api/collections?library_id=${library_id}`)
        .then(r => r.json())
        .then(d => Array.isArray(d) ? setCollections(d) : [])
        .catch(console.error);
    }
  }, [library_id, fetchBooks]);

  // Reload when tab gets focus (e.g. after scanning)
  useEffect(() => {
    if (!library_id) return;
    const onFocus = () => fetchBooks(library_id);
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") fetchBooks(library_id);
    });
    return () => {
      window.removeEventListener("focus", onFocus);
    };
  }, [library_id, fetchBooks]);

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
      body: JSON.stringify({ id, ...updates }),
    });
    setBooks(prev => prev.map(b => b.id === id ? { ...b, ...updates } : b));
    setSelected(prev => prev?.id === id ? { ...prev, ...updates } as Book : prev);
  };

  const handleDelete = async (id: string) => {
    await fetch("/api/books", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    });
    setBooks(prev => prev.filter(b => b.id !== id));
    setSelected(null);
  };

  const userName = session?.user?.name?.split(" ")[0] ?? "toi";
  const loading  = libLoading || booksLoading;

  // ── Render ──────────────────────────────────────────────────────────────────
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
            onClick={() => library_id && fetchBooks(library_id)}
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
