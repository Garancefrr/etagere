#!/bin/bash
set -e
echo "🔧 Fix cohérence scan + toast + ISBN lookup..."
cd "$(git rev-parse --show-toplevel)"
cat > "src/lib/isbn-lookup.ts" << 'FILEOF'
import { LookupResult, BookType } from "@/types";

// ── Type detection ─────────────────────────────────────────────────────────────

function detectType(terms: string): BookType {
  const t = terms.toLowerCase();
  if (/manga|manhwa|shonen|shojo|seinen|josei|kodansha|shueisha|viz|one.piece|naruto|dragon.ball/.test(t)) return "manga";
  if (/bande.dessin|bd|comics|dargaud|dupuis|lombard|casterman|lucky|schtroumpf|ast[eé]rix|tintin|spirou|blake|mortimer/.test(t)) return "bd";
  return "livre";
}

// ── Series extraction from title ──────────────────────────────────────────────

function extractSeries(title: string): { seriesName?: string; seriesIndex?: number } {
  const patterns = [
    /^(.+?)\s*[-–—]\s*(?:tome|t\.?|vol(?:ume)?\.?|#)\s*(\d+)/i,
    /^(.+?)\s*,\s*(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i,
    /^(.+?)\s+(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i,
    /^(.+?)\s*\((?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)\)/i,
  ];
  for (const re of patterns) {
    const m = title.match(re);
    if (m && parseInt(m[2]) <= 200) {
      const name = m[1]
        .replace(/^(les|la|le|l'|the)\s+/i, "")
        .replace(/\s+$/, "")
        .trim();
      return { seriesName: name || undefined, seriesIndex: parseInt(m[2]) };
    }
  }
  return {};
}

// ── BnF SRU API — covers all French/Belgian EAN codes ────────────────────────

async function fromBnF(code: string): Promise<LookupResult | null> {
  try {
    const url = `https://catalogue.bnf.fr/api/SRU?version=1.2&operation=searchRetrieve&query=bib.ean+adj+"${code}"&recordSchema=unimarcxchange&maximumRecords=1`;
    const res  = await fetch(url, { signal: AbortSignal.timeout(6000) });
    const text = await res.text();

    if (!text.includes("<numberOfRecords>") || text.includes("<numberOfRecords>0")) return null;

    // Title: UNIMARC 200$a + 200$e (subtitle)
    const titleA = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
    const titleE = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="e">([^<]+)/)?.[1]?.trim();
    if (!titleA) return null;
    const title = titleE ? `${titleA} — ${titleE}` : titleA;

    // Volume number: UNIMARC 200$h
    const volStr  = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="h">([^<]+)/)?.[1]?.trim();
    const volNum  = volStr ? parseInt(volStr.replace(/\D/g, "")) : undefined;

    // Series: UNIMARC 225$a
    const seriesRaw = text.match(/<datafield tag="225"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
    const seriesVol = text.match(/<datafield tag="225"[^>]*>[\s\S]*?<subfield code="v">([^<]+)/)?.[1]?.trim();

    // Author: UNIMARC 700$a + 700$b
    const authorB = text.match(/<datafield tag="700"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
    const authorF = text.match(/<datafield tag="700"[^>]*>[\s\S]*?<subfield code="b">([^<]+)/)?.[1]?.trim();
    const author  = authorB ? [authorF ? `${authorF} ${authorB}` : authorB] : [];

    // Publisher: UNIMARC 210$c
    const publisher = text.match(/<datafield tag="210"[^>]*>[\s\S]*?<subfield code="c">([^<]+)/)?.[1]?.trim();

    // Year: UNIMARC 210$d
    const yearStr = text.match(/<datafield tag="210"[^>]*>[\s\S]*?<subfield code="d">(\d{4})/)?.[1];
    const year    = yearStr ? parseInt(yearStr) : undefined;

    // Genre/subject for type detection
    const subjects = text.match(/<subfield code="a">([^<]+)/g)?.join(" ") ?? "";

    // Series resolution
    let seriesName  = seriesRaw?.replace(/\s*#?\d+.*$/, "").trim();
    let seriesIndex = seriesVol ? parseInt(seriesVol.replace(/\D/g, "")) : volNum;

    // Fallback: parse series from title
    if (!seriesName) {
      const parsed = extractSeries(title);
      seriesName  = parsed.seriesName;
      seriesIndex = parsed.seriesIndex ?? seriesIndex;
    }

    const book_type = detectType(subjects + " " + title + " " + (publisher ?? "") + " " + (seriesName ?? ""));

    return {
      isbn: code,
      title,
      authors: author,
      cover_url: `https://catalogue.bnf.fr/couverture?&isbn=${code}&notoile=1`,
      publisher,
      published_year: year,
      series_name: seriesName,
      series_index: seriesIndex,
      book_type,
    };
  } catch {
    return null;
  }
}

// ── Open Library ──────────────────────────────────────────────────────────────

async function fromOpenLibrary(isbn: string): Promise<LookupResult | null> {
  try {
    const res  = await fetch(`https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`, { signal: AbortSignal.timeout(5000) });
    const data = await res.json();
    const b    = data[`ISBN:${isbn}`];
    if (!b?.title) return null;

    const subjects   = (b.subjects ?? []).map((s: any) => typeof s === "string" ? s : s.name ?? "").join(" ").toLowerCase();
    const series     = Array.isArray(b.series) ? b.series[0] : b.series;
    const numMatch   = typeof series === "string" ? series.match(/#?(\d+)/) : null;
    const { seriesName: parsedName, seriesIndex: parsedIdx } = extractSeries(b.title);

    return {
      isbn,
      title:          b.title,
      authors:        (b.authors ?? []).map((a: any) => a.name),
      cover_url:      b.cover?.large ?? b.cover?.medium ?? b.cover?.small,
      publisher:      b.publishers?.[0]?.name,
      published_year: b.publish_date ? parseInt(b.publish_date.slice(-4)) : undefined,
      page_count:     b.number_of_pages,
      description:    b.excerpts?.[0]?.text,
      series_name:    (typeof series === "string" ? series.replace(/\s*#?\d+.*$/, "").trim() || undefined : undefined) ?? parsedName,
      series_index:   numMatch ? parseInt(numMatch[1]) : parsedIdx,
      book_type:      detectType(subjects + " " + b.title),
    };
  } catch {
    return null;
  }
}

// ── Google Books ──────────────────────────────────────────────────────────────

async function fromGoogleBooks(isbn: string): Promise<LookupResult | null> {
  try {
    const res  = await fetch(`https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}`, { signal: AbortSignal.timeout(5000) });
    const data = await res.json();
    const vol  = data.items?.[0]?.volumeInfo;
    if (!vol?.title) return null;

    const categories = (vol.categories ?? []).join(" ").toLowerCase();
    const fullTitle  = `${vol.title} ${vol.subtitle ?? ""}`.trim();
    const { seriesName, seriesIndex } = extractSeries(fullTitle);

    return {
      isbn,
      title:          vol.title,
      authors:        vol.authors ?? [],
      cover_url:      vol.imageLinks?.thumbnail?.replace("http:", "https:").replace("zoom=1", "zoom=3").replace("&edge=curl", ""),
      publisher:      vol.publisher,
      published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : undefined,
      page_count:     vol.pageCount,
      description:    vol.description,
      series_name:    seriesName,
      series_index:   seriesIndex,
      book_type:      detectType(categories + " " + fullTitle),
    };
  } catch {
    return null;
  }
}

// ── Main lookup ───────────────────────────────────────────────────────────────
// Strategy:
// 1. BnF first — best coverage for ALL French/European EAN codes (books, BD, manga)
// 2. Open Library — good for international ISBN
// 3. Google Books — good fallback with cover images
// 4. Title-based series extraction as last resort

export async function lookupISBN(code: string): Promise<LookupResult | null> {
  const clean = code.replace(/[-\s]/g, "");

  // Try BnF first for all EAN-13 codes (European standard)
  // EAN-13 = 13 digits. ISBN-13 = subset of EAN-13 starting with 978/979
  const isEAN13 = /^\d{13}$/.test(clean);

  if (isEAN13) {
    const bnf = await fromBnF(clean);
    if (bnf?.title) return bnf;
  }

  // Open Library
  const ol = await fromOpenLibrary(clean);
  if (ol?.title) return ol;

  // Google Books
  const gb = await fromGoogleBooks(clean);
  if (gb?.title) return gb;

  // BnF as last resort (for non-EAN13 or if already tried above)
  if (!isEAN13) {
    const bnf = await fromBnF(clean);
    if (bnf?.title) return bnf;
  }

  return null;
}
FILEOF
cat > "src/components/scanner/Scanner.tsx" << 'FILEOF'
"use client";
import { useEffect, useRef, useState, useCallback } from "react";
import { BrowserMultiFormatReader } from "@zxing/library";
import { X, Keyboard, Check, Plus, RefreshCw } from "lucide-react";
import { ScanResult, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";

// ── Types ─────────────────────────────────────────────────────────────────────

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
  onSuccess: (saved: SavedBook) => void;
  onClose: () => void;
}

// ── Frame corners ─────────────────────────────────────────────────────────────

const CORNERS = [
  { top: -2,    left: -2,  borderTop: "3px solid",    borderLeft: "3px solid",  borderRadius: "6px 0 0 0" },
  { top: -2,    right: -2, borderTop: "3px solid",    borderRight: "3px solid", borderRadius: "0 6px 0 0" },
  { bottom: -2, left: -2,  borderBottom: "3px solid", borderLeft: "3px solid",  borderRadius: "0 0 0 6px" },
  { bottom: -2, right: -2, borderBottom: "3px solid", borderRight: "3px solid", borderRadius: "0 0 6px 0" },
];

// ── Component ─────────────────────────────────────────────────────────────────

export default function Scanner({ rapidMode, libraryId, userEmail, onSuccess, onClose }: Props) {
  const videoRef      = useRef<HTMLVideoElement>(null);
  const processingRef = useRef(false);

  const [phase,    setPhase]    = useState<Phase>("scanning");
  const [isbn,     setIsbn]     = useState("");
  const [result,   setResult]   = useState<ScanResult | null>(null);
  const [status,   setStatus]   = useState<ReadStatus>("a_lire");
  const [bookType, setBookType] = useState<BookType>("livre");
  const [manual,   setManual]   = useState("");
  const [showKbd,  setShowKbd]  = useState(false);

  // Frame color reflects current phase
  const frameColor =
    phase === "success"                        ? "#22C55E" :
    phase === "not_found" || phase === "error" ? "#EF4444" :
    "#5B7AFF";

  // ── Camera: start once, never stop ─────────────────────────────────────────
  useEffect(() => {
    const reader = new BrowserMultiFormatReader();
    reader.decodeFromVideoDevice(null, videoRef.current!, (r) => {
      if (!r || processingRef.current) return;
      processingRef.current = true;
      doLookup(r.getText());
    });
    return () => reader.reset();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Lookup ──────────────────────────────────────────────────────────────────
  const doLookup = useCallback(async (code: string) => {
    setIsbn(code);
    setPhase("loading");

    try {
      const res = await fetch(
        `/api/books/lookup?isbn=${encodeURIComponent(code)}&library_id=${libraryId}`
      );

      if (!res.ok) {
        setPhase("not_found");
        processingRef.current = false;
        return;
      }

      const data: ScanResult = await res.json();
      setResult(data);
      setBookType(data.book.book_type);

      if (rapidMode) {
        // In rapid mode: save immediately without confirmation
        const saved = await doSave(data, "a_lire", data.book.book_type);
        if (saved) {
          setPhase("success");
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
        // Classic mode: show confirmation panel
        setPhase("confirm");
        processingRef.current = false;
      }
    } catch {
      setPhase("error");
      processingRef.current = false;
    }
  }, [rapidMode, libraryId]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Save ────────────────────────────────────────────────────────────────────
  // Returns the saved book data (from DB response) or null on failure
  const doSave = async (
    r: ScanResult,
    s: ReadStatus,
    bt: BookType
  ): Promise<SavedBook | null> => {
    try {
      const res = await fetch("/api/books/add", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          isbn:           r.book.isbn,
          title:          r.book.title,
          authors:        r.book.authors,
          cover_url:      r.book.cover_url,
          publisher:      r.book.publisher,
          published_year: r.book.published_year,
          page_count:     r.book.page_count,
          description:    r.book.description,
          book_type:      bt,
          status:         s,
          series_name:    r.book.series_name,
          series_index:   r.book.series_index,
          collection_id:  r.collection?.id,
          library_id:     libraryId,
          email:          userEmail,
        }),
      });

      if (!res.ok) {
        const e = await res.json();
        console.error("doSave error:", e);
        return null;
      }

      // Use the actual saved book title from DB response (not lookup title)
      const saved = await res.json();
      const result: SavedBook = {
        title:            saved.title ?? r.book.title,
        collection_name:  r.collection?.name,
        is_new_collection: r.isNewCollection,
      };
      onSuccess(result);
      return result;
    } catch (e) {
      console.error("doSave exception:", e);
      return null;
    }
  };

  // ── Handlers ────────────────────────────────────────────────────────────────

  const handleConfirm = async () => {
    if (!result) return;
    setPhase("saving");
    const saved = await doSave(result, status, bookType);
    if (saved) {
      setPhase("success");
      setTimeout(() => { reset(); onClose(); }, 600);
    } else {
      setPhase("error");
    }
  };

  const reset = () => {
    setPhase("scanning");
    setResult(null);
    setIsbn("");
    processingRef.current = false;
  };

  const handleManual = () => {
    if (!manual.trim()) return;
    processingRef.current = true;
    doLookup(manual.trim());
  };

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
          {rapidMode ? "⚡ Mode rapide" : "Scanner"}
        </span>
        <button onClick={() => setShowKbd(v => !v)} className="w-10 h-10 rounded-full flex items-center justify-center"
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

      {/* Camera — always running */}
      <div className="flex-1 flex items-center justify-center relative min-h-0">
        <div className="relative">
          <video ref={videoRef}
            style={{ width: 300, height: 220, objectFit: "cover", borderRadius: 12, display: "block" }} />

          {/* Animated frame */}
          <div className="absolute inset-0 pointer-events-none">
            {CORNERS.map((s, i) => (
              <div key={i} className="absolute" style={{
                width: 20, height: 20, ...s,
                borderTopColor:    s.borderTop    ? frameColor : undefined,
                borderBottomColor: s.borderBottom ? frameColor : undefined,
                borderLeftColor:   s.borderLeft   ? frameColor : undefined,
                borderRightColor:  s.borderRight  ? frameColor : undefined,
                transition: "border-color 0.3s",
              }} />
            ))}

            {/* Scan line */}
            {(phase === "scanning" || phase === "loading") && (
              <div className="scan-line absolute left-0 right-0"
                style={{ height: 2, background: `linear-gradient(90deg,transparent,${frameColor},transparent)` }} />
            )}

            {/* Success overlay */}
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

          {/* Loading spinner */}
          {(phase === "loading" || phase === "saving") && (
            <div className="absolute top-2 right-2">
              <div className="w-5 h-5 rounded-full border-2 animate-spin"
                style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
            </div>
          )}
        </div>
      </div>

      {/* Manual ISBN input */}
      {showKbd && (
        <div className="flex gap-2 px-5 mb-2 flex-shrink-0">
          <input
            type="text" value={manual} onChange={e => setManual(e.target.value)}
            placeholder="Saisir ISBN ou EAN..."
            onKeyDown={e => e.key === "Enter" && handleManual()}
            className="flex-1 px-4 py-3 rounded-2xl outline-none"
            style={{ background: "rgba(255,255,255,0.08)", color: "white", border: "1px solid rgba(91,122,255,0.3)", fontSize: 15 }}
          />
          <button onClick={handleManual} className="px-5 py-3 rounded-2xl font-bold"
            style={{ background: "var(--accent)", color: "#fff" }}>OK</button>
        </div>
      )}

      {/* Bottom panel — fixed height, no scroll */}
      <div className="flex-shrink-0 rounded-t-3xl p-4 flex flex-col gap-3"
        style={{ background: "var(--surface)", maxHeight: "45vh", overflow: "hidden" }}>

        {phase === "scanning" && (
          <p className="text-center py-2" style={{ fontSize: 14, color: "var(--txt2)" }}>
            Centrez le code-barres dans le cadre
          </p>
        )}

        {(phase === "loading" || phase === "saving") && (
          <div className="flex items-center justify-center gap-3 py-2">
            <div className="w-5 h-5 rounded-full border-2 animate-spin flex-shrink-0"
              style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
            <p style={{ fontSize: 14, color: "var(--txt2)" }}>
              {phase === "saving" ? "Enregistrement…" : `Recherche ${isbn}…`}
            </p>
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
              <RefreshCw className="w-4 h-4" /> Réessayer
            </Button>
          </div>
        )}

        {phase === "confirm" && result && (
          <>
            {/* Collection badge */}
            {result.collection && (
              <div className="flex items-center gap-2 px-3 py-2 rounded-xl flex-shrink-0"
                style={{
                  background: result.isNewCollection ? "var(--accent-l)" : "var(--have-bg)",
                  border: `1px solid ${result.isNewCollection ? "var(--border)" : "var(--have-b)"}`,
                }}>
                {result.isNewCollection
                  ? <Plus className="w-4 h-4 flex-shrink-0" style={{ color: "var(--accent)" }} />
                  : <Check className="w-4 h-4 flex-shrink-0" style={{ color: "var(--have-t)" }} />}
                <p className="truncate font-semibold" style={{
                  fontSize: 13,
                  color: result.isNewCollection ? "var(--accent)" : "var(--have-t)",
                }}>
                  {result.isNewCollection
                    ? `Collection « ${result.collection.name} » créée`
                    : `Tome ${result.book.series_index} ajouté à ${result.collection.name}`}
                </p>
              </div>
            )}

            {/* Book preview */}
            <div className="flex gap-3 p-3 rounded-2xl flex-shrink-0"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
              <Cover
                src={result.book.cover_url}
                alt={result.book.title}
                width={44} height={62}
                className="rounded-lg flex-shrink-0"
              />
              <div className="flex-1 min-w-0">
                <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>
                  {result.book.title}
                </p>
                <p className="truncate" style={{ fontSize: 12, color: "var(--txt2)", marginTop: 2 }}>
                  {result.book.authors.join(", ")}
                </p>
                {result.book.series_name && (
                  <p style={{ fontSize: 11, color: "var(--accent)", marginTop: 2 }}>
                    {result.book.series_name} #{result.book.series_index}
                  </p>
                )}
              </div>
            </div>

            {/* Status picker */}
            <div className="flex gap-2 flex-shrink-0">
              {(Object.entries(STATUS_CONFIG) as [ReadStatus, { emoji: string; label: string }][]).map(([v, { emoji, label }]) => (
                <button key={v} onClick={() => setStatus(v)}
                  className="flex-1 py-2 rounded-xl font-semibold"
                  style={{
                    fontSize: 12,
                    background: status === v ? "var(--accent)" : "var(--surface2)",
                    color: status === v ? "#fff" : "var(--txt2)",
                    border: `1px solid ${status === v ? "var(--accent)" : "var(--border)"}`,
                  }}>
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
cat > "src/app/scan/page.tsx" << 'FILEOF'
"use client";
import { useState, useCallback } from "react";
import { useLibrary } from "@/hooks/useLibrary";
import { useToast } from "@/hooks/useToast";
import { useFirstUse } from "@/hooks/useFirstUse";
import BottomNav from "@/components/layout/BottomNav";
import Scanner from "@/components/scanner/Scanner";
import { ToastStack } from "@/components/ui/Toast";
import { ScanLine, Zap, Settings2 } from "lucide-react";

interface SavedBook {
  title: string;
  collection_name?: string;
  is_new_collection?: boolean;
}

const MODES = [
  { key: false, icon: Settings2, label: "Mode classique", sub: "Confirmation avant ajout" },
  { key: true,  icon: Zap,       label: "Mode rapide",    sub: "Ajout instantané en série" },
] as const;

export default function ScanPage() {
  const { library_id, email, loading } = useLibrary();
  const [scanning,  setScanning]       = useState(false);
  const [rapidMode, setRapidMode]      = useState(false);
  const isFirstUse                     = useFirstUse("folio_scan_seen");
  const { toasts, push, dismiss }      = useToast();

  // Toast uses the real title returned by the API after save — never the lookup title
  const handleSuccess = useCallback((saved: SavedBook) => {
    const subtitle = saved.is_new_collection
      ? `Collection « ${saved.collection_name} » créée`
      : saved.collection_name
        ? `Ajouté à ${saved.collection_name}`
        : undefined;

    push(saved.title, subtitle);

    if (!rapidMode) setScanning(false);
  }, [rapidMode, push]);

  if (isFirstUse === null) return null;
  const ready = !!library_id && !!email && !loading;

  return (
    <>
      <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>
        <div className="px-4 pt-12 pb-4">
          <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>
            Ajouter
          </p>
          <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Scanner</h1>
        </div>

        {/* Mode toggle */}
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

        {isFirstUse
          ? <FirstUseView onStart={() => ready && setScanning(true)} ready={ready} />
          : <ScanButton rapidMode={rapidMode} onStart={() => ready && setScanning(true)} ready={ready} />}
      </div>

      {scanning && library_id && email && (
        <Scanner
          rapidMode={rapidMode}
          libraryId={library_id}
          userEmail={email}
          onSuccess={handleSuccess}
          onClose={() => setScanning(false)}
        />
      )}

      <ToastStack toasts={toasts} onDismiss={dismiss} />
      <BottomNav />
    </>
  );
}

function ScanButton({ rapidMode, onStart, ready }: { rapidMode: boolean; onStart: () => void; ready: boolean }) {
  return (
    <div className="flex flex-col items-center gap-4 px-5">
      <button onClick={onStart} disabled={!ready}
        className="w-full py-5 rounded-3xl flex items-center justify-center gap-3 active:scale-95"
        style={{
          background: ready ? "var(--accent)" : "var(--surface)",
          boxShadow: ready ? "0 8px 32px rgba(59,91,255,0.35)" : "none",
          opacity: ready ? 1 : 0.6,
          cursor: ready ? "pointer" : "default",
        }}>
        {!ready
          ? <div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
          : <ScanLine className="w-7 h-7 text-white" />}
        <span className="font-bold text-white" style={{ fontSize: 17 }}>
          {!ready ? "Chargement…" : rapidMode ? "Lancer le mode rapide" : "Ouvrir le scanner"}
        </span>
      </button>
      {ready && (
        <p className="text-center" style={{ fontSize: 13, color: "var(--txt3)" }}>
          {rapidMode ? "Chaque scan est ajouté immédiatement" : "ISBN ou EAN détecté automatiquement"}
        </p>
      )}
    </div>
  );
}

function FirstUseView({ onStart, ready }: { onStart: () => void; ready: boolean }) {
  const STEPS = [
    "Pointez la caméra vers le code-barres",
    "La détection est automatique",
    "Les BDs créent leur collection automatiquement",
  ];
  return (
    <div className="flex flex-col items-center gap-6 px-5">
      <button onClick={onStart} disabled={!ready}
        className="w-32 h-32 rounded-3xl flex flex-col items-center justify-center gap-2 active:scale-95"
        style={{
          background: ready ? "var(--accent)" : "var(--surface)",
          boxShadow: ready ? "0 8px 32px rgba(59,91,255,0.35)" : "none",
          opacity: ready ? 1 : 0.6,
          cursor: ready ? "pointer" : "default",
        }}>
        {!ready
          ? <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
          : <ScanLine className="w-12 h-12 text-white" />}
        <span className="font-bold text-white text-sm">{ready ? "Scanner" : "…"}</span>
      </button>
      <div className="text-center">
        <p className="font-bold" style={{ fontSize: 17, color: "var(--txt1)" }}>Scannez le code-barres</p>
        <p style={{ fontSize: 14, color: "var(--txt3)", marginTop: 4 }}>ISBN ou EAN au dos du livre</p>
      </div>
      <div className="w-full space-y-2">
        {STEPS.map((text, i) => (
          <div key={i} className="flex items-center gap-3 p-4 rounded-2xl"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <span className="w-7 h-7 rounded-full flex items-center justify-center font-bold text-white flex-shrink-0"
              style={{ background: "var(--accent)", fontSize: 13 }}>{i + 1}</span>
            <span style={{ fontSize: 14, color: "var(--txt2)" }}>{text}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
FILEOF
git add -A
git commit -m "fix: toast shows real saved title, BnF first for all EAN-13, consistent scan flow"
git push
echo "🎉 Déployé !"
