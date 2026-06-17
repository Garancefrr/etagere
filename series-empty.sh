#!/bin/bash
set -e
echo "🔧 Champ série vide si non détecté automatiquement..."
cd "$(git rev-parse --show-toplevel)"
cat > src/components/scanner/Scanner.tsx << 'FILEOF'
"use client";
import { useEffect, useRef, useState, useCallback } from "react";
import { BrowserMultiFormatReader } from "@zxing/library";
import { X, Keyboard, Check, Plus, RefreshCw, Edit2, AlertTriangle, ChevronDown } from "lucide-react";
import { ScanResult, ReadStatus, BookType, Collection } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";

type Phase = "scanning" | "loading" | "confirm" | "saving" | "success" | "not_found" | "error";

interface SavedBook {
  title: string;
  collection_name?: string;
  is_new_collection?: boolean;
}

interface Props {
  rapidMode: boolean;
  libraryId: string;
  userEmail: string;
  collections: Collection[];
  onSuccess: (saved: SavedBook) => void;
  onClose: () => void;
}

function isReliable(result: ScanResult): boolean {
  const { book } = result;
  if (book._unreliable) return false;
  if (book.series_name && book.series_index) return true;
  if (book.book_type === "bd" || book.book_type === "manga") return false;
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

  // Editable fields
  const [editTitle,   setEditTitle]   = useState("");
  const [editSeries,  setEditSeries]  = useState("");
  const [editVolume,  setEditVolume]  = useState("");
  const [editCover,   setEditCover]   = useState<string | undefined>();
  const [isEditing,   setIsEditing]   = useState(false);
  const [showDropdown, setShowDropdown] = useState(false);
  const [isNonIsbnEan, setIsNonIsbnEan] = useState(false);

  const frameColor =
    phase === "success"                        ? "#22C55E" :
    phase === "not_found" || phase === "error" ? "#EF4444" :
    needsCheck                                 ? "#F59E0B" :
    "#5B7AFF";

  // Collection names for dropdown
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

  // Lookup
  const doLookup = useCallback(async (code: string) => {
    setIsbn(code);
    setPhase("loading");
    setNeedsCheck(false);
    setIsEditing(false);
    setShowDropdown(false);

    const clean = code.replace(/[-\s]/g, "");
    const nonIsbn = /^\d{13}$/.test(clean) && !clean.startsWith("978") && !clean.startsWith("979");
    setIsNonIsbnEan(nonIsbn);

    try {
      const res = await fetch(`/api/books/lookup?isbn=${encodeURIComponent(code)}&library_id=${libraryId}`);
      if (!res.ok) {
        // For non-ISBN EAN: auto-open keyboard so user can type the printed ISBN
        if (nonIsbn) setShowKbd(true);
        setPhase("not_found");
        processingRef.current = false;
        return;
      }

      const data: ScanResult = await res.json();
      setResult(data);
      setBookType(data.book.book_type);
      setEditTitle(data.book.title ?? "");
      setEditCover(data.book.cover_url);

      // Only pre-fill series if the API actually detected a series_name + series_index
      // If no series detected, leave empty so user can type the correct series name
      const hasDetectedSeries = !!(data.book.series_name && data.book.series_index);
      setEditSeries(hasDetectedSeries ? (data.book.series_name ?? "") : "");
      setEditVolume(hasDetectedSeries ? (data.book.series_index?.toString() ?? "") : "");

      if (rapidMode && isReliable(data)) {
        const saved = await doSave(data, "a_lire", data.book.book_type,
          data.book.title, data.book.cover_url, data.book.series_name, data.book.series_index);
        if (saved) {
          setPhase("success");
          setTimeout(() => { setPhase("scanning"); setResult(null); setIsbn(""); processingRef.current = false; }, 800);
        } else { setPhase("error"); processingRef.current = false; }
      } else {
        const doubt = !isReliable(data);
        setNeedsCheck(rapidMode ? doubt : doubt && nonIsbn);
        if (doubt) {
          setIsEditing(true);
          if (nonIsbn) setShowKbd(true);
        }
        setPhase("confirm");
        processingRef.current = false;
      }
    } catch {
      setPhase("error"); processingRef.current = false;
    }
  }, [rapidMode, libraryId]); // eslint-disable-line react-hooks/exhaustive-deps

  // Save
  const doSave = async (
    r: ScanResult, s: ReadStatus, bt: BookType,
    title: string, coverUrl?: string, seriesName?: string, seriesIndex?: number
  ): Promise<SavedBook | null> => {
    try {
      let collectionName  = r.collection?.name;
      let isNewCollection = r.isNewCollection;

      // Resolve collection if series was manually set
      const hasManualSeries = seriesName && seriesIndex && (bt === "bd" || bt === "manga");
      if (hasManualSeries) {
        const colRes = await fetch(
          `/api/collections/resolve?library_id=${libraryId}&series_name=${encodeURIComponent(seriesName!)}&series_index=${seriesIndex}&book_type=${bt}`
        );
        if (colRes.ok) {
          const col = await colRes.json();
          collectionName  = col.collection?.name;
          isNewCollection = col.isNew;
        }
      }

      const res = await fetch("/api/books/add", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          isbn: r.book.isbn, title,
          authors: r.book.authors,
          cover_url: coverUrl ?? r.book.cover_url,
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

      if (!res.ok) { console.error("doSave:", await res.json()); return null; }
      const saved = await res.json();
      const out: SavedBook = { title: saved.title ?? title, collection_name: collectionName, is_new_collection: isNewCollection };
      onSuccess(out);
      return out;
    } catch (e) { console.error("doSave:", e); return null; }
  };

  const handleConfirm = async () => {
    if (!result) return;
    setPhase("saving");
    const title     = editTitle.trim()  || result.book.title;
    const serName   = editSeries.trim() || undefined;
    const serIdx    = editVolume ? parseInt(editVolume) : undefined;

    // If title was changed, re-search cover with corrected title
    let coverUrl = editCover;
    const titleChanged = title.toLowerCase() !== result.book.title.toLowerCase();
    if (titleChanged || !coverUrl) {
      try {
        const q = serName ? `${serName} ${title}` : title;
        const coverRes = await fetch(`/api/books/cover?title=${encodeURIComponent(q)}`);
        if (coverRes.ok) {
          const coverData = await coverRes.json();
          if (coverData.cover_url) coverUrl = coverData.cover_url;
        }
      } catch { /* keep existing cover */ }
    }

    const saved = await doSave(result, status, bookType, title, coverUrl, serName, serIdx);
    if (saved) {
      setPhase("success");
      setTimeout(() => {
        setPhase("scanning"); setResult(null); setIsbn("");
        setNeedsCheck(false); setIsEditing(false);
        processingRef.current = false;
      }, 600);
    } else setPhase("error");
  };

  const reset = () => {
    setPhase("scanning"); setResult(null); setIsbn("");
    setNeedsCheck(false); setIsEditing(false); processingRef.current = false;
  };

  const selectCollection = (name: string) => {
    setEditSeries(name);
    setShowDropdown(false);
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
          {rapidMode ? (needsCheck ? "⚠️ Vérification" : "⚡ Mode rapide") : "Scanner"}
        </span>
        <button onClick={() => setShowKbd(v => !v)} className="w-10 h-10 rounded-full flex items-center justify-center"
          style={{ background: "rgba(255,255,255,0.08)" }}>
          <Keyboard className="w-5 h-5 text-white" />
        </button>
      </div>

      {rapidMode && !needsCheck && phase !== "confirm" && (
        <div className="mx-5 mb-1 px-3 py-2 rounded-xl flex-shrink-0"
          style={{ background: "rgba(59,91,255,0.18)", border: "1px solid rgba(91,122,255,0.3)" }}>
          <span style={{ fontSize: 12, color: "#7B80FF" }}>Scan continu — ajout instantané si fiable</span>
        </div>
      )}
      {needsCheck && (
        <div className="mx-5 mb-1 px-3 py-2 rounded-xl flex items-center gap-2 flex-shrink-0"
          style={{ background: "rgba(245,158,11,0.15)", border: "1px solid rgba(245,158,11,0.3)" }}>
          <AlertTriangle className="w-4 h-4 flex-shrink-0" style={{ color: "#F59E0B" }} />
          <span style={{ fontSize: 12, color: "#F59E0B" }}>
            {isNonIsbnEan
              ? "Code EAN — corrige le titre ou tape l'ISBN (978...) ci-dessous"
              : "Métadonnées douteuses — corrige avant d'ajouter"}
          </span>
        </div>
      )}

      {/* Camera */}
      <div className="flex-1 flex items-center justify-center relative min-h-0">
        <div className="relative">
          <video ref={videoRef} style={{ width: 300, height: 220, objectFit: "cover", borderRadius: 12, display: "block" }} />
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
              <div className="absolute inset-0 flex items-center justify-center rounded-xl" style={{ background: "rgba(34,197,94,0.2)" }}>
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

      {/* Manual */}
      {showKbd && (
        <div className="flex gap-2 px-5 mb-2 flex-shrink-0">
          <input type="text" inputMode="numeric" pattern="[0-9-]*" value={manual} onChange={e => setManual(e.target.value.replace(/[^0-9-]/g, ""))}
            placeholder="ISBN : X-XXXX-XXXX-X"
            onKeyDown={e => e.key === "Enter" && manual.trim() && (processingRef.current = true, doLookup(manual.trim()))}
            className="flex-1 px-4 py-3 rounded-2xl outline-none"
            style={{ background: "rgba(255,255,255,0.08)", color: "white", border: "1px solid rgba(91,122,255,0.3)", fontSize: 15 }} />
          <button onClick={() => manual.trim() && (processingRef.current = true, doLookup(manual.trim()))}
            className="px-5 py-3 rounded-2xl font-bold" style={{ background: "var(--accent)", color: "#fff" }}>OK</button>
        </div>
      )}

      {/* Bottom panel */}
      <div className="flex-shrink-0 rounded-t-3xl p-4 flex flex-col gap-3"
        style={{ background: "var(--surface)", maxHeight: "55vh", overflowY: "auto" }}>

        {phase === "scanning" && (
          <p className="text-center py-2" style={{ fontSize: 14, color: "var(--txt2)" }}>Centrez le code-barres dans le cadre</p>
        )}
        {(phase === "loading" || phase === "saving") && (
          <div className="flex items-center justify-center gap-3 py-2">
            <div className="w-5 h-5 rounded-full border-2 animate-spin flex-shrink-0" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
            <p style={{ fontSize: 14, color: "var(--txt2)" }}>{phase === "saving" ? "Enregistrement…" : `Recherche ${isbn}…`}</p>
          </div>
        )}
        {phase === "success" && (
          <p className="text-center py-2 font-semibold" style={{ fontSize: 14, color: "#22C55E" }}>✅ Ajouté !</p>
        )}
        {(phase === "not_found" || phase === "error") && (
          <div className="flex flex-col gap-2 py-1">
            <div className="flex items-center justify-between gap-3">
              <p style={{ fontSize: 14, color: "var(--miss-t)" }}>
                {phase === "error" ? "Erreur lors de l'ajout" : `Introuvable — ${isbn}`}
              </p>
              <Button onClick={reset} size="sm" variant="secondary"><RefreshCw className="w-4 h-4" /> Réessayer</Button>
            </div>
            {isNonIsbnEan && phase === "not_found" && (
              <p style={{ fontSize: 12, color: "var(--txt2)", lineHeight: 1.5 }}>
                Ce code EAN n&apos;est pas un ISBN. Si tu vois un ISBN (978...) imprimé sur la BD, tape-le ci-dessus ⬆️
              </p>
            )}
          </div>
        )}

        {phase === "confirm" && result && (
          <>
            {/* Book preview + edit */}
            <div className="flex gap-3 p-3 rounded-2xl flex-shrink-0"
              style={{ background: "var(--surface2)", border: `1px solid ${needsCheck ? "rgba(245,158,11,0.4)" : "var(--border)"}` }}>
              <Cover src={editCover} alt={editTitle} width={44} height={62} className="rounded-lg flex-shrink-0" />
              <div className="flex-1 min-w-0">
                {isEditing ? (
                  <div className="flex flex-col gap-2">
                    <input value={editTitle} onChange={e => setEditTitle(e.target.value)} placeholder="Titre..."
                      className="w-full px-2 py-1.5 rounded-lg outline-none"
                      style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 13 }} />

                    {/* Series dropdown */}
                    <div className="relative">
                      <div className="flex items-center gap-1 px-2 py-1.5 rounded-lg cursor-pointer"
                        onClick={() => setShowDropdown(v => !v)}
                        style={{ background: "var(--surface)", border: `1px solid ${editVolume && !editSeries.trim() ? "rgba(245,158,11,0.7)" : "var(--border)"}` }}>
                        <input value={editSeries}
                          onChange={e => { setEditSeries(e.target.value); setShowDropdown(true); }}
                          onClick={e => { e.stopPropagation(); setShowDropdown(true); }}
                          placeholder={editVolume ? "⚠️ Nom de la série (obligatoire)" : "Série (ex: Les Schtroumpfs)"}
                          className="flex-1 outline-none bg-transparent"
                          style={{ color: "var(--txt1)", fontSize: 12 }} />
                        <ChevronDown className="w-3.5 h-3.5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
                      </div>
                      {showDropdown && collectionNames.length > 0 && (
                        <div className="absolute left-0 right-0 top-full mt-1 rounded-lg overflow-hidden z-10 max-h-32 overflow-y-auto"
                          style={{ background: "var(--surface)", border: "1px solid var(--border)", boxShadow: "0 4px 12px rgba(0,0,0,0.3)" }}>
                          {collectionNames
                            .filter(n => !editSeries || n.toLowerCase().includes(editSeries.toLowerCase()))
                            .map(name => (
                              <button key={name} onClick={() => selectCollection(name)}
                                className="w-full text-left px-3 py-2 active:opacity-70"
                                style={{ fontSize: 12, color: "var(--txt1)", borderBottom: "1px solid var(--border)" }}>
                                {name}
                              </button>
                            ))}
                          {editSeries.trim() && !collectionNames.includes(editSeries.trim()) && (
                            <button onClick={() => { setShowDropdown(false); }}
                              className="w-full text-left px-3 py-2"
                              style={{ fontSize: 12, color: "var(--accent)", fontWeight: 600 }}>
                              + Créer « {editSeries.trim()} »
                            </button>
                          )}
                        </div>
                      )}
                    </div>

                    <input value={editVolume} onChange={e => setEditVolume(e.target.value)}
                      placeholder="N° de tome" type="number"
                      className="w-20 px-2 py-1.5 rounded-lg outline-none"
                      style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 12 }} />
                  </div>
                ) : (
                  <>
                    <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{editTitle}</p>
                    <p className="truncate" style={{ fontSize: 12, color: "var(--txt2)", marginTop: 2 }}>{result.book.authors.join(", ")}</p>
                    {editSeries && <p style={{ fontSize: 11, color: "var(--accent)", marginTop: 2 }}>{editSeries} #{editVolume}</p>}
                  </>
                )}
              </div>
              <button onClick={() => { setIsEditing(v => !v); setShowDropdown(false); }}
                className="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 self-start"
                style={{
                  background: isEditing ? "var(--accent)" : needsCheck ? "rgba(245,158,11,0.2)" : "var(--surface)",
                  border: `1px solid ${isEditing ? "var(--accent)" : needsCheck ? "rgba(245,158,11,0.5)" : "var(--border)"}`,
                }}>
                <Edit2 className="w-3.5 h-3.5" style={{ color: isEditing ? "#fff" : needsCheck ? "#F59E0B" : "var(--txt3)" }} />
              </button>
            </div>

            {/* Type + Status */}
            <div className="flex gap-2 flex-shrink-0">
              {(Object.entries(TYPE_CONFIG) as [BookType, { emoji: string; label: string }][]).map(([v, { emoji, label }]) => (
                <button key={v} onClick={() => setBookType(v)} className="flex-1 py-1.5 rounded-xl font-semibold"
                  style={{ fontSize: 11, background: bookType === v ? "var(--accent)" : "var(--surface2)",
                    color: bookType === v ? "#fff" : "var(--txt2)", border: `1px solid ${bookType === v ? "var(--accent)" : "var(--border)"}` }}>
                  {emoji} {label}
                </button>
              ))}
            </div>
            <div className="flex gap-2 flex-shrink-0">
              {(Object.entries(STATUS_CONFIG) as [ReadStatus, { emoji: string; label: string }][]).map(([v, { emoji, label }]) => (
                <button key={v} onClick={() => setStatus(v)} className="flex-1 py-2 rounded-xl font-semibold"
                  style={{ fontSize: 11, background: status === v ? "var(--accent)" : "var(--surface2)",
                    color: status === v ? "#fff" : "var(--txt2)", border: `1px solid ${status === v ? "var(--accent)" : "var(--border)"}` }}>
                  {emoji} {label}
                </button>
              ))}
            </div>

            {/* Series missing warning */}
            {editVolume && !editSeries.trim() && (
              <div className="flex items-center gap-2 px-3 py-2 rounded-xl flex-shrink-0"
                style={{ background: "rgba(245,158,11,0.12)", border: "1px solid rgba(245,158,11,0.3)" }}>
                <AlertTriangle className="w-4 h-4 flex-shrink-0" style={{ color: "#F59E0B" }} />
                <p style={{ fontSize: 12, color: "#F59E0B" }}>
                  Renseigne le nom de la série pour créer la collection
                </p>
              </div>
            )}

            <Button
              onClick={handleConfirm}
              disabled={!!editVolume && !editSeries.trim()}
              className="w-full py-3 rounded-2xl flex-shrink-0"
              style={{ fontSize: 14, opacity: editVolume && !editSeries.trim() ? 0.4 : 1 }}>
              <Check className="w-4 h-4" /> {needsCheck ? "Corriger et ajouter" : "Ajouter"}
            </Button>
          </>
        )}
      </div>
    </div>
  );
}
FILEOF
git add -A
git commit -m "fix: series field empty when not auto-detected, no more pre-fill with BD title"
git push
echo "🎉 Déployé !"
