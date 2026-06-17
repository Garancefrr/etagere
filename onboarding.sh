#!/bin/bash
set -e
echo "🎓 Tutoriel première connexion..."
cd "$(git rev-parse --show-toplevel)"
mkdir -p src/components/onboarding
cat > "src/components/onboarding/Onboarding.tsx" << 'FILEOF'
"use client";
import { useState } from "react";
import { ScanLine, Keyboard, Layers, ChevronRight, BookOpen } from "lucide-react";
import { Button } from "@/components/ui/Button";

const STEPS = [
  {
    icon: BookOpen, color: "#5B7AFF",
    title: "Bienvenue sur Folio 📚",
    desc: "Ta bibliothèque personnelle, toujours avec toi. Scanne tes livres, BD et mangas pour les organiser en collections.",
    visual: (
      <div className="flex gap-3 justify-center my-4">
        {["📖", "🎨", "⛩️"].map((e, i) => (
          <div key={i} className="w-16 h-16 rounded-2xl flex items-center justify-center"
            style={{ background: "var(--surface2)", border: "1px solid var(--border)", fontSize: 28 }}>{e}</div>
        ))}
      </div>
    ),
  },
  {
    icon: ScanLine, color: "#22C55E",
    title: "Le Scanner 📷",
    desc: "Pointe la caméra vers le code-barres au dos du livre. La détection est automatique !",
    visual: (
      <div className="relative mx-auto my-4 rounded-2xl overflow-hidden"
        style={{ width: 200, height: 130, background: "#111827", border: "2px solid rgba(34,197,94,0.4)" }}>
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="flex flex-col items-center gap-2">
            <div style={{ width: 120, height: 40, background: "repeating-linear-gradient(90deg, #fff 0px, #fff 2px, transparent 2px, transparent 5px)", opacity: 0.3, borderRadius: 4 }} />
            <span style={{ fontSize: 10, color: "rgba(255,255,255,0.5)" }}>CODE-BARRES</span>
          </div>
        </div>
        <div className="absolute left-1/2 -translate-x-1/2 top-0 bottom-0 w-px" style={{ background: "linear-gradient(transparent, #22C55E, transparent)" }} />
      </div>
    ),
  },
  {
    icon: Keyboard, color: "#FB923C",
    title: "L'ISBN, c'est quoi ? 🔢",
    desc: "Si le scan ne fonctionne pas, cherche l'ISBN imprimé sur le livre. Il commence par 978 ou par un chiffre (ex: 2-8001-...). Tu peux le taper manuellement via le bouton clavier.",
    visual: (
      <div className="mx-auto my-4 p-4 rounded-2xl" style={{ background: "var(--surface2)", border: "1px solid var(--border)", maxWidth: 240 }}>
        <div className="flex items-center gap-2 mb-2">
          <span style={{ fontSize: 11, color: "var(--txt3)", fontWeight: 700 }}>ISBN :</span>
        </div>
        <div className="flex gap-1">
          {["9","7","8","-","2","-","8","0","0","1"].map((c, i) => (
            <div key={i} className="w-5 h-7 rounded flex items-center justify-center"
              style={{ background: c === "-" ? "transparent" : "var(--accent-l)", fontSize: 12, fontWeight: 700, color: "var(--accent)" }}>
              {c}
            </div>
          ))}
          <span style={{ fontSize: 12, color: "var(--txt3)" }}>...</span>
        </div>
        <p style={{ fontSize: 10, color: "var(--txt3)", marginTop: 8 }}>
          📍 Au dos du livre, près du code-barres ou sur la page de copyright
        </p>
      </div>
    ),
  },
  {
    icon: Layers, color: "#A855F7",
    title: "Collections auto ✨",
    desc: "Les séries sont détectées automatiquement. Tes BD, mangas et sagas sont regroupées en collections avec suivi des tomes.",
    visual: (
      <div className="mx-auto my-4 flex flex-col gap-2" style={{ maxWidth: 240 }}>
        {[
          { name: "Les Schtroumpfs", tomes: "4/40", pct: 10 },
          { name: "Harry Potter", tomes: "7/7", pct: 100 },
        ].map(({ name, tomes, pct }) => (
          <div key={name} className="p-3 rounded-xl" style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
            <div className="flex justify-between items-center mb-1.5">
              <span style={{ fontSize: 13, fontWeight: 600, color: "var(--txt1)" }}>{name}</span>
              <span style={{ fontSize: 11, fontWeight: 700, color: "var(--accent)" }}>{tomes}</span>
            </div>
            <div className="h-1.5 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
              <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
            </div>
          </div>
        ))}
        <div className="flex gap-1.5 justify-center mt-1">
          {[1,2,3,4,5].map(n => (
            <div key={n} className="flex items-center justify-center font-bold"
              style={{ width: 24, height: 24, borderRadius: 6, fontSize: 9,
                background: n <= 2 ? "var(--have-bg)" : "var(--miss-bg)",
                color: n <= 2 ? "var(--have-t)" : "var(--miss-t)",
                border: n <= 2 ? "1px solid var(--have-b)" : "1px dashed var(--miss-b)" }}>
              {n}
            </div>
          ))}
        </div>
      </div>
    ),
  },
];

interface Props { onComplete: () => void; }

export default function Onboarding({ onComplete }: Props) {
  const [step, setStep] = useState(0);
  const current = STEPS[step];
  const isLast = step === STEPS.length - 1;
  const Icon = current.icon;

  return (
    <div className="fixed inset-0 z-[100] flex flex-col items-center justify-center px-6"
      style={{ background: "var(--bg)" }}>
      <div className="flex gap-2 mb-8">
        {STEPS.map((_, i) => (
          <div key={i} className="rounded-full transition-all"
            style={{ width: i === step ? 24 : 8, height: 8, background: i === step ? current.color : "var(--border)" }} />
        ))}
      </div>
      <div className="w-16 h-16 rounded-3xl flex items-center justify-center mb-4"
        style={{ background: `${current.color}18` }}>
        <Icon style={{ width: 28, height: 28, color: current.color }} />
      </div>
      <h2 className="text-center font-bold mb-2" style={{ fontSize: 22, color: "var(--txt1)" }}>{current.title}</h2>
      {current.visual}
      <p className="text-center mb-8 max-w-xs" style={{ fontSize: 15, color: "var(--txt2)", lineHeight: 1.6 }}>{current.desc}</p>
      <div className="w-full max-w-xs flex flex-col gap-3">
        <Button onClick={() => isLast ? onComplete() : setStep(s => s + 1)}
          className="w-full py-4 rounded-2xl" style={{ fontSize: 16 }}>
          {isLast ? "C'est parti ! 🚀" : "Suivant"} {!isLast && <ChevronRight className="w-5 h-5" />}
        </Button>
        {!isLast && (
          <button onClick={onComplete} className="w-full py-3 rounded-2xl font-semibold" style={{ fontSize: 14, color: "var(--txt3)" }}>
            Passer le tutoriel
          </button>
        )}
      </div>
    </div>
  );
}
FILEOF
cat > "src/app/library/page.tsx" << 'FILEOF'
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
import { Search, SlidersHorizontal, LayoutGrid, List, RefreshCw } from "lucide-react";

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

  // Show onboarding on first visit

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
git add -A
git commit -m "feat: onboarding tutorial for first-time users"
git push
echo "🎉 Déployé !"
