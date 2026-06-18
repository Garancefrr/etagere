"use client";
import { useState, useCallback, useRef } from "react";
import { useData } from "@/contexts/DataContext";
import { useLibrary } from "@/hooks/useLibrary";
import { useToast } from "@/hooks/useToast";
import { useFirstUse } from "@/hooks/useFirstUse";
import BottomNav from "@/components/layout/BottomNav";
import Scanner from "@/components/scanner/Scanner";
import { ToastStack } from "@/components/ui/Toast";
import { ScanLine, Zap, Settings2, Keyboard, ArrowRight, X, Search, Check } from "lucide-react";
import { Cover } from "@/components/ui/Cover";

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
  const [scanning,       setScanning]       = useState(false);
  const [rapidMode,      setRapidMode]      = useState(false);
  const [showIsbnInput,  setShowIsbnInput]  = useState(false);
  const [showSearch,     setShowSearch]     = useState(false);
  const isFirstUse                          = useFirstUse("folio_scan_seen");
  const { toasts, push, dismiss }           = useToast();

  const handleSuccess = useCallback((saved: SavedBook) => {
    push(saved.title, saved.is_new_collection
      ? `Collection « ${saved.collection_name} » créée`
      : saved.collection_name
        ? `Ajouté à ${saved.collection_name}`
        : undefined);
    if (!rapidMode) { setScanning(false); setShowIsbnInput(false); }
    refreshAll();
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

        <div className="flex flex-col gap-3 px-4">
          {/* Main scan button */}
          <button onClick={() => { ready && setScanning(true); }} disabled={!ready}
            className="w-full py-5 rounded-3xl flex items-center justify-center gap-3 active:scale-95"
            style={{ background: ready ? "var(--accent)" : "var(--surface)", boxShadow: ready ? "0 8px 32px rgba(59,91,255,0.35)" : "none", opacity: ready ? 1 : 0.6 }}>
            {!ready
              ? <div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
              : <ScanLine className="w-7 h-7 text-white" />}
            <span className="font-bold text-white" style={{ fontSize: 17 }}>
              {!ready ? "Chargement…" : rapidMode ? "Lancer le mode rapide" : "Ouvrir le scanner"}
            </span>
          </button>

          {/* Search by title button */}
          <button onClick={() => { setShowSearch(v => !v); setShowIsbnInput(false); }} disabled={!ready}
            className="w-full py-4 rounded-2xl flex items-center justify-center gap-3 active:scale-95"
            style={{ background: showSearch ? "var(--accent-l)" : "var(--surface)", border: `1px solid ${showSearch ? "var(--accent)" : "var(--border)"}`, opacity: ready ? 1 : 0.5 }}>
            <Search className="w-5 h-5" style={{ color: "var(--accent)" }} />
            <span className="font-semibold" style={{ fontSize: 15, color: showSearch ? "var(--accent)" : "var(--txt1)" }}>
              Rechercher par titre
            </span>
          </button>

          {/* Inline search panel */}
          {showSearch && ready && library_id && email && (
            <SearchPanel
              libraryId={library_id}
              userEmail={email}
              collections={collections}
              onSuccess={s => { handleSuccess(s); setShowSearch(false); }}
            />
          )}

          {/* ISBN direct input button */}
          <button onClick={() => { setShowIsbnInput(v => !v); setShowSearch(false); }} disabled={!ready}
            className="w-full py-4 rounded-2xl flex items-center justify-center gap-3 active:scale-95"
            style={{ background: showIsbnInput ? "var(--accent-l)" : "var(--surface)", border: `1px solid ${showIsbnInput ? "var(--accent)" : "var(--border)"}`, opacity: ready ? 1 : 0.5 }}>
            <Keyboard className="w-5 h-5" style={{ color: "var(--accent)" }} />
            <span className="font-semibold" style={{ fontSize: 15, color: showIsbnInput ? "var(--accent)" : "var(--txt1)" }}>
              Saisir un ISBN manuellement
            </span>
          </button>

          {/* Inline ISBN input panel */}
          {showIsbnInput && ready && library_id && email && (
            <IsbnPanel
              libraryId={library_id}
              userEmail={email}
              collections={collections}
              rapidMode={rapidMode}
              onSuccess={handleSuccess}
              onClose={() => setShowIsbnInput(false)}
            />
          )}

          {ready && !showIsbnInput && !showSearch && (
            <p className="text-center" style={{ fontSize: 13, color: "var(--txt3)" }}>
              Vieille BD ou code-barres illisible ? Recherche par titre ou ISBN
            </p>
          )}
        </div>
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

// ── Inline ISBN panel ─────────────────────────────────────────────────────────

interface IsbnPanelProps {
  libraryId: string;
  userEmail: string;
  collections: any[];
  rapidMode: boolean;
  onSuccess: (saved: SavedBook) => void;
  onClose: () => void;
}

function IsbnPanel({ libraryId, userEmail, collections, rapidMode, onSuccess, onClose }: IsbnPanelProps) {
  const [isbn,    setIsbn]    = useState("");
  const [loading, setLoading] = useState(false);
  const [found,   setFound]   = useState<any>(null);
  const [error,   setError]   = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  const doSearch = async () => {
    const clean = isbn.trim();
    if (!clean) return;
    setLoading(true); setError(""); setFound(null);
    try {
      const res = await fetch(`/api/books/lookup?isbn=${encodeURIComponent(clean)}&library_id=${libraryId}`);
      if (!res.ok) { setError("Aucun résultat pour cet ISBN. Vérifie le numéro et réessaie."); return; }
      setFound(await res.json());
    } catch { setError("Erreur réseau, réessaie."); }
    finally { setLoading(false); }
  };

  const doAdd = async () => {
    if (!found) return;
    setLoading(true);
    try {
      // Create collection only if flagged by lookup
      let collectionName, isNew;
      if (found.book._createCollection && found.book.series_name) {
        const colRes = await fetch(
          `/api/collections/resolve?library_id=${libraryId}&series_name=${encodeURIComponent(found.book.series_name)}&series_index=${found.book.series_index ?? 0}&book_type=${found.book.book_type}`
        );
        if (colRes.ok) { const c = await colRes.json(); collectionName = c.collection?.name; isNew = c.isNew; }
      }
      const res = await fetch("/api/books/add", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          isbn: found.book.isbn, title: found.book.title,
          authors: found.book.authors,
          cover_url: found.book.cover_url || null,
          publisher: found.book.publisher || null,
          published_year: found.book.published_year || null,
          page_count: found.book.page_count || null,
          description: found.book.description || null,
          book_type: found.book.book_type, status: "a_lire",
          series_name: found.book.series_name || null,
          series_index: found.book.series_index || null,
          library_id: libraryId, email: userEmail,
        }),
      });
      if (res.ok) {
        onSuccess({ title: found.book.title, collection_name: collectionName, is_new_collection: isNew });
        setFound(null); setIsbn("");
      } else { setError("Erreur lors de l'ajout."); }
    } finally { setLoading(false); }
  };

  return (
    <div className="rounded-2xl overflow-hidden" style={{ background: "var(--surface)", border: "1px solid var(--accent)", borderTop: "3px solid var(--accent)" }}>
      {/* ISBN input */}
      <div className="p-4 flex gap-2">
        <input ref={inputRef} autoFocus type="text" inputMode="numeric" value={isbn}
          onChange={e => { setIsbn(e.target.value.replace(/[^0-9-]/g, "")); setFound(null); setError(""); }}
          onKeyDown={e => e.key === "Enter" && doSearch()}
          placeholder="978-2-8001-..."
          className="flex-1 px-4 py-3 rounded-2xl outline-none"
          style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 16, fontFamily: "monospace" }} />
        <button onClick={doSearch} disabled={!isbn.trim() || loading}
          className="w-12 h-12 rounded-2xl flex items-center justify-center flex-shrink-0"
          style={{ background: "var(--accent)", opacity: !isbn.trim() ? 0.4 : 1 }}>
          {loading
            ? <div className="w-5 h-5 rounded-full border-2 animate-spin" style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
            : <ArrowRight className="w-5 h-5 text-white" />}
        </button>
      </div>

      <p className="px-4 pb-3" style={{ fontSize: 11, color: "var(--txt3)" }}>
        L&apos;ISBN se trouve au dos du livre, près du code-barres. Il commence par 978, 979 ou un chiffre (ex: 2-8001-...).
      </p>

      {/* Error */}
      {error && (
        <div className="mx-4 mb-3 p-3 rounded-xl" style={{ background: "var(--miss-bg)", border: "1px solid var(--miss-b)" }}>
          <p style={{ fontSize: 13, color: "var(--miss-t)" }}>{error}</p>
        </div>
      )}

      {/* Result */}
      {found && (
        <div className="border-t mx-0 px-4 py-4 flex flex-col gap-3" style={{ borderColor: "var(--border)" }}>
          <div className="flex gap-3 items-center">
            {found.book.cover_url
              ? <Cover src={found.book.cover_url} alt={found.book.title} width={48} height={68} className="rounded-lg flex-shrink-0" />
              : <div className="rounded-lg flex-shrink-0 flex items-center justify-center" style={{ width: 48, height: 68, background: "var(--surface2)", border: "1px solid var(--border)", fontSize: 20 }}>
                  {found.book.book_type === "bd" ? "🎨" : found.book.book_type === "manga" ? "⛩️" : "📖"}
                </div>
            }
            <div className="flex-1 min-w-0">
              <p className="font-bold" style={{ fontSize: 15, color: "var(--txt1)" }}>{found.book.title}</p>
              <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{found.book.authors?.join(", ")}</p>
              {found.book.series_name && (
                <p style={{ fontSize: 12, color: "var(--accent)", marginTop: 2 }}>
                  {found.book.series_name}{found.book.series_index ? ` #${found.book.series_index}` : ""}
                </p>
              )}
            </div>
          </div>
          <button onClick={doAdd} disabled={loading}
            className="w-full py-3.5 rounded-2xl font-bold flex items-center justify-center gap-2"
            style={{ background: "var(--accent)", color: "#fff", fontSize: 15 }}>
            {loading
              ? <div className="w-5 h-5 rounded-full border-2 animate-spin" style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
              : "✅ Ajouter à ma bibliothèque"
            }
          </button>
        </div>
      )}
    </div>
  );
}

