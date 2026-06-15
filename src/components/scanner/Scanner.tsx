"use client";
import { useEffect, useRef, useState, useCallback } from "react";
import { BrowserMultiFormatReader } from "@zxing/library";
import { X, Keyboard, Check, Plus, RefreshCw } from "lucide-react";
import { ScanResult, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";

type Phase = "scanning" | "loading" | "confirm" | "not_found" | "error";

interface Props {
  rapidMode: boolean;
  onSuccess: (result: ScanResult, status: ReadStatus, bookType: BookType) => void;
  onClose: () => void;
}

export default function Scanner({ rapidMode, onSuccess, onClose }: Props) {
  const videoRef    = useRef<HTMLVideoElement>(null);
  const readerRef   = useRef<BrowserMultiFormatReader | null>(null);
  const processingRef = useRef(false); // prevents duplicate scan processing

  const [phase,      setPhase]      = useState<Phase>("scanning");
  const [isbn,       setIsbn]       = useState("");
  const [result,     setResult]     = useState<ScanResult | null>(null);
  const [status,     setStatus]     = useState<ReadStatus>("a_lire");
  const [bookType,   setBookType]   = useState<BookType>("livre");
  const [manual,     setManual]     = useState("");
  const [showManual, setShowManual] = useState(false);

  // ── Camera: start once, never stop ───────────────────────────────────────
  useEffect(() => {
    const reader = new BrowserMultiFormatReader();
    readerRef.current = reader;

    // Request camera once and reuse — browser won't re-prompt if already granted
    reader.decodeFromVideoDevice(null, videoRef.current!, (r) => {
      if (!r || processingRef.current) return;
      processingRef.current = true;
      lookup(r.getText());
    });

    return () => reader.reset();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Lookup ────────────────────────────────────────────────────────────────
  const lookup = useCallback(async (code: string) => {
    setIsbn(code);
    setPhase("loading");

    try {
      const res  = await fetch(`/api/books/lookup?isbn=${code}&library_id=lib1`);
      if (!res.ok) {
        setPhase("not_found");
        processingRef.current = false; // unblock scanner
        return;
      }
      const data: ScanResult = await res.json();
      setResult(data);
      setBookType(data.book.book_type);

      if (rapidMode) {
        await saveBook(data, "a_lire", data.book.book_type);
        // Reset panel immediately — scanner already running
        setPhase("scanning");
        setResult(null);
        setIsbn("");
        processingRef.current = false;
      } else {
        setPhase("confirm");
        // In classic mode: unblock scanner so user can scan while reading the panel
        processingRef.current = false;
      }
    } catch {
      setPhase("error");
      processingRef.current = false;
    }
  }, [rapidMode]); // eslint-disable-line react-hooks/exhaustive-deps

  const saveBook = async (r: ScanResult, s: ReadStatus, bt: BookType) => {
    await fetch("/api/books/add", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...r.book, book_type: bt, status: s, library_id: "lib1", added_by: "u1" }),
    });
    onSuccess(r, s, bt);
  };

  const reset = () => {
    setPhase("scanning");
    setResult(null);
    setIsbn("");
    processingRef.current = false;
  };

  const handleConfirm = async () => {
    if (!result) return;
    await saveBook(result, status, bookType);
    reset();
  };

  return (
    // overflow-hidden + fixed height = no scroll possible
    <div className="fixed inset-0 z-50 flex flex-col overflow-hidden" style={{ background: "#060818" }}>

      {/* ── Top bar ─────────────────────────────────────────────────────── */}
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

      {/* ── Camera — fills remaining space, never stops ──────────────────── */}
      <div className="flex-1 flex items-center justify-center relative min-h-0">
        <div className="relative">
          {/* Video always running */}
          <video
            ref={videoRef}
            style={{ width: 300, height: 220, objectFit: "cover", borderRadius: 12, display: "block" }}
          />

          {/* Frame corners */}
          <div className="absolute inset-0 pointer-events-none">
            {CORNERS.map((s, i) => <div key={i} className="absolute" style={{ width: 20, height: 20, ...s }} />)}
            {/* Scan line always visible */}
            <div className="scan-line absolute left-0 right-0"
              style={{ height: 2, background: "linear-gradient(90deg,transparent,#5B7AFF,transparent)" }} />
          </div>

          {/* Subtle loading indicator — doesn't block the video */}
          {phase === "loading" && (
            <div className="absolute top-2 right-2">
              <div className="w-5 h-5 rounded-full border-2 animate-spin"
                style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
            </div>
          )}
        </div>
      </div>

      {/* ── Manual ISBN ─────────────────────────────────────────────────── */}
      {showManual && (
        <div className="flex gap-2 px-5 mb-2 flex-shrink-0">
          <input
            type="text"
            value={manual}
            onChange={e => setManual(e.target.value)}
            placeholder="Saisir ISBN..."
            onKeyDown={e => { if (e.key === "Enter" && manual) { processingRef.current = true; lookup(manual); } }}
            className="flex-1 px-4 py-3 rounded-2xl outline-none"
            style={{ background: "rgba(255,255,255,0.08)", color: "white", border: "1px solid rgba(91,122,255,0.3)", fontSize: 15 }}
          />
          <button onClick={() => { if (manual) { processingRef.current = true; lookup(manual); } }}
            className="px-5 py-3 rounded-2xl font-bold"
            style={{ background: "var(--accent)", color: "#fff" }}>
            OK
          </button>
        </div>
      )}

      {/* ── Bottom panel — fixed height, no scroll ──────────────────────── */}
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

        {(phase === "not_found" || phase === "error") && (
          <div className="flex items-center justify-between gap-3 py-1">
            <p style={{ fontSize: 14, color: phase === "error" ? "var(--miss-t)" : "var(--txt1)" }}>
              {phase === "error" ? "Erreur de connexion" : `Introuvable — ${isbn}`}
            </p>
            <Button onClick={reset} size="sm" variant="secondary">
              <RefreshCw className="w-4 h-4" /> OK
            </Button>
          </div>
        )}

        {phase === "confirm" && result && (
          <>
            {/* Collection badge */}
            {result.collection && (
              <div className="flex items-center gap-2 px-3 py-2 rounded-xl flex-shrink-0"
                style={{ background: result.isNewCollection ? "var(--accent-l)" : "var(--have-bg)", border: `1px solid ${result.isNewCollection ? "var(--border)" : "var(--have-b)"}` }}>
                {result.isNewCollection
                  ? <Plus className="w-4 h-4 flex-shrink-0" style={{ color: "var(--accent)" }} />
                  : <Check className="w-4 h-4 flex-shrink-0" style={{ color: "var(--have-t)" }} />}
                <p className="truncate" style={{ fontSize: 13, fontWeight: 600, color: result.isNewCollection ? "var(--accent)" : "var(--have-t)" }}>
                  {result.isNewCollection ? `Collection « ${result.collection.name} » créée` : `Tome ${result.book.series_index} → ${result.collection.name}`}
                </p>
              </div>
            )}

            {/* Book preview */}
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

            {/* Status */}
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

// ── Frame corners ─────────────────────────────────────────────────────────────
const CORNERS = [
  { top: -2,    left: -2,  borderTop:    "3px solid #5B7AFF", borderLeft:   "3px solid #5B7AFF", borderRadius: "6px 0 0 0" },
  { top: -2,    right: -2, borderTop:    "3px solid #5B7AFF", borderRight:  "3px solid #5B7AFF", borderRadius: "0 6px 0 0" },
  { bottom: -2, left: -2,  borderBottom: "3px solid #5B7AFF", borderLeft:   "3px solid #5B7AFF", borderRadius: "0 0 0 6px" },
  { bottom: -2, right: -2, borderBottom: "3px solid #5B7AFF", borderRight:  "3px solid #5B7AFF", borderRadius: "0 0 6px 0" },
];
