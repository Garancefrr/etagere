"use client";
import { useEffect, useRef, useState, useCallback } from "react";
import { BrowserMultiFormatReader } from "@zxing/library";
import { X, Keyboard, RefreshCw, Check, Plus, BookOpen } from "lucide-react";
import { ScanResult, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";

type Phase = "scanning" | "loading" | "confirm" | "not_found" | "error";

interface Props {
  rapidMode: boolean;
  onSuccess: (result: ScanResult, status: ReadStatus, bookType: BookType) => void;
  onClose: () => void;
}

export default function Scanner({ rapidMode, onSuccess, onClose }: Props) {
  const videoRef  = useRef<HTMLVideoElement>(null);
  const readerRef = useRef<BrowserMultiFormatReader | null>(null);

  const [phase,      setPhase]      = useState<Phase>("scanning");
  const [isbn,       setIsbn]       = useState("");
  const [result,     setResult]     = useState<ScanResult | null>(null);
  const [status,     setStatus]     = useState<ReadStatus>("a_lire");
  const [bookType,   setBookType]   = useState<BookType>("livre");
  const [manual,     setManual]     = useState("");
  const [showManual, setShowManual] = useState(false);

  const addBook = useCallback(async (r: ScanResult, s: ReadStatus, bt: BookType) => {
    await fetch("/api/books/add", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...r.book, book_type: bt, status: s, library_id: "lib1", added_by: "u1" }),
    });
    onSuccess(r, s, bt);
  }, [onSuccess]);

  const lookup = useCallback(async (code: string) => {
    setIsbn(code);
    setPhase("loading");
    try {
      const res = await fetch(`/api/books/lookup?isbn=${code}&library_id=lib1`);
      if (!res.ok) { setPhase("not_found"); return; }
      const data: ScanResult = await res.json();
      setResult(data);
      setBookType(data.book.book_type);
      if (rapidMode) {
        await addBook(data, "a_lire", data.book.book_type);
        setPhase("scanning");
        setResult(null);
        setIsbn("");
        startReader();
      } else {
        setPhase("confirm");
      }
    } catch {
      setPhase("error");
    }
  }, [rapidMode, addBook]);

  const startReader = useCallback(() => {
    const reader = new BrowserMultiFormatReader();
    readerRef.current = reader;
    let active = true;
    reader.decodeFromVideoDevice(null, videoRef.current!, (r) => {
      if (!active || !r) return;
      active = false;
      reader.reset();
      lookup(r.getText());
    });
    return () => { active = false; reader.reset(); };
  }, [lookup]);

  useEffect(() => startReader(), [startReader]);

  const reset = () => {
    setPhase("scanning");
    setResult(null);
    setIsbn("");
    readerRef.current?.reset();
    startReader();
  };

  return (
    <div className="fixed inset-0 z-50 flex flex-col" style={{ background: "#060818" }}>
      {/* Top bar */}
      <div className="flex items-center justify-between px-5 pt-12 pb-2">
        <button onClick={onClose} className="w-10 h-10 rounded-full flex items-center justify-center"
          style={{ background: "rgba(255,255,255,0.08)" }}>
          <X className="w-5 h-5 text-white" />
        </button>
        <span className="font-bold text-white" style={{ fontSize: 16 }}>
          {rapidMode ? "⚡ Mode rapide" : "Scanner"}
        </span>
        <button onClick={() => setShowManual(v => !v)} className="w-10 h-10 rounded-full flex items-center justify-center"
          style={{ background: "rgba(255,255,255,0.08)" }}>
          <Keyboard className="w-5 h-5 text-white" />
        </button>
      </div>

      {rapidMode && (
        <div className="mx-5 mb-2 px-3 py-2 rounded-xl flex items-center gap-2"
          style={{ background: "rgba(59,91,255,0.18)", border: "1px solid rgba(91,122,255,0.3)" }}>
          <span style={{ fontSize: 12, color: "#7B80FF" }}>Ajout automatique à chaque scan</span>
        </div>
      )}

      {/* Viewfinder */}
      <div className="flex-1 flex items-center justify-center">
        <div className="relative">
          <video ref={videoRef} style={{ width: 300, height: 220, objectFit: "cover", borderRadius: 12 }} />
          <ScanFrame active={phase === "scanning"} />
        </div>
      </div>

      {/* Manual input */}
      {showManual && (
        <div className="flex gap-2 px-5 mb-3">
          <input
            type="text"
            value={manual}
            onChange={e => setManual(e.target.value)}
            placeholder="Saisir ISBN..."
            onKeyDown={e => e.key === "Enter" && manual && lookup(manual)}
            className="flex-1 px-4 py-3 rounded-2xl outline-none"
            style={{ background: "rgba(255,255,255,0.08)", color: "white", border: "1px solid rgba(91,122,255,0.3)", fontSize: 15 }}
          />
          <button onClick={() => manual && lookup(manual)} className="px-5 py-3 rounded-2xl font-bold"
            style={{ background: "var(--accent)", color: "#fff", fontSize: 14 }}>
            OK
          </button>
        </div>
      )}

      {/* Bottom panel */}
      <div className="rounded-t-3xl p-5 flex flex-col gap-4" style={{ background: "var(--surface)", minHeight: rapidMode ? 80 : 240 }}>
        <PhaseFeedback phase={phase} isbn={isbn} result={result} status={status} bookType={bookType}
          onStatusChange={setStatus} onTypeChange={setBookType}
          onConfirm={() => result && addBook(result, status, bookType)}
          onReset={reset} />
      </div>
    </div>
  );
}

// ── Sub-components ────────────────────────────────────────────────────────────