// ── Search panel ──────────────────────────────────────────────────────────────

interface SearchPanelProps {
  libraryId: string;
  userEmail: string;
  collections: any[];
  onSuccess: (saved: SavedBook) => void;
}

function SearchPanel({ libraryId, userEmail, collections, onSuccess }: SearchPanelProps) {
  const [query,      setQuery]      = useState("");
  const [results,    setResults]    = useState<any[]>([]);
  const [searching,  setSearching]  = useState(false);
  const [selected,   setSelected]   = useState<any | null>(null);
  const [saving,     setSaving]     = useState(false);
  const [addError,   setAddError]   = useState("");
  const timerRef = useRef<NodeJS.Timeout | null>(null);

  const handleQuery = (v: string) => {
    setQuery(v);
    setSelected(null);
    setAddError("");
    if (timerRef.current) clearTimeout(timerRef.current);
    if (v.length < 2) { setResults([]); return; }
    setSearching(true);
    timerRef.current = setTimeout(async () => {
      try {
        const res = await fetch(`/api/books/search?q=${encodeURIComponent(v)}`);
        if (res.ok) setResults(await res.json());
      } catch { /* ignore */ }
      setSearching(false);
    }, 400);
  };

  const doAdd = async (book: any) => {
    setSaving(true);
    setAddError("");
    try {
      let collectionName, isNew;
      if (book.series_name && book.series_index) {
        const colRes = await fetch(
          `/api/collections/resolve?library_id=${libraryId}&series_name=${encodeURIComponent(book.series_name)}&series_index=${book.series_index}&book_type=${book.book_type || "livre"}`
        );
        if (colRes.ok) { const c = await colRes.json(); collectionName = c.collection?.name; isNew = c.isNew; }
      }
      const res = await fetch("/api/books/add", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          isbn: book.isbn || null, title: book.title,
          authors: book.authors, cover_url: book.cover_url,
          publisher: book.publisher, published_year: book.published_year,
          page_count: book.page_count, description: book.description,
          book_type: book.book_type || "livre", status: "a_lire",
          series_name: book.series_name || null,
          series_index: book.series_index || null,
          library_id: libraryId, email: userEmail,
        }),
      });
      if (res.status === 409) {
        setAddError("Ce livre est déjà dans ta bibliothèque");
        return;
      }
      if (!res.ok) {
        const d = await res.json().catch(() => ({}));
        setAddError(d.error ?? "Erreur lors de l'ajout");
        return;
      }
      onSuccess({ title: book.title, collection_name: collectionName, is_new_collection: isNew });
    } catch { setAddError("Erreur réseau"); }
    finally { setSaving(false); }
  };

  return (
    <div className="rounded-2xl overflow-hidden"
      style={{ background: "var(--surface)", border: "1px solid var(--accent)", borderTop: "3px solid var(--accent)" }}>
      {/* Search input */}
      <div className="p-4 flex gap-2">
        <div className="flex-1 flex items-center gap-2 px-4 py-3 rounded-2xl"
          style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
          {searching
            ? <div className="w-4 h-4 rounded-full border-2 animate-spin flex-shrink-0" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
            : <Search className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />}
          <input autoFocus type="text" value={query} onChange={e => handleQuery(e.target.value)}
            placeholder="Titre, auteur..."
            className="flex-1 outline-none bg-transparent"
            style={{ color: "var(--txt1)", fontSize: 15 }} />
          {query && <button onClick={() => { setQuery(""); setResults([]); setSelected(null); }}>
            <X className="w-4 h-4" style={{ color: "var(--txt3)" }} />
          </button>}
        </div>
      </div>

      {/* Results list */}
      {!selected && results.length > 0 && (
        <div style={{ borderTop: "1px solid var(--border)", maxHeight: 320, overflowY: "auto" }}>
          {results.map((book, i) => (
            <button key={i} onClick={() => setSelected(book)}
              className="w-full flex items-center gap-3 px-4 py-3 text-left active:opacity-70"
              style={{ borderBottom: "1px solid var(--border)" }}>
              <Cover src={book.cover_url} alt={book.title} width={36} height={50} className="rounded-lg flex-shrink-0" />
              <div className="flex-1 min-w-0">
                <p className="font-semibold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{book.title}</p>
                <p className="truncate" style={{ fontSize: 12, color: "var(--txt2)", marginTop: 1 }}>{book.authors?.join(", ")}</p>
                {book.series_name && (
                  <p style={{ fontSize: 11, color: "var(--accent)", marginTop: 1 }}>
                    {book.series_name}{book.series_index ? ` #${book.series_index}` : ""}
                  </p>
                )}
              </div>
              {book.published_year && <span style={{ fontSize: 11, color: "var(--txt3)", flexShrink: 0 }}>{book.published_year}</span>}
            </button>
          ))}
        </div>
      )}

      {/* Selected book confirm */}
      {selected && (
        <div style={{ borderTop: "1px solid var(--border)" }}>
          <div className="flex items-center gap-3 px-4 py-3">
            <Cover src={selected.cover_url} alt={selected.title} width={48} height={68} className="rounded-xl flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="font-bold" style={{ fontSize: 15, color: "var(--txt1)" }}>{selected.title}</p>
              <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{selected.authors?.join(", ")}</p>
              {selected.series_name && (
                <p style={{ fontSize: 12, color: "var(--accent)", marginTop: 2 }}>
                  {selected.series_name}{selected.series_index ? ` #${selected.series_index}` : ""}
                </p>
              )}
              {selected.publisher && <p style={{ fontSize: 11, color: "var(--txt3)", marginTop: 2 }}>{selected.publisher}</p>}
            </div>
            <button onClick={() => setSelected(null)} className="p-1" style={{ color: "var(--txt3)" }}>
              <X className="w-4 h-4" />
            </button>
          </div>
          <div className="px-4 pb-4">
              {addError && (
                <p className="text-xs mb-2 text-center" style={{ color: "var(--miss-t)" }}>{addError}</p>
              )}
              <button onClick={() => doAdd(selected)} disabled={saving}
                className="w-full py-3.5 rounded-2xl font-bold flex items-center justify-center gap-2"
                style={{ background: "var(--accent)", color: "#fff", fontSize: 15 }}>
                {saving
                  ? <div className="w-5 h-5 rounded-full border-2 animate-spin" style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
                  : <><Check className="w-5 h-5" /> Ajouter à ma bibliothèque</>}
              </button>
            </div>
        </div>
      )}

      {!searching && query.length >= 2 && results.length === 0 && !selected && (
        <p className="px-4 pb-4" style={{ fontSize: 13, color: "var(--txt3)" }}>
          Aucun résultat pour « {query} »
        </p>
      )}
    </div>
  );
}
