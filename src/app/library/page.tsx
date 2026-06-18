"use client";
import { useState, useMemo } from "react";
import { useSession } from "next-auth/react";
import { Book, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { useData } from "@/contexts/DataContext";
import { useFirstUse } from "@/hooks/useFirstUse";
import BookCard from "@/components/book/BookCard";
import BookDetail from "@/components/book/BookDetail";
import Onboarding from "@/components/onboarding/Onboarding";
import BottomNav from "@/components/layout/BottomNav";
import { Search, SlidersHorizontal, LayoutGrid, List, RefreshCw, Image as ImageIcon, FileText } from "lucide-react";

type Layout       = "grid" | "list";
type FilterType   = BookType | "all";
type FilterStatus = ReadStatus | "all";

export default function LibraryPage() {
  const { data: session } = useSession();
  const { books, collections, loading, library_id, setBooks, refreshAll, refreshCollections } = useData();
  const isFirstUse = useFirstUse("folio_onboarding_seen");
  const [showOnboarding, setShowOnboarding] = useState<boolean | null>(null);
  const [search,         setSearch]         = useState("");
  const [filterStatus,   setFilterStatus]   = useState<FilterStatus>("all");
  const [filterType,     setFilterType]     = useState<FilterType>("all");
  const [layout,         setLayout]         = useState<Layout>("grid");
  const [selected,       setSelected]       = useState<Book | null>(null);
  const [showFilters,    setShowFilters]    = useState(false);
  const [refreshingCovers, setRefreshingCovers] = useState(false);
  const [refreshingDescs, setRefreshingDescs] = useState(false);
  const [refreshing,       setRefreshing]       = useState(false);

  const handleRefresh = async () => {
    setRefreshing(true);
    await refreshAll();
    setTimeout(() => setRefreshing(false), 800);
  };

  const refreshDescriptions = async () => {
    if (!library_id || refreshingDescs) return;
    setRefreshingDescs(true);
    try {
      await fetch("/api/books/refresh-descriptions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ library_id }),
      });
      await refreshAll();
    } finally {
      setRefreshingDescs(false);
    }
  };

  const refreshCovers = async () => {
    if (!library_id || refreshingCovers) return;
    setRefreshingCovers(true);
    try {
      await fetch("/api/books/refresh-covers", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ library_id }),
      });
      await refreshAll();
    } finally {
      setRefreshingCovers(false);
    }
  };

  // Show onboarding on first visit

  // ── Computed ────────────────────────────────────────────────────────────────
  const stats = useMemo(() => ({
    lu:       books.filter(b => b.status === "lu").length,
    en_cours: books.filter(b => b.status === "en_cours").length,
    a_lire:   books.filter(b => b.status === "a_lire").length,
  }), [books]);

  const filtered = useMemo(() => {
    const statusOrder: Record<string, number> = { en_cours: 0, a_lire: 1, lu: 2 };
    return books
      .filter(b => {
        const q = search.toLowerCase();
        return (
          (!q || b.title.toLowerCase().includes(q) || b.authors.some(a => a.toLowerCase().includes(q))) &&
          (filterStatus === "all" || b.status === filterStatus) &&
          (filterType   === "all" || b.book_type === filterType)
        );
      })
      .sort((a, b) => (statusOrder[a.status] ?? 9) - (statusOrder[b.status] ?? 9));
  }, [books, search, filterStatus, filterType]);

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
      body: JSON.stringify({ id, library_id }),
    });
    setBooks(prev => prev.filter(b => b.id !== id));
    setSelected(null);
    refreshCollections();
  };

  const userName = session?.user?.name?.split(" ")[0] ?? "toi";

  // ── Early returns ──────────────────────────────────────────────────────────

  if (isFirstUse === true && showOnboarding === null) {
    return <Onboarding onComplete={() => setShowOnboarding(false)} />;
  }

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center" style={{ background: "var(--bg)" }}>
      <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
      <BottomNav />
    </div>
  );

  return (
    <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>

      {/* Sticky header */}
      <div className="sticky top-0 z-30 px-3 pt-10 pb-2" style={{ background: "var(--bg)" }}>

        {/* Hero banner */}
        <div className="rounded-2xl p-3 mb-3 flex items-center justify-between relative overflow-hidden"
          style={{ background: "var(--accent)" }}>
          <div className="absolute right-[-20px] top-[-20px] w-24 h-24 rounded-full"
            style={{ background: "rgba(255,255,255,0.07)" }} />
          <div>
            <p className="font-bold text-white" style={{ fontSize: 15 }}>Bienvenue {userName} 👋</p>
            <div className="flex gap-4 mt-1.5">
              {(["lu","en_cours","a_lire"] as ReadStatus[]).map(s => (
                <div key={s}>
                  <p className="font-bold text-white leading-none" style={{ fontSize: 20 }}>{stats[s]}</p>
                  <p style={{ color: "rgba(255,255,255,0.6)", fontSize: 11, marginTop: 1 }}>
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

        {/* Search + controls — responsive */}
        <div className="flex gap-2 mb-3">
          <div className="flex-1 flex items-center gap-2 px-3 py-2.5 rounded-2xl"
            style={{ background: "var(--surface)", border: "1px solid var(--border)", minWidth: 0 }}>
            <Search className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
            <input
              type="text" value={search} onChange={e => setSearch(e.target.value)}
              placeholder="Titre, auteur..."
              className="flex-1 outline-none bg-transparent min-w-0"
              style={{ color: "var(--txt1)", fontSize: 14 }}
            />
          </div>
          {/* Refresh */}
          <button onClick={handleRefresh} disabled={refreshing}
            className="w-10 h-10 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <RefreshCw className="w-4 h-4"
              style={{ color: refreshing ? "var(--accent)" : "var(--txt2)", animation: refreshing ? "spin 0.8s linear infinite" : "none" }} />
          </button>
          {/* Cover refresh — only when needed */}
          {books.some(b => !b.cover_url) && (
            <button onClick={refreshCovers} disabled={refreshingCovers}
              className="w-10 h-10 rounded-2xl flex items-center justify-center flex-shrink-0"
              style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
              {refreshingCovers
                ? <div className="w-4 h-4 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
                : <ImageIcon className="w-4 h-4" style={{ color: "var(--accent)" }} />}
            </button>
          )}
          {/* Description refresh — only when needed */}
          {books.some(b => !b.description) && (
            <button onClick={refreshDescriptions} disabled={refreshingDescs}
              className="w-10 h-10 rounded-2xl flex items-center justify-center flex-shrink-0"
              style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
              {refreshingDescs
                ? <div className="w-4 h-4 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
                : <FileText className="w-4 h-4" style={{ color: "var(--accent)" }} />}
            </button>
          )}
          {/* Layout toggle */}
          <button onClick={() => setLayout(l => l === "grid" ? "list" : "grid")}
            className="w-10 h-10 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            {layout === "grid"
              ? <List className="w-4 h-4" style={{ color: "var(--txt2)" }} />
              : <LayoutGrid className="w-4 h-4" style={{ color: "var(--txt2)" }} />}
          </button>
          {/* Filters */}
          <button onClick={() => setShowFilters(f => !f)}
            className="w-10 h-10 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{ background: showFilters ? "var(--accent)" : "var(--surface)", border: `1px solid ${showFilters ? "var(--accent)" : "var(--border)"}` }}>
            <SlidersHorizontal className="w-4 h-4" style={{ color: showFilters ? "#fff" : "var(--txt2)" }} />
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
      <div className="flex justify-between items-center px-3 mb-2">
        <span className="font-bold" style={{ fontSize: 15, color: "var(--txt1)" }}>
          {loading ? "Chargement…" : `${filtered.length} ouvrage${filtered.length > 1 ? "s" : ""}`}
        </span>
      </div>

      {/* Book list */}
      <div className="px-3">
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
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10 }}>
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
