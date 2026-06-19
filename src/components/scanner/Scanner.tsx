"use client";
import { useEffect, useRef, useState, useCallback } from "react";
import { BrowserMultiFormatReader } from "@zxing/library";
import { X, Keyboard, Check, RefreshCw, Edit2, AlertTriangle, ChevronDown, Plus } from "lucide-react";
import { ScanResult, ReadStatus, BookType, Collection } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";

type Phase = "scanning" | "loading" | "confirm" | "saving" | "success" | "not_found" | "error";

interface SavedBook { title: string; collection_name?: string; is_new_collection?: boolean; }

interface Props {
  rapidMode: boolean;
  libraryId: string;
  userEmail: string;
  collections: Collection[];
  onSuccess: (saved: SavedBook) => void;
  onClose: () => void;
}

// ── Reliability check ──────────────────────────────────────────────────────────
function isReliable(result: ScanResult): boolean {
  const { book } = result;
  if (book._unreliable) return false;
  if (book.series_name && book.series_index) return true; // full series info
  if (book.book_type === "bd" || book.book_type === "manga") return false; // always confirm
  if (!book.cover_url) return false;
  if (book.title.length < 4) return false;
  return true;
}

const CORNERS = [
  { top: -2,    left: -2,  borderTop: "3px solid",    borderLeft: "3px solid",  borderRadius: "6px 0 0 0" },
  { top: -2,    right: -2, borderTop: "3px solid",    borderRight: "3px solid", borderRadius: "0 6px 0 0" },
  { bottom: -2, left: -2,  borderBottom: "3px solid", borderLeft: "3px solid",  borderRadius: "0 0 0 6px" },
  { bottom: -2, right: -2, borderBottom: "3px solid", borderRight: "3px solid", borderRadius: "0 0 6px 0" },
];

// ── Shared edit form (same for both modes) ─────────────────────────────────────
function EditForm({
  editTitle, setEditTitle,
  editSeries, setEditSeries,
  editVolume, setEditVolume,
  editCover, result, collectionNames, compact = false,
}: {
  editTitle: string; setEditTitle: (v: string) => void;
  editSeries: string; setEditSeries: (v: string) => void;
  editVolume: string; setEditVolume: (v: string) => void;
  editCover?: string; result: ScanResult; collectionNames: string[];
  compact?: boolean;
}) {
  const [showDropdown, setShowDropdown] = useState(false);
  const filtered = collectionNames.filter(n => !editSeries || n.toLowerCase().includes(editSeries.toLowerCase()));

  return (
    <div className="flex flex-col gap-2">
      <input value={editTitle} onChange={e => setEditTitle(e.target.value)} placeholder="Titre..."
        className="w-full px-3 py-2 rounded-xl outline-none"
        style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: compact ? 13 : 14 }} />

      <div className="relative">
        <div className="flex items-center gap-1 px-3 py-2 rounded-xl cursor-pointer"
          onClick={() => setShowDropdown(v => !v)}
          style={{ background: "var(--surface)", border: `1px solid ${editVolume && !editSeries.trim() ? "rgba(245,158,11,0.7)" : "var(--border)"}` }}>
          <input value={editSeries}
            onChange={e => { setEditSeries(e.target.value); setShowDropdown(true); }}
            onClick={e => { e.stopPropagation(); setShowDropdown(true); }}
            placeholder={editVolume ? "⚠️ Série (obligatoire)" : "Série (ex: Les Schtroumpfs)"}
            className="flex-1 outline-none bg-transparent"
            style={{ color: "var(--txt1)", fontSize: 16 }} />
          <ChevronDown className="w-3.5 h-3.5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
        </div>
        {showDropdown && (filtered.length > 0 || (editSeries.trim() && !collectionNames.includes(editSeries.trim()))) && (
          <div className="absolute left-0 right-0 top-full mt-1 rounded-xl overflow-hidden z-20 max-h-36 overflow-y-auto"
            style={{ background: "var(--surface2)", border: "1px solid var(--border)", boxShadow: "0 4px 12px rgba(0,0,0,0.4)" }}>
            {editSeries && <button onClick={() => { setEditSeries(""); setEditVolume(""); setShowDropdown(false); }}
              className="w-full text-left px-3 py-2 text-xs"
              style={{ color: "var(--miss-t)", borderBottom: "1px solid var(--border)" }}>✕ Aucune série</button>}
            {filtered.map(name => (
              <button key={name} onClick={() => { setEditSeries(name); setShowDropdown(false); }}
                className="w-full text-left px-3 py-2 text-xs active:opacity-70"
                style={{ color: "var(--txt1)", borderBottom: "1px solid var(--border)" }}>{name}</button>
            ))}
            {editSeries.trim() && !collectionNames.includes(editSeries.trim()) && (
              <button onClick={() => setShowDropdown(false)}
                className="w-full text-left px-3 py-2 text-xs font-semibold"
                style={{ color: "var(--accent)" }}>+ Créer « {editSeries.trim()} »</button>
            )}
          </div>
        )}
      </div>

      <input value={editVolume} onChange={e => setEditVolume(e.target.value)}
        placeholder="N° de tome" type="number"
        className="w-24 px-3 py-2 rounded-xl outline-none"
        style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 16 }} />
    </div>
  );
}

