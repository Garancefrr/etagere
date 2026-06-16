#!/bin/bash
set -e
echo "📷 Scanner vert + fix library..."
cd "$(git rev-parse --show-toplevel)"
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

interface Props {
  rapidMode: boolean;
  libraryId: string;
  userId: string;
  onSuccess: (result: ScanResult, status: ReadStatus, bookType: BookType) => void;
  onClose: () => void;
}

const CORNERS = [
  { top: -2,    left: -2,  borderTop:    "3px solid", borderLeft:   "3px solid", borderRadius: "6px 0 0 0" },
  { top: -2,    right: -2, borderTop:    "3px solid", borderRight:  "3px solid", borderRadius: "0 6px 0 0" },
  { bottom: -2, left: -2,  borderBottom: "3px solid", borderLeft:   "3px solid", borderRadius: "0 0 0 6px" },
  { bottom: -2, right: -2, borderBottom: "3px solid", borderRight:  "3px solid", borderRadius: "0 0 6px 0" },
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

  // Frame color: blue scanning, green success, red error
  const frameColor = phase === "success" ? "#22C55E"
    : (phase === "not_found" || phase === "error") ? "#EF4444"
    : "#5B7AFF";

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
          // Flash green for 800ms then reset
          setTimeout(() => {
            setPhase("scanning");
            setResult(null);
            setIsbn("");
            processingRef.current = false;
          }, 800);
        } else {
          setPhase("error");
          processingRef.current = false;
        }
      } else {
        setPhase("confirm");
        processingRef.current = false;
      }
    } catch {
      setPhase("error");
      processingRef.current = false;
    }
  }, [rapidMode, libraryId]); // eslint-disable-line react-hooks/exhaustive-deps

  const saveBook = async (r: ScanResult, s: ReadStatus, bt: BookType): Promise<boolean> => {
    try {
      const res = await fetch("/api/books/add", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          isbn:          r.book.isbn,
          title:         r.book.title,
          authors:       r.book.authors,
          cover_url:     r.book.cover_url,
          publisher:     r.book.publisher,
          published_year: r.book.published_year,
          page_count:    r.book.page_count,
          description:   r.book.description,
          book_type:     bt,
          status:        s,
          series_name:   r.book.series_name,
          series_index:  r.book.series_index,
          collection_id: r.collection?.id,
          library_id:    libraryId,
          added_by:      userId,
        }),
      });
      if (!res.ok) {
        const err = await res.json();
        console.error("Save book error:", err);
        return false;
      }
      onSuccess(r, s, bt);
      return true;
    } catch (e) {
      console.error("Save book exception:", e);
      return false;
    }
  };

  const reset = () => {
    setPhase("scanning");
    setResult(null);
    setIsbn("");
    processingRef.current = false;
  };

  const handleConfirm = async () => {
    if (!result) return;
    setPhase("loading");
    const ok = await saveBook(result, status, bookType);
    if (ok) {
      setPhase("success");
      setTimeout(() => {
        reset();
        onClose();
      }, 600);
    } else {
      setPhase("error");
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex flex-col overflow-hidden" style={{ background: "#060818" }}>

      {/* Top bar */}
      <div className="flex items-center justify-between px-5 pt-12 pb-2 flex-shrink-0">
        <button onClick={onClose} className="w-10 h-10 rounded-full flex items-center justify-center"
          style={{ background: "rgba(255,255,255,0.08)" }}>
          <X className="w-5 h-5 text-white" />
        </button>
        <span className="font-bold text-white" style={{ fontSize: 16 }}>
          {rapidMode ? "⚡ Mode rapide" : "Scanner"}
        </span>
        <button onClick={() => setShowManual(v => !v)}
          className="w-10 h-10 rounded-full flex items-center justify-center"
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

      {/* Camera */}
      <div className="flex-1 flex items-center justify-center relative min-h-0">
        <div className="relative">
          <video ref={videoRef}
            style={{ width: 300, height: 220, objectFit: "cover", borderRadius: 12, display: "block" }} />

          {/* Frame corners — color changes with phase */}
          <div className="absolute inset-0 pointer-events-none" style={{ transition: "all 0.3s" }}>
            {CORNERS.map((s, i) => (
              <div key={i} className="absolute" style={{
                width: 20, height: 20,
                ...s,
                borderTopColor:    s.borderTop    ? frameColor : undefined,
                borderBottomColor: s.borderBottom ? frameColor : undefined,
                borderLeftColor:   s.borderLeft   ? frameColor : undefined,
                borderRightColor:  s.borderRight  ? frameColor : undefined,
                transition: "border-color 0.3s",
              }} />
            ))}

            {/* Scan line — only when actively scanning */}
            {(phase === "scanning" || phase === "loading") && (
              <div className="scan-line absolute left-0 right-0"
                style={{ height: 2, background: `linear-gradient(90deg,transparent,${frameColor},transparent)` }} />
            )}

            {/* Success checkmark overlay */}
            {phase === "success" && (
              <div className="absolute inset-0 flex items-center justify-center rounded-xl"
                style={{ background: "rgba(34,197,94,0.2)" }}>
                <div className="w-14 h-14 rounded-full flex items-center justify-center"
                  style={{ background: "#22C55E" }}>
                  <Check className="w-8 h-8 text-white" />
                </div>
              </div>
            )}
          </div>

          {/* Loading spinner top-right */}
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
            placeholder="Saisir ISBN..."
            onKeyDown={e => { if (e.key === "Enter" && manual) { processingRef.current = true; lookup(manual); }}}
            className="flex-1 px-4 py-3 rounded-2xl outline-none"
            style={{ background: "rgba(255,255,255,0.08)", color: "white", border: "1px solid rgba(91,122,255,0.3)", fontSize: 15 }} />
          <button onClick={() => { if (manual) { processingRef.current = true; lookup(manual); }}}
            className="px-5 py-3 rounded-2xl font-bold"
            style={{ background: "var(--accent)", color: "#fff" }}>OK</button>
        </div>
      )}

      {/* Bottom panel */}
      <div className="flex-shrink-0 rounded-t-3xl p-4 flex flex-col gap-3"
        style={{ background: "var(--surface)", maxHeight: "45vh", overflow: "hidden" }}>

        {phase === "scanning" && (
          <p className="text-center py-2" style={{ fontSize: 14, color: "var(--txt2)" }}>
            Centrez le code-barres dans le cadre
          </p>
        )}

        {phase === "loading" && (
          <div className="flex items-center justify-center gap-3 py-2">
            <div className="w-5 h-5 rounded-full border-2 animate-spin flex-shrink-0"
              style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
            <p style={{ fontSize: 14, color: "var(--txt2)" }}>Recherche {isbn}…</p>
          </div>
        )}

        {phase === "success" && (
          <p className="text-center py-2 font-semibold" style={{ fontSize: 14, color: "#22C55E" }}>
            ✅ Ajouté !
          </p>
        )}

        {(phase === "not_found" || phase === "error") && (
          <div className="flex items-center justify-between gap-3 py-1">
            <p style={{ fontSize: 14, color: "var(--miss-t)" }}>
              {phase === "error" ? "Erreur lors de l'ajout" : `Introuvable — ${isbn}`}
            </p>
            <Button onClick={reset} size="sm" variant="secondary">
              <RefreshCw className="w-4 h-4" /> OK
            </Button>
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
                  {result.isNewCollection
                    ? `Collection « ${result.collection.name} » créée`
                    : `Tome ${result.book.series_index} → ${result.collection.name}`}
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
                  <p style={{ fontSize: 11, color: "var(--accent)", marginTop: 2 }}>
                    {result.book.series_name} #{result.book.series_index}
                  </p>
                )}
              </div>
            </div>

            <div className="flex gap-2 flex-shrink-0">
              {(Object.entries(STATUS_CONFIG) as [ReadStatus, { emoji: string; label: string }][]).map(([v, { emoji, label }]) => (
                <button key={v} onClick={() => setStatus(v)}
                  className="flex-1 py-2 rounded-xl font-semibold"
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
  const { data: session }                       = useSession();
  const [books,        setBooks]                = useState<Book[]>([]);
  const [libraryId,    setLibraryId]            = useState<string | null>(null);
  const [loading,      setLoading]              = useState(true);
  const [search,       setSearch]               = useState("");
  const [filterStatus, setFilterStatus]         = useState<FilterStatus>("all");
  const [filterType,   setFilterType]           = useState<FilterType>("all");
  const [layout,       setLayout]               = useState<Layout>("grid");
  const [selected,     setSelected]             = useState<Book | null>(null);
  const [showFilters,  setShowFilters]          = useState(false);

  const fetchBooks = useCallback(async (lid: string) => {
    const res = await fetch(`/api/books?library_id=${lid}`);
    if (res.ok) setBooks(await res.json());
  }, []);

  useEffect(() => {
    if (!session?.user?.email) return;
    fetch(`/api/library?email=${session.user.email}`)
      .then(r => r.json())
      .then(async ({ id }) => {
        if (id) { setLibraryId(id); await fetchBooks(id); }
      })
      .catch(() => {})
      .finally(() => setLoading(false));
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

  const userName = session?.user?.name?.split(" ")[0] ?? "toi";

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
            ? <img src={session.user.image} alt="" className="w-12 h-12 rounded-xl flex-shrink-0 object-cover" />
            : <div className="w-12 h-12 rounded-xl flex items-center justify-center font-bold flex-shrink-0"
                style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>{userName[0]}</div>}
        </div>

        {/* Search */}
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

        {showFilters && (
          <div className="space-y-2 mb-2">
            <FilterRow
              options={[{ v:"all", l:"Tous" }, ...Object.entries(STATUS_CONFIG).map(([v,c]) => ({ v, l:`${c.emoji} ${c.label}` }))]}
              value={filterStatus} onChange={v => setFilterStatus(v as FilterStatus)} />
            <FilterRow
              options={[{ v:"all", l:"Tous types" }, ...Object.entries(TYPE_CONFIG).map(([v,c]) => ({ v, l:`${c.emoji} ${c.label}` }))]}
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
            <div className="w-8 h-8 rounded-full border-2 animate-spin"
              style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
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
git add -A
git commit -m "feat: green frame feedback on scan success, fix library email auth"
git push
echo "🎉 Déployé !"