function ScanFrame({ active }: { active: boolean }) {
  const corners = [
    { top: -2, left: -2,  borderTop: "3px solid #5B7AFF", borderLeft:  "3px solid #5B7AFF", borderRadius: "6px 0 0 0" },
    { top: -2, right: -2, borderTop: "3px solid #5B7AFF", borderRight: "3px solid #5B7AFF", borderRadius: "0 6px 0 0" },
    { bottom: -2, left: -2,  borderBottom: "3px solid #5B7AFF", borderLeft:  "3px solid #5B7AFF", borderRadius: "0 0 0 6px" },
    { bottom: -2, right: -2, borderBottom: "3px solid #5B7AFF", borderRight: "3px solid #5B7AFF", borderRadius: "0 0 6px 0" },
  ];
  return (
    <div className="absolute inset-0 pointer-events-none">
      {corners.map((s, i) => <div key={i} className="absolute" style={{ width: 20, height: 20, ...s }} />)}
      {active && (
        <div className="scan-line absolute left-0 right-0"
          style={{ height: 2, background: "linear-gradient(90deg,transparent,#5B7AFF,transparent)" }} />
      )}
    </div>
  );
}

function PhaseFeedback({ phase, isbn, result, status, bookType, onStatusChange, onTypeChange, onConfirm, onReset }: {
  phase: Phase; isbn: string; result: ScanResult | null;
  status: ReadStatus; bookType: BookType;
  onStatusChange: (s: ReadStatus) => void;
  onTypeChange: (t: BookType) => void;
  onConfirm: () => void; onReset: () => void;
}) {
  if (phase === "scanning") return (
    <p className="text-center py-4" style={{ fontSize: 14, color: "var(--txt2)" }}>
      Centrez le code-barres dans le cadre
    </p>
  );

  if (phase === "loading") return (
    <div className="flex items-center justify-center gap-3 py-4">
      <div className="w-6 h-6 rounded-full border-2 animate-spin"
        style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
      <p style={{ fontSize: 14, color: "var(--txt2)" }}>Recherche de {isbn}…</p>
    </div>
  );

  if (phase === "not_found" || phase === "error") return (
    <div className="flex flex-col items-center gap-3 py-2">
      <p className="font-semibold" style={{ fontSize: 15, color: phase === "error" ? "var(--miss-t)" : "var(--txt1)" }}>
        {phase === "error" ? "Erreur de connexion" : `Introuvable — ${isbn}`}
      </p>
      <Button onClick={onReset}><RefreshCw className="w-4 h-4" /> Réessayer</Button>
    </div>
  );

  if (phase === "confirm" && result) return (
    <>
      {/* Collection notification */}
      {result.collection && (
        <div className="flex items-center gap-2 px-3 py-2 rounded-xl"
          style={{ background: result.isNewCollection ? "var(--accent-l)" : "var(--have-bg)", border: `1px solid ${result.isNewCollection ? "var(--border)" : "var(--have-b)"}` }}>
          {result.isNewCollection
            ? <Plus className="w-4 h-4 flex-shrink-0" style={{ color: "var(--accent)" }} />
            : <Check className="w-4 h-4 flex-shrink-0" style={{ color: "var(--have-t)" }} />}
          <p style={{ fontSize: 13, fontWeight: 600, color: result.isNewCollection ? "var(--accent)" : "var(--have-t)" }}>
            {result.isNewCollection
              ? `Collection « ${result.collection.name} » créée`
              : `Tome ${result.book.series_index} → ${result.collection.name}`}
          </p>
        </div>
      )}

      {/* Book preview */}
      <div className="flex gap-3 p-3 rounded-2xl" style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
        <Cover src={result.book.cover_url} alt={result.book.title} width={52} height={72} className="rounded-xl flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <p className="font-bold" style={{ fontSize: 15, color: "var(--txt1)", lineHeight: 1.3 }}>{result.book.title}</p>
          <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{result.book.authors.join(", ")}</p>
          {result.book.series_name && (
            <p style={{ fontSize: 12, color: "var(--accent)", marginTop: 2 }}>
              {result.book.series_name} #{result.book.series_index}
            </p>
          )}
        </div>
      </div>

      {/* Type */}
      <div className="flex gap-2">
        {(Object.entries(TYPE_CONFIG) as [BookType, { label: string; emoji: string }][]).map(([v, { emoji, label }]) => (
          <button key={v} onClick={() => onTypeChange(v)}
            className="flex-1 py-2.5 rounded-xl font-semibold"
            style={{ fontSize: 13, background: bookType === v ? "var(--accent)" : "var(--surface2)", color: bookType === v ? "#fff" : "var(--txt2)", border: `1px solid ${bookType === v ? "var(--accent)" : "var(--border)"}` }}>
            {emoji} {label}
          </button>
        ))}
      </div>

      {/* Status */}
      <div className="flex gap-2">
        {(Object.entries(STATUS_CONFIG) as [ReadStatus, { emoji: string; label: string }][]).map(([v, { emoji, label }]) => (
          <button key={v} onClick={() => onStatusChange(v)}
            className="flex-1 py-2.5 rounded-xl font-semibold"
            style={{ fontSize: 13, background: status === v ? "var(--accent)" : "var(--surface2)", color: status === v ? "#fff" : "var(--txt2)", border: `1px solid ${status === v ? "var(--accent)" : "var(--border)"}` }}>
            {emoji} {label}
          </button>
        ))}
      </div>

      <Button onClick={onConfirm} className="w-full py-4 rounded-2xl" style={{ fontSize: 15 }}>
        <Check className="w-5 h-5" /> Ajouter à ma bibliothèque
      </Button>
    </>
  );

  return null;
}
