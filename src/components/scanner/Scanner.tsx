"use client";
import { useEffect, useRef, useState, useCallback } from "react";
import { BrowserMultiFormatReader } from "@zxing/library";
import { X, Keyboard, RefreshCw, Check, BookOpen, Plus } from "lucide-react";
import { ScanResult, ReadStatus, BookType } from "@/types";

interface Props {
  onSuccess: (result: ScanResult, status: ReadStatus, bookType: BookType) => void;
  onClose: () => void;
}
type Phase = "scanning" | "loading" | "confirm" | "not_found" | "error";

export default function Scanner({ onSuccess, onClose }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [phase, setPhase] = useState<Phase>("scanning");
  const [isbn, setIsbn] = useState("");
  const [scanResult, setScanResult] = useState<ScanResult | null>(null);
  const [status, setStatus] = useState<ReadStatus>("a_lire");
  const [bookType, setBookType] = useState<BookType>("livre");
  const [manualISBN, setManualISBN] = useState("");
  const [showManual, setShowManual] = useState(false);

  const lookup = useCallback(async (code: string) => {
    setIsbn(code);
    setPhase("loading");
    try {
      const res = await fetch(`/api/books/lookup?isbn=${code}&library_id=lib1`);
      if (res.ok) {
        const result: ScanResult = await res.json();
        setScanResult(result);
        setBookType(result.book.book_type);
        setPhase("confirm");
      } else { setPhase("not_found"); }
    } catch { setPhase("error"); }
  }, []);

  useEffect(() => {
    const reader = new BrowserMultiFormatReader();
    let active = true;
    if (videoRef.current) {
      reader.decodeFromVideoDevice(null, videoRef.current, (result) => {
        if (!active || !result) return;
        active = false;
        reader.reset();
        lookup(result.getText());
      });
    }
    return () => { active = false; reader.reset(); };
  }, [lookup]);

  const reset = () => { setPhase("scanning"); setScanResult(null); setIsbn(""); };

  return (
    <div className="fixed inset-0 z-50 flex flex-col" style={{ background: "#060818" }}>
      <div className="flex items-center justify-between px-5 pt-12 pb-3">
        <button onClick={onClose} className="w-9 h-9 rounded-full flex items-center justify-center" style={{ background: "rgba(255,255,255,0.08)" }}>
          <X className="w-4 h-4 text-white" />
        </button>
        <span className="font-bold text-white">Scanner</span>
        <button onClick={() => setShowManual(!showManual)} className="w-9 h-9 rounded-full flex items-center justify-center" style={{ background: "rgba(255,255,255,0.08)" }}>
          <Keyboard className="w-4 h-4 text-white" />
        </button>
      </div>

      <div className="relative flex items-center justify-center" style={{ height: 200 }}>
        <video ref={videoRef} style={{ width: 280, height: 200, objectFit: "cover", borderRadius: 8 }} />
        <div className="absolute pointer-events-none" style={{ width: 240, height: 140, border: "1.5px solid rgba(91,122,255,0.5)", borderRadius: 8, position: "relative" }}>
          {phase === "scanning" && (
            <div className="scan-line" style={{ position: "absolute", left: 0, right: 0, height: 1.5, background: "linear-gradient(90deg,transparent,#5B7AFF,transparent)" }} />
          )}
        </div>
      </div>

      {showManual && (
        <div className="flex gap-2 px-5 mt-3">
          <input type="text" value={manualISBN} onChange={e => setManualISBN(e.target.value)}
            placeholder="Saisir ISBN manuellement..."
            className="flex-1 px-3 py-2 rounded-xl text-sm outline-none"
            style={{ background: "rgba(255,255,255,0.08)", color: "white", border: "1px solid rgba(91,122,255,0.3)" }}
            onKeyDown={e => e.key === "Enter" && manualISBN && lookup(manualISBN)} />
          <button onClick={() => manualISBN && lookup(manualISBN)} className="px-4 py-2 rounded-xl text-sm font-bold" style={{ background: "var(--accent)", color: "#fff" }}>OK</button>
        </div>
      )}

      <div className="flex-1 rounded-t-3xl mt-4 overflow-y-auto p-5 flex flex-col gap-4" style={{ background: "var(--surface)" }}>

        {phase === "scanning" && (
          <div className="flex flex-col items-center gap-2 py-6">
            <p className="font-semibold" style={{ color: "var(--txt1)" }}>Centrez le code-barres</p>
            <p className="text-sm" style={{ color: "var(--txt3)" }}>ISBN 10 ou 13 — détection automatique</p>
            <p className="text-xs mt-2" style={{ color: "var(--txt3)" }}>Si une BD appartient à une série, la collection sera créée automatiquement</p>
          </div>
        )}

        {phase === "loading" && (
          <div className="flex flex-col items-center gap-3 py-6">
            <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
            <p className="text-sm" style={{ color: "var(--txt2)" }}>Recherche de {isbn}…</p>
          </div>
        )}

        {phase === "not_found" && (
          <div className="flex flex-col items-center gap-4 py-6">
            <p className="font-semibold" style={{ color: "var(--txt1)" }}>{isbn} introuvable</p>
            <p className="text-sm text-center" style={{ color: "var(--txt2)" }}>Non référencé dans Open Library ni Google Books.</p>
            <button onClick={reset} className="flex items-center gap-2 px-5 py-2.5 rounded-xl font-semibold text-sm" style={{ background: "var(--accent)", color: "#fff" }}>
              <RefreshCw className="w-4 h-4" /> Réessayer
            </button>
          </div>
        )}

        {phase === "error" && (
          <div className="flex flex-col items-center gap-3 py-6">
            <p className="font-semibold" style={{ color: "var(--miss-t)" }}>Erreur de connexion</p>
            <button onClick={reset} className="flex items-center gap-2 px-5 py-2.5 rounded-xl font-semibold text-sm" style={{ background: "var(--accent)", color: "#fff" }}>
              <RefreshCw className="w-4 h-4" /> Réessayer
            </button>
          </div>
        )}

        {phase === "confirm" && scanResult && (
          <>
            {scanResult.collection && (
              <div className="rounded-2xl p-3 flex gap-3 items-start"
                style={{ background: scanResult.isNewCollection ? "var(--accent-l)" : "var(--surface2)", border: `1px solid ${scanResult.isNewCollection ? "var(--accent)" : "var(--border)"}` }}>
                {scanResult.collection.cover_url && (
                  <div className="w-10 h-14 rounded-lg overflow-hidden flex-shrink-0" style={{ background: "var(--placeholder)" }}>
                    <img src={scanResult.collection.cover_url} alt="" className="w-full h-full object-cover" />
                  </div>
                )}
                <div className="flex-1">
                  {scanResult.isNewCollection ? (
                    <>
                      <div className="flex items-center gap-1.5 mb-1">
                        <Plus className="w-3.5 h-3.5" style={{ color: "var(--accent)" }} />
                        <span className="text-xs font-bold" style={{ color: "var(--accent)" }}>Collection créée automatiquement</span>
                      </div>
                      <p className="text-sm font-bold" style={{ color: "var(--txt1)" }}>{scanResult.collection.name}</p>
                      <p className="text-xs mt-0.5" style={{ color: "var(--txt2)" }}>Tome {scanResult.book.series_index} · {scanResult.collection.book_type}</p>
                    </>
                  ) : scanResult.isNewVolume ? (
                    <>
                      <div className="flex items-center gap-1.5 mb-1">
                        <Check className="w-3.5 h-3.5" style={{ color: "var(--have-t)" }} />
                        <span className="text-xs font-bold" style={{ color: "var(--have-t)" }}>Tome manquant trouvé !</span>
                      </div>
                      <p className="text-sm font-bold" style={{ color: "var(--txt1)" }}>{scanResult.collection.name}</p>
                      <p className="text-xs mt-0.5" style={{ color: "var(--txt2)" }}>
                        Tome {scanResult.book.series_index} · {scanResult.collection.owned_volumes.length}/{scanResult.collection.total_volumes ?? "?"} possédés
                      </p>
                      {scanResult.collection.total_volumes && scanResult.collection.total_volumes <= 20 && (
                        <div className="flex flex-wrap gap-1 mt-2">
                          {Array.from({ length: scanResult.collection.total_volumes }, (_, i) => i + 1).map(n => {
                            const isNew = n === scanResult.book.series_index;
                            const have = scanResult.collection!.owned_volumes.includes(n);
                            return (
                              <div key={n} style={{ width: 20, height: 20, borderRadius: 4, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 8, fontWeight: 700,
                                ...(isNew ? { background: "var(--accent)", color: "#fff" } : have ? { background: "var(--have-bg)", color: "var(--have-t)", border: "1px solid var(--have-b)" } : { background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px dashed var(--miss-b)" }) }}>
                                {n}
                              </div>
                            );
                          })}
                        </div>
                      )}
                    </>
                  ) : (
                    <p className="text-sm" style={{ color: "var(--txt2)" }}>Ce tome est déjà dans votre collection.</p>
                  )}
                </div>
              </div>
            )}

            <div className="flex gap-3 p-3 rounded-2xl" style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
              <div className="w-14 h-20 rounded-xl overflow-hidden flex-shrink-0 flex items-center justify-center shadow" style={{ background: "var(--placeholder)" }}>
                {scanResult.book.cover_url ? <img src={scanResult.book.cover_url} alt="" className="w-full h-full object-cover" /> : <BookOpen className="w-6 h-6" style={{ color: "var(--txt3)" }} />}
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-bold text-sm leading-tight" style={{ color: "var(--txt1)" }}>{scanResult.book.title}</p>
                <p className="text-xs mt-1" style={{ color: "var(--txt2)" }}>{scanResult.book.authors.join(", ")}</p>
                {scanResult.book.series_name && <p className="text-xs mt-1 font-semibold" style={{ color: "var(--accent)" }}>{scanResult.book.series_name} #{scanResult.book.series_index}</p>}
                <p className="text-xs mt-0.5 font-mono" style={{ color: "var(--txt3)" }}>ISBN {scanResult.book.isbn}</p>
              </div>
            </div>

            <div>
              <label className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--txt3)" }}>Type</label>
              <div className="flex gap-2 mt-1.5">
                {(["livre","bd","manga"] as BookType[]).map(t => (
                  <button key={t} onClick={() => setBookType(t)} className="flex-1 py-2 rounded-xl text-sm font-semibold"
                    style={{ background: bookType === t ? "var(--accent)" : "var(--surface2)", color: bookType === t ? "#fff" : "var(--txt2)", border: `1px solid ${bookType === t ? "var(--accent)" : "var(--border)"}` }}>
                    {t === "livre" ? "📖 Livre" : t === "bd" ? "🎨 BD" : "⛩️ Manga"}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--txt3)" }}>Statut</label>
              <div className="flex gap-2 mt-1.5">
                {(["a_lire","en_cours","lu"] as ReadStatus[]).map(s => (
                  <button key={s} onClick={() => setStatus(s)} className="flex-1 py-2 rounded-xl text-xs font-semibold"
                    style={{ background: status === s ? "var(--accent)" : "var(--surface2)", color: status === s ? "#fff" : "var(--txt2)", border: `1px solid ${status === s ? "var(--accent)" : "var(--border)"}` }}>
                    {s === "a_lire" ? "📌 À lire" : s === "en_cours" ? "📖 En cours" : "✅ Lu"}
                  </button>
                ))}
              </div>
            </div>

            <button onClick={() => onSuccess(scanResult, status, bookType)}
              className="w-full py-4 rounded-2xl font-bold text-sm flex items-center justify-center gap-2 active:scale-95"
              style={{ background: "var(--accent)", color: "#fff" }}>
              <Check className="w-5 h-5" /> Ajouter à ma bibliothèque
            </button>
          </>
        )}
      </div>
    </div>
  );
}
