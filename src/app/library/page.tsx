"use client";
import { useState, useMemo } from "react";
import { Book, ReadStatus, BookType } from "@/types";
import BookCard from "@/components/book/BookCard";
import BookDetail from "@/components/book/BookDetail";
import BottomNav from "@/components/layout/BottomNav";
import { Search, SlidersHorizontal, LayoutGrid, List } from "lucide-react";

const MOCK_BOOKS: Book[] = [
  { id:"b1",isbn:"9782070360024",title:"Le Seigneur des Anneaux",authors:["J.R.R. Tolkien"],cover_url:"https://covers.openlibrary.org/b/isbn/9782070360024-M.jpg",publisher:"Gallimard",published_year:1954,page_count:1200,book_type:"livre",status:"lu",rating:5,added_by:"user1",added_at:"2025-01-10T10:00:00Z",updated_at:"2025-01-10T10:00:00Z",library_id:"lib1"},
  { id:"b2",isbn:"9782205055375",title:"Astérix le Gaulois",authors:["René Goscinny","Albert Uderzo"],cover_url:"https://covers.openlibrary.org/b/isbn/9782205055375-M.jpg",publisher:"Hachette",published_year:1961,page_count:48,book_type:"bd",status:"lu",rating:4,series_name:"Astérix",series_index:1,added_by:"user1",added_at:"2025-02-01T10:00:00Z",updated_at:"2025-02-01T10:00:00Z",library_id:"lib1"},
  { id:"b3",isbn:"9782012101562",title:"Harry Potter à l'école des sorciers",authors:["J.K. Rowling"],cover_url:"https://covers.openlibrary.org/b/isbn/9782012101562-M.jpg",publisher:"Gallimard Jeunesse",published_year:1998,page_count:320,book_type:"livre",status:"en_cours",rating:4,series_name:"Harry Potter",series_index:1,added_by:"user1",added_at:"2026-03-15T10:00:00Z",updated_at:"2026-03-15T10:00:00Z",library_id:"lib1"},
  { id:"b4",isbn:"9782344009888",title:"Naruto, tome 1",authors:["Masashi Kishimoto"],cover_url:"https://covers.openlibrary.org/b/isbn/9782344009888-M.jpg",publisher:"Kana",published_year:1999,page_count:192,book_type:"manga",status:"a_lire",series_name:"Naruto",series_index:1,added_by:"user1",added_at:"2026-04-20T10:00:00Z",updated_at:"2026-04-20T10:00:00Z",library_id:"lib1"},
  { id:"b5",isbn:"9782070628070",title:"L'Étranger",authors:["Albert Camus"],cover_url:"https://covers.openlibrary.org/b/isbn/9782070628070-M.jpg",publisher:"Gallimard",published_year:1942,page_count:186,book_type:"livre",status:"lu",rating:5,added_by:"user1",added_at:"2026-05-05T10:00:00Z",updated_at:"2026-05-05T10:00:00Z",library_id:"lib1"},
  { id:"b6",isbn:"9782070413119",title:"Le Petit Prince",authors:["Antoine de Saint-Exupéry"],cover_url:"https://covers.openlibrary.org/b/isbn/9782070413119-M.jpg",publisher:"Gallimard",published_year:1943,page_count:96,book_type:"livre",status:"lu",rating:5,added_by:"user1",added_at:"2026-05-10T10:00:00Z",updated_at:"2026-05-10T10:00:00Z",library_id:"lib1"},
  { id:"b7",isbn:"9782290349229",title:"Dune",authors:["Frank Herbert"],cover_url:"https://covers.openlibrary.org/b/isbn/9782290349229-M.jpg",publisher:"Pocket",published_year:1965,page_count:896,book_type:"livre",status:"a_lire",added_by:"user1",added_at:"2026-05-20T10:00:00Z",updated_at:"2026-05-20T10:00:00Z",library_id:"lib1"},
  { id:"b8",title:"1984",authors:["George Orwell"],book_type:"livre",status:"a_lire",added_by:"user1",added_at:"2026-06-01T10:00:00Z",updated_at:"2026-06-01T10:00:00Z",library_id:"lib1"},
];

