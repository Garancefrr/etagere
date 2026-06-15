"use client";
import { useState, useMemo } from "react";
import { Book, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG, LIBRARY_ID } from "@/lib/constants";
import BookCard from "@/components/book/BookCard";
import BookDetail from "@/components/book/BookDetail";
import BottomNav from "@/components/layout/BottomNav";
import { Search, SlidersHorizontal, LayoutGrid, List } from "lucide-react";

// ─── Demo data (replace with Supabase query) ─────────────────────────────────
const DEMO_BOOKS: Book[] = [
  { id:"b1", isbn:"9782070360024", title:"Le Seigneur des Anneaux", authors:["J.R.R. Tolkien"],  cover_url:"https://covers.openlibrary.org/b/isbn/9782070360024-M.jpg", book_type:"livre", status:"lu",       rating:5, library_id:LIBRARY_ID, added_by:"u1", added_at:"2025-01-10T00:00:00Z", updated_at:"2025-01-10T00:00:00Z" },
  { id:"b2", isbn:"9782205055375", title:"Astérix le Gaulois",      authors:["Goscinny","Uderzo"], cover_url:"https://covers.openlibrary.org/b/isbn/9782205055375-M.jpg", book_type:"bd",    status:"lu",       rating:4, library_id:LIBRARY_ID, added_by:"u1", added_at:"2025-02-01T00:00:00Z", updated_at:"2025-02-01T00:00:00Z", series_name:"Astérix", series_index:1 },
  { id:"b3", isbn:"9782012101562", title:"Harry Potter T.1",        authors:["J.K. Rowling"],     cover_url:"https://covers.openlibrary.org/b/isbn/9782012101562-M.jpg", book_type:"livre", status:"en_cours", rating:4, library_id:LIBRARY_ID, added_by:"u1", added_at:"2026-03-15T00:00:00Z", updated_at:"2026-03-15T00:00:00Z", series_name:"Harry Potter", series_index:1 },
  { id:"b4", isbn:"9782344009888", title:"Naruto, tome 1",          authors:["Kishimoto"],        cover_url:"https://covers.openlibrary.org/b/isbn/9782344009888-M.jpg", book_type:"manga", status:"a_lire",             library_id:LIBRARY_ID, added_by:"u1", added_at:"2026-04-20T00:00:00Z", updated_at:"2026-04-20T00:00:00Z", series_name:"Naruto", series_index:1 },
  { id:"b5", isbn:"9782070628070", title:"L'Étranger",              authors:["Albert Camus"],     cover_url:"https://covers.openlibrary.org/b/isbn/9782070628070-M.jpg", book_type:"livre", status:"lu",       rating:5, library_id:LIBRARY_ID, added_by:"u1", added_at:"2026-05-05T00:00:00Z", updated_at:"2026-05-05T00:00:00Z" },
  { id:"b6", isbn:"9782070413119", title:"Le Petit Prince",         authors:["Saint-Exupéry"],    cover_url:"https://covers.openlibrary.org/b/isbn/9782070413119-M.jpg", book_type:"livre", status:"lu",       rating:5, library_id:LIBRARY_ID, added_by:"u1", added_at:"2026-05-10T00:00:00Z", updated_at:"2026-05-10T00:00:00Z" },
  { id:"b7", isbn:"9782290349229", title:"Dune",                    authors:["Frank Herbert"],    cover_url:"https://covers.openlibrary.org/b/isbn/9782290349229-M.jpg", book_type:"livre", status:"a_lire",             library_id:LIBRARY_ID, added_by:"u1", added_at:"2026-05-20T00:00:00Z", updated_at:"2026-05-20T00:00:00Z" },
];

type Layout      = "grid" | "list";
type FilterType  = BookType | "all";
type FilterStatus = ReadStatus | "all";

