#!/bin/bash
set -e
echo "⏳ Fix double chargement — un seul spinner..."
cd "$(git rev-parse --show-toplevel)"
cat > "src/app/library/page.tsx" << 'FILEOF'
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
  const [books,          setBooks]          = useState<Book[]>([]);
  const [initialLoaded,  setInitialLoaded]  = useState(false);
  const [search,         setSearch]         = useState("");
  const [filterStatus,   setFilterStatus]   = useState<FilterStatus>("all");
  const [filterType,     setFilterType]     = useState<FilterType>("all");
  const [layout,         setLayout]         = useState<Layout>("grid");
  const [selected,       setSelected]       = useState<Book | null>(null);
  const [showFilters,    setShowFilters]    = useState(false);
  const [collections,    setCollections]    = useState<Collection[]>([]);

  // ── Fetch from Supabase ─────────────────────────────────────────────────────
  const fetchBooks = useCallback(async (lid: string) => {
    try {
      const res = await fetch(`/api/books?library_id=${lid}`);
      if (res.ok) setBooks(await res.json());
    } finally {
      setInitialLoaded(true);
    }
  }, []);

  // Load on mount — single fetch after library_id resolves
  useEffect(() => {
    if (!library_id) return;
    fetchBooks(library_id);
    fetch(`/api/collections?library_id=${library_id}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setCollections(d) : [])
      .catch(console.error);
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
      body: JSON.stringify({ id, library_id, ...updates }),
    });
    setBooks(prev => prev.map(b => b.id === id ? { ...b, ...updates } : b));
    setSelected(prev => prev?.id === id ? { ...prev, ...updates } as Book : prev);
    // Refresh collections if series info was updated
    if (updates.series_name || updates.series_index) {
      if (library_id) {
        fetch(`/api/collections?library_id=${library_id}`)
          .then(r => r.json())
          .then(d => Array.isArray(d) ? setCollections(d) : [])
          .catch(console.error);
      }
    }
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
  const loading  = libLoading || !initialLoaded;

  // ── Render ──────────────────────────────────────────────────────────────────

  // Show spinner until first fetch is complete
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
FILEOF
cat > "src/app/collections/page.tsx" << 'FILEOF'
"use client";
import { useState, useEffect, useRef } from "react";
import { Collection, BookType } from "@/types";
import { useLibrary } from "@/hooks/useLibrary";
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
  const { library_id, profile_id, loading: libLoading } = useLibrary();
  const [collections,     setCollections]    = useState<Collection[]>([]);
  const [initialLoaded,    setInitialLoaded]  = useState(false);
  const [search,          setSearch]         = useState("");
  const [filter,          setFilter]         = useState<Filter>("all");
  const [showCreate,      setShowCreate]     = useState(false);
  const [shareCol,        setShareCol]       = useState<Collection | null>(null);
  const [editCol,         setEditCol]        = useState<Collection | null>(null);
  const [deleteId,        setDeleteId]       = useState<string | null>(null);

  useEffect(() => {
    if (!library_id) return;
    fetch(`/api/collections?library_id=${library_id}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setCollections(d) : [])
      .catch(console.error)
      .finally(() => setInitialLoaded(true));
  }, [library_id]);

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
  const loading = libLoading || !initialLoaded;

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
git add -A
git commit -m "fix: single loading spinner, no flash of empty state"
git push
echo "🎉 Déployé !"