type FilterStatus = ReadStatus | "all";
type FilterType = BookType | "all";

export default function LibraryPage() {
  const [books, setBooks] = useState<Book[]>(MOCK_BOOKS);
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState<FilterStatus>("all");
  const [filterType, setFilterType] = useState<FilterType>("all");
  const [layout, setLayout] = useState<"grid" | "list">("grid");
  const [selected, setSelected] = useState<Book | null>(null);
  const [showFilters, setShowFilters] = useState(false);

  const stats = useMemo(() => ({
    total: books.length,
    lu: books.filter(b => b.status === "lu").length,
    en_cours: books.filter(b => b.status === "en_cours").length,
    a_lire: books.filter(b => b.status === "a_lire").length,
  }), [books]);

  const filtered = useMemo(() => books.filter(b => {
    const s = !search || b.title.toLowerCase().includes(search.toLowerCase()) || b.authors.some(a => a.toLowerCase().includes(search.toLowerCase()));
    const st = filterStatus === "all" || b.status === filterStatus;
    const ty = filterType === "all" || b.book_type === filterType;
    return s && st && ty;
  }), [books, search, filterStatus, filterType]);

  const handleUpdate = (id: string, updates: Partial<Book>) => {
    setBooks(prev => prev.map(b => b.id === id ? { ...b, ...updates, updated_at: new Date().toISOString() } : b));
    setSelected(prev => prev?.id === id ? { ...prev, ...updates } : prev);
  };
  const handleDelete = (id: string) => { setBooks(prev => prev.filter(b => b.id !== id)); setSelected(null); };

  return (
    <div className="flex flex-col min-h-screen pb-20" style={{ background: "var(--bg)" }}>
      {/* Sticky header */}
      <div className="sticky top-0 z-30 px-4 pt-10 pb-3" style={{ background: "var(--bg)" }}>
        {/* Hero band */}
        <div className="rounded-2xl p-4 mb-3 flex items-center justify-between overflow-hidden relative"
          style={{ background: "var(--accent)" }}>
          <div style={{ position: "absolute", right: -20, top: -20, width: 100, height: 100, borderRadius: "50%", background: "rgba(255,255,255,0.07)" }} />
          <div>
            <p className="text-sm font-bold text-white">Bienvenue, Garance 👋</p>
            <p className="text-xs mt-0.5" style={{ color: "rgba(255,255,255,0.65)" }}>2 tomes manquants dans vos collections</p>
            <div className="flex gap-4 mt-2">
              {[{ n: stats.lu, l: "Lus" }, { n: stats.en_cours, l: "En cours" }, { n: stats.a_lire, l: "À lire" }].map(({ n, l }) => (
                <div key={l}>
                  <p className="text-lg font-bold text-white leading-none">{n}</p>
                  <p className="text-xs" style={{ color: "rgba(255,255,255,0.6)" }}>{l}</p>
                </div>
              ))}
            </div>
          </div>
          <div className="w-10 h-10 rounded-xl flex items-center justify-center font-bold text-lg flex-shrink-0"
            style={{ background: "rgba(255,255,255,0.2)", color: "#fff" }}>G</div>
        </div>

        {/* Search + controls */}
        <div className="flex items-center gap-2 mb-2">
          <div className="flex-1 flex items-center gap-2 px-3 py-2.5 rounded-xl"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <Search className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
            <input type="text" value={search} onChange={e => setSearch(e.target.value)}
              placeholder="Titre, auteur..."
              className="flex-1 text-sm outline-none bg-transparent"
              style={{ color: "var(--txt1)" }} />
          </div>
          <button onClick={() => setLayout(l => l === "grid" ? "list" : "grid")}
            className="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            {layout === "grid" ? <List className="w-4 h-4" style={{ color: "var(--txt2)" }} /> : <LayoutGrid className="w-4 h-4" style={{ color: "var(--txt2)" }} />}
          </button>
          <button onClick={() => setShowFilters(f => !f)}
            className="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0"
            style={{ background: showFilters ? "var(--accent)" : "var(--surface)", border: `1px solid ${showFilters ? "var(--accent)" : "var(--border)"}` }}>
            <SlidersHorizontal className="w-4 h-4" style={{ color: showFilters ? "#fff" : "var(--txt2)" }} />
          </button>
        </div>

        {/* Filters */}
        {showFilters && (
          <div className="flex flex-col gap-2 mb-2">
            <div className="flex gap-2 overflow-x-auto pb-1">
              {(["all","lu","en_cours","a_lire"] as FilterStatus[]).map(s => (
                <button key={s} onClick={() => setFilterStatus(s)}
                  className="flex-shrink-0 px-3 py-1.5 rounded-full text-xs font-semibold"
                  style={{ background: filterStatus === s ? "var(--accent)" : "var(--surface)", color: filterStatus === s ? "#fff" : "var(--txt2)", border: `1px solid ${filterStatus === s ? "var(--accent)" : "var(--border)"}` }}>
                  {s === "all" ? "Tous statuts" : s === "lu" ? "✅ Lu" : s === "en_cours" ? "📖 En cours" : "📌 À lire"}
                </button>
              ))}
            </div>
            <div className="flex gap-2 overflow-x-auto pb-1">
              {(["all","livre","bd","manga"] as FilterType[]).map(t => (
                <button key={t} onClick={() => setFilterType(t)}
                  className="flex-shrink-0 px-3 py-1.5 rounded-full text-xs font-semibold"
                  style={{ background: filterType === t ? "var(--accent)" : "var(--surface)", color: filterType === t ? "#fff" : "var(--txt2)", border: `1px solid ${filterType === t ? "var(--accent)" : "var(--border)"}` }}>
                  {t === "all" ? "Tous types" : t === "livre" ? "📖 Livres" : t === "bd" ? "🎨 BD" : "⛩️ Mangas"}
                </button>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Section label */}
      <div className="flex items-center justify-between px-4 mb-3">
        <span className="text-sm font-bold" style={{ color: "var(--txt1)" }}>
          {filtered.length} {filtered.length > 1 ? "ouvrages" : "ouvrage"}
          {search || filterStatus !== "all" || filterType !== "all" ? " (filtrés)" : ""}
        </span>
        <span className="text-xs font-semibold" style={{ color: "var(--accent)" }}>Voir tout</span>
      </div>

      {/* Grid / list */}
      <div className="px-4">
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center py-16 gap-3">
            <p className="font-semibold" style={{ color: "var(--txt1)" }}>Aucun résultat</p>
            <p className="text-sm" style={{ color: "var(--txt3)" }}>Essayez un autre filtre ou terme</p>
          </div>
        ) : layout === "grid" ? (
          <div className="grid grid-cols-4 gap-3">
            {filtered.map(b => <BookCard key={b.id} book={b} onClick={() => setSelected(b)} />)}
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {filtered.map(b => (
              <button key={b.id} onClick={() => setSelected(b)}
                className="flex items-center gap-3 p-3 rounded-xl text-left active:scale-[0.98]"
                style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
                <div className="w-10 h-14 rounded-lg overflow-hidden flex-shrink-0" style={{ background: "var(--placeholder)" }}>
                  {b.cover_url && <img src={b.cover_url} alt="" className="w-full h-full object-cover" />}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-sm truncate" style={{ color: "var(--txt1)" }}>{b.title}</p>
                  <p className="text-xs mt-0.5" style={{ color: "var(--txt2)" }}>{b.authors[0]}</p>
                  {b.series_name && <p className="text-xs mt-0.5" style={{ color: "var(--accent)" }}>{b.series_name} #{b.series_index}</p>}
                </div>
                <span className="text-xs px-2 py-1 rounded-full font-semibold flex-shrink-0"
                  style={{ background: b.status === "lu" ? "var(--have-bg)" : b.status === "en_cours" ? "#FEF9C3" : "var(--accent-l)", color: b.status === "lu" ? "var(--have-t)" : b.status === "en_cours" ? "#A16207" : "var(--accent)" }}>
                  {b.status === "lu" ? "Lu" : b.status === "en_cours" ? "En cours" : "À lire"}
                </span>
              </button>
            ))}
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