// ── Main Scanner ───────────────────────────────────────────────────────────────
export default function Scanner({ rapidMode, libraryId, userEmail, collections, onSuccess, onClose }: Props) {
  const videoRef      = useRef<HTMLVideoElement>(null);
  const processingRef = useRef(false);

  const [phase,       setPhase]       = useState<Phase>("scanning");
  const [isbn,        setIsbn]        = useState("");
  const [result,      setResult]      = useState<ScanResult | null>(null);
  const [status,      setStatus]      = useState<ReadStatus>("a_lire");
  const [bookType,    setBookType]    = useState<BookType>("livre");
  const [manual,      setManual]      = useState("");
  const [showKbd,     setShowKbd]     = useState(false);
  const [needsCheck,  setNeedsCheck]  = useState(false);
  const [isNonIsbnEan, setIsNonIsbnEan] = useState(false);

  // Editable fields — shared between modes
  const [editTitle,  setEditTitle]  = useState("");
  const [editSeries, setEditSeries] = useState("");
  const [editVolume, setEditVolume] = useState("");
  const [editCover,  setEditCover]  = useState<string | undefined>();
  const [isEditing,  setIsEditing]  = useState(false);
  const [showCollectionPicker, setShowCollectionPicker] = useState(false);

  const frameColor =
    phase === "success"                        ? "#22C55E" :
    phase === "not_found" || phase === "error" ? "#EF4444" :
    needsCheck                                 ? "#F59E0B" :
    "#5B7AFF";

  const collectionNames = collections.map(c => c.name);

  // Camera
  useEffect(() => {
    const reader = new BrowserMultiFormatReader();
    reader.decodeFromVideoDevice(null, videoRef.current!, (r) => {
      if (!r || processingRef.current) return;
      processingRef.current = true;
      doLookup(r.getText());
    });
    return () => reader.reset();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Core save logic (shared) ────────────────────────────────────────────────
  const doSave = useCallback(async (
    r: ScanResult, s: ReadStatus, bt: BookType,
    title: string, coverUrl?: string, seriesName?: string, seriesIndex?: number
  ): Promise<SavedBook | null> => {
    try {
      let collectionName  = r.collection?.name;
      let isNewCollection = r.isNewCollection;

      // Create collection if:
      // 1. Server flagged it (_createCollection)
      // 2. User manually picked/typed a series name (showCollectionPicker was used)
      // 3. User manually entered a different series than suggested
      const userEnteredSeries = seriesName && seriesIndex &&
        (seriesName !== r.book.series_name || seriesIndex !== r.book.series_index);
      const shouldCreateCollection = r.book._createCollection === true || userEnteredSeries || (seriesName && showCollectionPicker);

      if (shouldCreateCollection && seriesName) {
        const idx = seriesIndex ?? 0;
        const colRes = await fetch(
          `/api/collections/resolve?library_id=${libraryId}&series_name=${encodeURIComponent(seriesName)}&series_index=${idx}&book_type=${bt}`
        );
        if (colRes.ok) { const col = await colRes.json(); collectionName = col.collection?.name; isNewCollection = col.isNew; }
      }

      // Cover fallback
      let finalCover = coverUrl;
      if (!finalCover) {
        try {
          const q = seriesName ? `${seriesName} ${title}` : title;
          const cr = await fetch(`/api/books/cover?title=${encodeURIComponent(q)}`);
          if (cr.ok) { const cd = await cr.json(); finalCover = cd.cover_url; }
        } catch { /* no cover */ }
      }

      const res = await fetch("/api/books/add", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          isbn: r.book.isbn, title,
          authors: r.book.authors,
          cover_url: finalCover ?? null,
          publisher: r.book.publisher,
          published_year: r.book.published_year,
          page_count: r.book.page_count,
          description: r.book.description,
          book_type: bt, status: s,
          series_name: seriesName || null,
          series_index: seriesIndex || null,
          library_id: libraryId,
          email: userEmail,
        }),
      });

      if (!res.ok) return null;
      const out: SavedBook = { title, collection_name: collectionName, is_new_collection: isNewCollection };
      onSuccess(out);
      return out;
    } catch { return null; }
  }, [libraryId, userEmail, onSuccess]);

  // ── Lookup ──────────────────────────────────────────────────────────────────
  const doLookup = useCallback(async (code: string) => {
    setIsbn(code);
    setPhase("loading");
    setNeedsCheck(false);
    setIsEditing(false);
    setShowCollectionPicker(false);

    const clean = code.replace(/[-\s]/g, "");
    const nonIsbn = /^\d{13}$/.test(clean) && !clean.startsWith("978") && !clean.startsWith("979");
    setIsNonIsbnEan(nonIsbn);

    try {
      const res = await fetch(`/api/books/lookup?isbn=${encodeURIComponent(code)}&library_id=${libraryId}`);

      if (!res.ok) {
        setShowKbd(true);
        setPhase("not_found");
        processingRef.current = false;
        return;
      }

      const data: ScanResult = await res.json();
      setResult(data);
      setBookType(data.book.book_type);
      setEditTitle(data.book.title ?? "");
      setEditCover(data.book.cover_url);
      setEditSeries(data.book.series_name ?? "");
      setEditVolume(data.book.series_index?.toString() ?? "");

      const reliable = isReliable(data);

      if (rapidMode && reliable) {
        // Rapid: auto-save immediately
        const saved = await doSave(data, "a_lire", data.book.book_type,
          data.book.title, data.book.cover_url, data.book.series_name, data.book.series_index);
        if (saved) {
          setPhase("success");
          setTimeout(() => { setPhase("scanning"); setResult(null); setIsbn(""); processingRef.current = false; }, 700);
        } else { setPhase("error"); processingRef.current = false; }
      } else {
        // Classic OR rapid-but-needs-check: show confirm panel
        const doubt = !reliable;
        setNeedsCheck(doubt);
        if (doubt) { setIsEditing(true); setShowKbd(nonIsbn); }
        setPhase("confirm");
        processingRef.current = false;
      }
    } catch { setPhase("error"); processingRef.current = false; }
  }, [rapidMode, libraryId, doSave]);

  // ── Confirm (shared) ────────────────────────────────────────────────────────
  const handleConfirm = async () => {
    if (!result) return;
    setPhase("saving");
    const title   = editTitle.trim()  || result.book.title;
    const serName = editSeries.trim() || undefined;
    const serIdx  = editVolume ? parseInt(editVolume) : undefined;
    const saved   = await doSave(result, status, bookType, title, editCover, serName, serIdx);
    if (saved) {
      setPhase("success");
      setTimeout(() => {
        // Rapid: go back to scanning; Classic: close
        if (rapidMode) {
          setPhase("scanning"); setResult(null); setIsbn("");
          setNeedsCheck(false); setIsEditing(false);
          processingRef.current = false;
        } else {
          onClose();
        }
      }, 600);
    } else setPhase("error");
  };

  const reset = () => {
    setPhase("scanning"); setResult(null); setIsbn("");
    setNeedsCheck(false); setIsEditing(false);
    setShowCollectionPicker(false);
    processingRef.current = false;
  };

  const canConfirm = !(editVolume && !editSeries.trim());

  // ── Render ──────────────────────────────────────────────────────────────────
  return (
    <div className="fixed inset-0 z-50 flex flex-col overflow-hidden" style={{ background: "#060818" }}>

      {/* Top bar */}
      <div className="flex items-center justify-between px-5 pt-12 pb-2 flex-shrink-0">
        <button onClick={onClose} className="w-10 h-10 rounded-full flex items-center justify-center"
          style={{ background: "rgba(255,255,255,0.08)" }}>
          <X className="w-5 h-5 text-white" />
        </button>
        <span className="font-bold text-white" style={{ fontSize: 16 }}>
          {rapidMode
            ? (needsCheck ? "⚠️ Vérification rapide" : "⚡ Mode rapide")
            : "Scanner"}
        </span>
        <button onClick={() => setShowKbd(v => !v)} className="w-10 h-10 rounded-full flex items-center justify-center"
          style={{ background: "rgba(255,255,255,0.08)" }}>
          <Keyboard className="w-5 h-5 text-white" />
        </button>
      </div>

      {/* Mode banners */}
      {rapidMode && !needsCheck && phase === "scanning" && (
        <div className="mx-5 mb-1 px-3 py-2 rounded-xl flex-shrink-0"
          style={{ background: "rgba(59,91,255,0.18)", border: "1px solid rgba(91,122,255,0.3)" }}>
          <span style={{ fontSize: 12, color: "#7B80FF" }}>⚡ Ajout instantané si fiable — scan continu</span>
        </div>
      )}
      {needsCheck && (
        <div className="mx-5 mb-1 px-3 py-2 rounded-xl flex items-center gap-2 flex-shrink-0"
          style={{ background: "rgba(245,158,11,0.15)", border: "1px solid rgba(245,158,11,0.3)" }}>
          <AlertTriangle className="w-4 h-4 flex-shrink-0" style={{ color: "#F59E0B" }} />
          <span style={{ fontSize: 12, color: "#F59E0B" }}>
            {isNonIsbnEan ? "Code EAN — tape l'ISBN (978...) ou corrige" : "Métadonnées douteuses — corrige avant d'ajouter"}
          </span>
        </div>
      )}

      {/* Camera */}
      <div className="flex items-center justify-center relative flex-shrink-0"
        style={{ padding: phase === "confirm" ? "4px 0" : "12px 0" }}>
        <div className="relative">
          <video ref={videoRef}
            style={{
              width: phase === "confirm" ? 180 : 300,
              height: phase === "confirm" ? 120 : 220,
              objectFit: "cover", borderRadius: 12, display: "block",
              transition: "width 0.3s, height 0.3s",
            }} />
          <div className="absolute inset-0 pointer-events-none">
            {CORNERS.map((s, i) => (
              <div key={i} className="absolute" style={{ width: 20, height: 20, ...s,
                borderTopColor: s.borderTop ? frameColor : undefined,
                borderBottomColor: s.borderBottom ? frameColor : undefined,
                borderLeftColor: s.borderLeft ? frameColor : undefined,
                borderRightColor: s.borderRight ? frameColor : undefined,
                transition: "border-color 0.3s" }} />
            ))}
            {(phase === "scanning" || phase === "loading") && (
              <div className="scan-line absolute left-0 right-0"
                style={{ height: 2, background: `linear-gradient(90deg,transparent,${frameColor},transparent)` }} />
            )}
            {phase === "success" && (
              <div className="absolute inset-0 flex items-center justify-center rounded-xl"
                style={{ background: "rgba(34,197,94,0.2)" }}>
                <div className="w-14 h-14 rounded-full flex items-center justify-center" style={{ background: "#22C55E" }}>
                  <Check className="w-8 h-8 text-white" />
                </div>
              </div>
            )}
          </div>
          {(phase === "loading" || phase === "saving") && (
            <div className="absolute top-2 right-2">
              <div className="w-5 h-5 rounded-full border-2 animate-spin" style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
            </div>
          )}
        </div>
      </div>

      {/* Bottom panel */}
      <div className="flex-1 rounded-t-3xl p-4 flex flex-col gap-3 overflow-y-auto min-h-0"
        style={{ background: "var(--surface)" }}>

        {/* ISBN keyboard input */}
        {showKbd && (
          <div className="flex gap-2 flex-shrink-0">
            <input type="text" inputMode="numeric" pattern="[0-9-]*" value={manual}
              onChange={e => setManual(e.target.value.replace(/[^0-9-]/g, ""))}
              placeholder="ISBN : X-XXXX-XXXX-X"
              onKeyDown={e => e.key === "Enter" && manual.trim() && (processingRef.current = true, doLookup(manual.trim()))}
              className="flex-1 px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", color: "var(--txt1)", border: "1px solid var(--border)", fontSize: 15 }} />
            <button onClick={() => manual.trim() && (processingRef.current = true, doLookup(manual.trim()))}
              className="px-5 py-3 rounded-2xl font-bold" style={{ background: "var(--accent)", color: "#fff" }}>OK</button>
          </div>
        )}

        {/* States */}
        {phase === "scanning" && !showKbd && (
          <p className="text-center py-2" style={{ fontSize: 14, color: "var(--txt2)" }}>Centrez le code-barres dans le cadre</p>
        )}
        {(phase === "loading" || phase === "saving") && (
          <div className="flex items-center justify-center gap-3 py-2">
            <div className="w-5 h-5 rounded-full border-2 animate-spin flex-shrink-0" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
            <p style={{ fontSize: 14, color: "var(--txt2)" }}>{phase === "saving" ? "Enregistrement…" : `Recherche…`}</p>
          </div>
        )}
        {phase === "success" && (
          <p className="text-center py-2 font-semibold" style={{ fontSize: 14, color: "#22C55E" }}>
            ✅ {rapidMode ? "Ajouté ! Scan suivant..." : "Ajouté !"}
          </p>
        )}
        {(phase === "not_found" || phase === "error") && (
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-3">
              <p style={{ fontSize: 14, color: "var(--miss-t)" }}>
                {phase === "error" ? "Erreur lors de l'ajout" : "Introuvable"}
              </p>
              <Button onClick={reset} size="sm" variant="secondary"><RefreshCw className="w-4 h-4" /> Réessayer</Button>
            </div>
            {phase === "not_found" && (
              <p style={{ fontSize: 12, color: "var(--txt2)" }}>
                Tape un ISBN (978...) si tu en vois un imprimé sur le livre.
              </p>
            )}
          </div>
        )}

        {/* Confirm panel — identical for both modes */}
        {phase === "confirm" && result && (
          <>
            {/* Book preview */}
            <div className="flex gap-3 p-3 rounded-2xl flex-shrink-0"
              style={{ background: "var(--surface2)", border: `1px solid ${needsCheck ? "rgba(245,158,11,0.4)" : "var(--border)"}` }}>
              <Cover src={editCover} alt={editTitle} width={44} height={62} className="rounded-lg flex-shrink-0" />
              <div className="flex-1 min-w-0">
                {isEditing ? (
                  <EditForm
                    editTitle={editTitle} setEditTitle={setEditTitle}
                    editSeries={editSeries} setEditSeries={setEditSeries}
                    editVolume={editVolume} setEditVolume={setEditVolume}
                    editCover={editCover} result={result}
                    collectionNames={collectionNames}
                    compact
                  />
                ) : (
                  <>
                    <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{editTitle}</p>
                    <p className="truncate mt-0.5" style={{ fontSize: 12, color: "var(--txt2)" }}>{result.book.authors.join(", ")}</p>
                    {editSeries && <p style={{ fontSize: 11, color: "var(--accent)", marginTop: 2 }}>{editSeries}{editVolume ? ` #${editVolume}` : ""}</p>}
                  </>
                )}
              </div>
              <button onClick={() => setIsEditing(v => !v)}
                className="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 self-start"
                style={{
                  background: isEditing ? "var(--accent)" : needsCheck ? "rgba(245,158,11,0.2)" : "var(--surface)",
                  border: `1px solid ${isEditing ? "var(--accent)" : needsCheck ? "rgba(245,158,11,0.5)" : "var(--border)"}`,
                }}>
                <Edit2 className="w-3.5 h-3.5" style={{ color: isEditing ? "#fff" : needsCheck ? "#F59E0B" : "var(--txt3)" }} />
              </button>
            </div>

            {/* Type selector */}
            <div className="flex gap-2 flex-shrink-0">
              {(Object.entries(TYPE_CONFIG) as [BookType, { emoji: string; label: string }][]).map(([v, { emoji, label }]) => (
                <button key={v} onClick={() => setBookType(v)} className="flex-1 py-1.5 rounded-xl font-semibold"
                  style={{ fontSize: 11, background: bookType === v ? "var(--accent)" : "var(--surface2)",
                    color: bookType === v ? "#fff" : "var(--txt2)", border: `1px solid ${bookType === v ? "var(--accent)" : "var(--border)"}` }}>
                  {emoji} {label}
                </button>
              ))}
            </div>

            {/* Status selector */}
            <div className="flex gap-2 flex-shrink-0">
              {(Object.entries(STATUS_CONFIG) as [ReadStatus, { emoji: string; label: string }][]).map(([v, { emoji, label }]) => (
                <button key={v} onClick={() => setStatus(v)} className="flex-1 py-2 rounded-xl font-semibold"
                  style={{ fontSize: 11, background: status === v ? "var(--accent)" : "var(--surface2)",
                    color: status === v ? "#fff" : "var(--txt2)", border: `1px solid ${status === v ? "var(--accent)" : "var(--border)"}` }}>
                  {emoji} {label}
                </button>
              ))}
            </div>

            {/* Collection picker — optional for livres, auto for BD/manga */}
            {result.book.book_type === "livre" && !result.book._createCollection && (
              showCollectionPicker ? (
                <div className="rounded-2xl overflow-hidden flex-shrink-0"
                  style={{ background: "var(--surface2)", border: "1px solid var(--accent)" }}>
                  <div className="flex items-center justify-between px-3 py-2"
                    style={{ borderBottom: "1px solid var(--border)" }}>
                    <p className="font-semibold" style={{ fontSize: 12, color: "var(--accent)" }}>📚 Collection</p>
                    <button onClick={() => { setShowCollectionPicker(false); setEditSeries(""); setEditVolume(""); }}
                      style={{ fontSize: 11, color: "var(--txt3)" }}>Annuler</button>
                  </div>
                  <div className="p-2 flex flex-col gap-1.5">
                    <EditForm
                      editTitle={editTitle} setEditTitle={setEditTitle}
                      editSeries={editSeries} setEditSeries={setEditSeries}
                      editVolume={editVolume} setEditVolume={setEditVolume}
                      editCover={editCover} result={result}
                      collectionNames={collectionNames} compact
                    />
                  </div>
                </div>
              ) : (
                <button onClick={() => setShowCollectionPicker(true)}
                  className="flex items-center gap-2 px-3 py-2.5 rounded-2xl w-full flex-shrink-0"
                  style={{ background: "var(--surface2)", border: "1px dashed var(--border)" }}>
                  <Plus className="w-4 h-4" style={{ color: "var(--accent)" }} />
                  <span style={{ fontSize: 13, color: "var(--txt2)" }}>Ajouter à une collection</span>
                </button>
              )
            )}

            {/* Series warning */}
            {editVolume && !editSeries.trim() && (
              <div className="flex items-center gap-2 px-3 py-2 rounded-xl"
                style={{ background: "rgba(245,158,11,0.12)", border: "1px solid rgba(245,158,11,0.3)" }}>
                <AlertTriangle className="w-4 h-4 flex-shrink-0" style={{ color: "#F59E0B" }} />
                <p style={{ fontSize: 12, color: "#F59E0B" }}>Renseigne la série pour créer la collection</p>
              </div>
            )}

            <Button onClick={handleConfirm} disabled={!canConfirm}
              className="w-full py-3 rounded-2xl flex-shrink-0"
              style={{ fontSize: 14, opacity: canConfirm ? 1 : 0.4 }}>
              <Check className="w-4 h-4" />
              {rapidMode
                ? (needsCheck ? "Corriger et continuer →" : "Ajouter et continuer →")
                : (needsCheck ? "Corriger et ajouter" : "Ajouter")}
            </Button>
          </>
        )}
      </div>
    </div>
  );
}