export default function LibraryPage() {
  const [books,        setBooks]        = useState<Book[]>(DEMO_BOOKS);
  const [search,       setSearch]       = useState("");
  const [filterStatus, setFilterStatus] = useState<FilterStatus>("all");
  const [filterType,   setFilterType]   = useState<FilterType>("all");
  const [layout,       setLayout]       = useState<Layout>("grid");
  const [selected,     setSelected]     = useState<Book | null>(null);
  const [showFilters,  setShowFilters]  = useState(false);

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

  const handleUpdate = (id: string, updates: Partial<Book>) => {
    setBooks(prev => prev.map(b => b.id === id ? { ...b, ...updates, updated_at: new Date().toISOString() } : b));
    setSelected(prev => prev?.id === id ? { ...prev, ...updates } as Book : prev);
  };

  const handleDelete = (id: string) => {
    setBooks(prev => prev.filter(b => b.id !== id));
    setSelected(null);
  };

  return (
    <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>

      {/* Sticky header */}
      <div className="sticky top-0 z-30 px-4 pt-12 pb-3" style={{ background: "var(--bg)" }}>

        {/* Hero */}
        <div className="rounded-2xl p-4 mb-4 flex items-center justify-between relative overflow-hidden"
          style={{ background: "var(--accent)" }}>
          <div className="absolute right-[-20px] top-[-20px] w-28 h-28 rounded-full"
            style={{ background: "rgba(255,255,255,0.07)" }} />
          <div>
            <p className="font-bold text-white" style={{ fontSize: 16 }}>Bienvenue 👋</p>
            <div className="flex gap-5 mt-2">
              {(["lu","en_cours","a_lire"] as ReadStatus[]).map(s => (
                <div key={s}>
                  <p className="font-bold text-white leading-none" style={{ fontSize: 22 }}>{stats[s]}</p>
                  <p style={{ color: "rgba(255,255,255,0.6)", fontSize: 12, marginTop: 2 }}>{STATUS_CONFIG[s].label}</p>
                </div>
              ))}
            </div>
          </div>
          <div className="w-12 h-12 rounded-xl flex items-center justify-center font-bold flex-shrink-0"
            style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>G</div>
        </div>

        {/* Search row */}
        <div className="flex gap-2 mb-3">
          <div className="flex-1 flex items-center gap-2 px-4 py-3 rounded-2xl"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <Search className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
            <input
              type="text"
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Titre, auteur..."
              className="flex-1 outline-none bg-transparent"
              style={{ color: "var(--txt1)", fontSize: 15 }}
            />
          </div>
          <button onClick={() => setLayout(l => l === "grid" ? "list" : "grid")}
            className="w-11 h-11 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            {layout === "grid"
              ? <List className="w-5 h-5" style={{ color: "var(--txt2)" }} />
              : <LayoutGrid className="w-5 h-5" style={{ color: "var(--txt2)" }} />}
          </button>
          <button onClick={() => setShowFilters(f => !f)}
            className="w-11 h-11 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{ background: showFilters ? "var(--accent)" : "var(--surface)", border: `1px solid ${showFilters ? "var(--accent)" : "var(--border)"}` }}>
            <SlidersHorizontal className="w-5 h-5" style={{ color: showFilters ? "#fff" : "var(--txt2)" }} />
          </button>
        </div>

        {/* Filters */}
        {showFilters && (
          <div className="space-y-2 mb-2">
            <FilterRow
              options={[{ v: "all", l: "Tous" }, ...Object.entries(STATUS_CONFIG).map(([v, c]) => ({ v, l: `${c.emoji} ${c.label}` }))]}
              value={filterStatus}
              onChange={(v) => setFilterStatus(v as FilterStatus)}
            />
            <FilterRow
              options={[{ v: "all", l: "Tous types" }, ...Object.entries(TYPE_CONFIG).map(([v, c]) => ({ v, l: `${c.emoji} ${c.label}` }))]}
              value={filterType}
              onChange={(v) => setFilterType(v as FilterType)}
            />
          </div>
        )}
      </div>

      {/* Count */}
      <div className="flex justify-between px-4 mb-3">
        <span className="font-bold" style={{ fontSize: 15, color: "var(--txt1)" }}>
          {filtered.length} ouvrage{filtered.length > 1 ? "s" : ""}
        </span>
        <span style={{ fontSize: 13, color: "var(--accent)", fontWeight: 600 }}>Voir tout</span>
      </div>

      {/* Content */}
      <div className="px-4">
        {filtered.length === 0 ? (
          <Empty />
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

      {/* Detail modal */}
      {selected && (
        <BookDetail
          book={selected}
          onClose={() => setSelected(null)}
          onUpdate={handleUpdate}
          onDelete={handleDelete}
        />
      )}

      <BottomNav />
    </div>
  );
}

// ── Internal helpers ──────────────────────────────────────────────────────────

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
      <span className="px-3 py-1.5 rounded-full font-semibold flex-shrink-0"
        style={{ fontSize: 12, background: bg, color }}>{label}</span>
    </button>
  );
}

function Empty() {
  return (
    <div className="flex flex-col items-center py-20 gap-3">
      <p className="font-semibold" style={{ fontSize: 17, color: "var(--txt1)" }}>Aucun résultat</p>
      <p style={{ fontSize: 14, color: "var(--txt3)" }}>Essayez un autre filtre</p>
    </div>
  );
}
