#!/bin/bash
set -e
echo "🔍 Fix EAN vs ISBN — doute automatique pour codes non-ISBN..."
cd "$(git rev-parse --show-toplevel)"
cat > "src/types/index.ts" << 'FILEOF'
// ─── Core types ───────────────────────────────────────────────────────────────

export type ReadStatus = "lu" | "en_cours" | "a_lire";
export type BookType   = "livre" | "bd" | "manga";

export interface Book {
  id: string;
  isbn?: string;
  title: string;
  authors: string[];
  cover_url?: string;
  publisher?: string;
  published_year?: number;
  page_count?: number;
  description?: string;
  book_type: BookType;
  status: ReadStatus;
  rating?: number;       // 1–5
  note?: string;
  series_name?: string;
  series_index?: number;
  collection_id?: string;
  library_id: string;
  added_by: string;
  added_at: string;
  updated_at: string;
}

export interface Collection {
  id: string;
  library_id: string;
  name: string;
  author?: string;
  cover_url?: string;
  book_type: BookType;
  total_volumes?: number;
  owned_volumes: number[];
  created_at: string;
  updated_at: string;
}

export interface WishlistItem {
  id: string;
  title: string;
  authors: string[];
  cover_url?: string;
  series_index?: number;
  isbn?: string;
  claimed_by_name?: string;
  claimed_at?: string;
}

export interface Wishlist {
  id: string;
  collection_id: string;
  collection_name: string;
  owner_name: string;
  missing_items: WishlistItem[];
  created_at: string;
}

export interface SharedLibrary {
  wishlist_id: string;
  collection_name: string;
  owner_name: string;
  shared_at: string;
  missing_count: number;
  claimed_count: number;
  cover_url?: string;
}

// ─── API response ─────────────────────────────────────────────────────────────

export interface LookupResult {
  isbn: string;
  title: string;
  authors: string[];
  cover_url?: string;
  publisher?: string;
  published_year?: number;
  page_count?: number;
  description?: string;
  series_name?: string;
  series_index?: number;
  book_type: BookType;
  _unreliable?: boolean;
}

export interface ScanResult {
  book: LookupResult;
  collection?: Collection;
  isNewCollection: boolean;
  isNewVolume: boolean;
}
FILEOF
cat > "src/lib/isbn-lookup.ts" << 'FILEOF'
import { LookupResult, BookType } from "@/types";

// ── Type detection ─────────────────────────────────────────────────────────────

function detectType(terms: string): BookType {
  const t = terms.toLowerCase();
  if (/manga|manhwa|shonen|shojo|seinen|josei|kodansha|shueisha|viz|one.piece|naruto|dragon.ball/.test(t)) return "manga";
  if (/bande.dessin|bd|comics|dargaud|dupuis|lombard|casterman|lucky|schtroumpf|ast[eé]rix|tintin|spirou|blake|mortimer|franco.belge/.test(t)) return "bd";
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
      const name = m[1].replace(/\s+$/, "").trim();
      return { seriesName: name || undefined, seriesIndex: parseInt(m[2]) };
    }
  }
  return {};
}

// ── Is this a standard ISBN (978/979) or a product EAN? ───────────────────────

function isStandardISBN(code: string): boolean {
  return /^(978|979)\d{10}$/.test(code);
}

// ── Google Books (with API key) ───────────────────────────────────────────────

async function fromGoogleBooks(code: string): Promise<LookupResult | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=isbn:${code}${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) { console.error("Google Books error:", res.status); return null; }

    const data = await res.json();
    const vol = data.items?.[0]?.volumeInfo;
    if (!vol?.title) return null;

    const categories = (vol.categories ?? []).join(" ").toLowerCase();
    const fullTitle  = `${vol.title} ${vol.subtitle ?? ""}`.trim();

    // Use seriesInfo if available (Google Books specific)
    let seriesName: string | undefined;
    let seriesIndex: number | undefined;

    const seriesInfo = data.items?.[0]?.volumeInfo?.seriesInfo;
    if (seriesInfo?.bookDisplayNumber) {
      seriesIndex = parseInt(seriesInfo.bookDisplayNumber);
    }

    // Also try extracting from title
    const parsed = extractSeries(fullTitle);
    seriesName  = parsed.seriesName ?? seriesName;
    seriesIndex = seriesIndex ?? parsed.seriesIndex;

    let coverUrl = vol.imageLinks?.extraLarge
      ?? vol.imageLinks?.large
      ?? vol.imageLinks?.medium
      ?? vol.imageLinks?.thumbnail;

    if (coverUrl) {
      coverUrl = coverUrl
        .replace("http:", "https:")
        .replace("&edge=curl", "")
        .replace(/zoom=\d/, "zoom=3");
    }

    return {
      isbn: code, title: vol.title, authors: vol.authors ?? [],
      cover_url: coverUrl,
      publisher: vol.publisher,
      published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : undefined,
      page_count: vol.pageCount,
      description: vol.description,
      series_name: seriesName, series_index: seriesIndex,
      book_type: detectType(categories + " " + fullTitle + " " + (vol.publisher ?? "")),
    };
  } catch { return null; }
}

// ── BnF SRU API ───────────────────────────────────────────────────────────────

async function fromBnF(code: string): Promise<LookupResult | null> {
  try {
    for (const field of ["bib.ean", "bib.isbn"]) {
      const url = `https://catalogue.bnf.fr/api/SRU?version=1.2&operation=searchRetrieve&query=${field}+adj+"${code}"&recordSchema=unimarcxchange&maximumRecords=1`;
      const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
      const text = await res.text();
      if (text.includes("<numberOfRecords>0")) continue;

      const titleA   = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
      const titleE   = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="e">([^<]+)/)?.[1]?.trim();
      if (!titleA) continue;
      const title    = titleE ? `${titleA} — ${titleE}` : titleA;

      const volStr    = text.match(/<datafield tag="200"[^>]*>[\s\S]*?<subfield code="h">([^<]+)/)?.[1]?.trim();
      const volNum    = volStr ? parseInt(volStr.replace(/\D/g, "")) : undefined;
      const seriesRaw = text.match(/<datafield tag="225"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
      const seriesVol = text.match(/<datafield tag="225"[^>]*>[\s\S]*?<subfield code="v">([^<]+)/)?.[1]?.trim();

      const authorB   = text.match(/<datafield tag="700"[^>]*>[\s\S]*?<subfield code="a">([^<]+)/)?.[1]?.trim();
      const authorF   = text.match(/<datafield tag="700"[^>]*>[\s\S]*?<subfield code="b">([^<]+)/)?.[1]?.trim();
      const author    = authorB ? [authorF ? `${authorF} ${authorB}` : authorB] : [];

      const publisher = text.match(/<datafield tag="210"[^>]*>[\s\S]*?<subfield code="c">([^<]+)/)?.[1]?.trim();
      const yearStr   = text.match(/<datafield tag="210"[^>]*>[\s\S]*?<subfield code="d">(\d{4})/)?.[1];
      const subjects  = text.match(/<subfield code="a">([^<]+)/g)?.join(" ") ?? "";

      let seriesName  = seriesRaw?.replace(/\s*#?\d+.*$/, "").trim();
      let seriesIndex = seriesVol ? parseInt(seriesVol.replace(/\D/g, "")) : volNum;
      if (!seriesName) {
        const p = extractSeries(title);
        seriesName  = p.seriesName;
        seriesIndex = p.seriesIndex ?? seriesIndex;
      }

      return {
        isbn: code, title, authors: author,
        cover_url: `https://catalogue.bnf.fr/couverture?&isbn=${code}&notoile=1`,
        publisher, published_year: yearStr ? parseInt(yearStr) : undefined,
        series_name: seriesName, series_index: seriesIndex,
        book_type: detectType(subjects + " " + title + " " + (publisher ?? "") + " " + (seriesName ?? "")),
      };
    }
    return null;
  } catch { return null; }
}

// ── Open Library ──────────────────────────────────────────────────────────────

async function fromOpenLibrary(isbn: string): Promise<LookupResult | null> {
  try {
    const res  = await fetch(
      `https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`,
      { signal: AbortSignal.timeout(5000) }
    );
    const data = await res.json();
    const b    = data[`ISBN:${isbn}`];
    if (!b?.title) return null;

    const subjects   = (b.subjects ?? []).map((s: any) => typeof s === "string" ? s : s.name ?? "").join(" ").toLowerCase();
    const series     = Array.isArray(b.series) ? b.series[0] : b.series;
    const numMatch   = typeof series === "string" ? series.match(/#?(\d+)/) : null;
    const { seriesName: parsedName, seriesIndex: parsedIdx } = extractSeries(b.title);

    return {
      isbn, title: b.title,
      authors: (b.authors ?? []).map((a: any) => a.name),
      cover_url: b.cover?.large ?? b.cover?.medium ?? b.cover?.small,
      publisher: b.publishers?.[0]?.name,
      published_year: b.publish_date ? parseInt(b.publish_date.slice(-4)) : undefined,
      page_count: b.number_of_pages,
      description: b.excerpts?.[0]?.text,
      series_name: (typeof series === "string" ? series.replace(/\s*#?\d+.*$/, "").trim() || undefined : undefined) ?? parsedName,
      series_index: numMatch ? parseInt(numMatch[1]) : parsedIdx,
      book_type: detectType(subjects + " " + b.title),
    };
  } catch { return null; }
}

// ── Main lookup ───────────────────────────────────────────────────────────────
// 
// For standard ISBN (978/979...): Google Books → BnF → Open Library
// For product EAN (other prefixes): BnF → Open Library (flagged as unreliable)

export async function lookupISBN(code: string): Promise<LookupResult | null> {
  const clean = code.replace(/[-\s]/g, "");

  if (isStandardISBN(clean)) {
    // Standard ISBN — reliable lookups
    const gb = await fromGoogleBooks(clean);
    if (gb?.title) return gb;
  }

  // BnF for all EAN-13
  if (/^\d{13}$/.test(clean)) {
    const bnf = await fromBnF(clean);
    if (bnf?.title) return bnf;
  }

  // For non-ISBN EAN, Open Library often has wrong data
  // Still try it but mark the result as potentially unreliable
  const ol = await fromOpenLibrary(clean);
  if (ol?.title) {
    // Flag: if this is a non-ISBN EAN, the result may be wrong
    if (!isStandardISBN(clean)) {
      ol._unreliable = true;
    }
    return ol;
  }

  return null;
}
FILEOF
cat > "src/components/scanner/Scanner.tsx" << 'FILEOF'
"use client";
import { useEffect, useRef, useState, useCallback } from "react";
import { BrowserMultiFormatReader } from "@zxing/library";
import { X, Keyboard, Check, Plus, RefreshCw, Edit2, AlertTriangle } from "lucide-react";
import { ScanResult, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
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

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Returns true if the lookup result is reliable enough for rapid-mode auto-save.
 * Falls back to confirmation if there's any doubt.
 */
function isReliable(result: ScanResult): boolean {
  const { book } = result;
  // Flagged as unreliable by the lookup (non-ISBN EAN code)
  if (book._unreliable) return false;
  // Always reliable if series was fully resolved
  if (book.series_name && book.series_index) return true;
  // Doubt: BD/manga without series info — likely bad metadata
  if (book.book_type === "bd" || book.book_type === "manga") return false;
  // Doubt: no cover image
  if (!book.cover_url) return false;
  // Doubt: very short title (likely truncated or wrong)
  if (book.title.length < 4) return false;
  // Looks good for a regular book
  return true;
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

  const [phase,      setPhase]      = useState<Phase>("scanning");
  const [isbn,       setIsbn]       = useState("");
  const [result,     setResult]     = useState<ScanResult | null>(null);
  const [status,     setStatus]     = useState<ReadStatus>("a_lire");
  const [bookType,   setBookType]   = useState<BookType>("livre");
  const [manual,     setManual]     = useState("");
  const [showKbd,    setShowKbd]    = useState(false);
  const [needsCheck, setNeedsCheck] = useState(false); // rapid mode paused for correction

  // Editable fields
  const [editTitle,  setEditTitle]  = useState("");
  const [editSeries, setEditSeries] = useState("");
  const [editVolume, setEditVolume] = useState("");
  const [isEditing,  setIsEditing]  = useState(false);

  const frameColor =
    phase === "success"                        ? "#22C55E" :
    phase === "not_found" || phase === "error" ? "#EF4444" :
    needsCheck                                 ? "#F59E0B" :
    "#5B7AFF";

  // ── Camera ────────────────────────────────────────────────────────────────
  useEffect(() => {
    const reader = new BrowserMultiFormatReader();
    reader.decodeFromVideoDevice(null, videoRef.current!, (r) => {
      if (!r || processingRef.current) return;
      processingRef.current = true;
      doLookup(r.getText());
    });
    return () => reader.reset();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Lookup ────────────────────────────────────────────────────────────────
  const doLookup = useCallback(async (code: string) => {
    setIsbn(code);
    setPhase("loading");
    setNeedsCheck(false);

    try {
      const res = await fetch(
        `/api/books/lookup?isbn=${encodeURIComponent(code)}&library_id=${libraryId}`
      );
      if (!res.ok) { setPhase("not_found"); processingRef.current = false; return; }

      const data: ScanResult = await res.json();
      setResult(data);
      setBookType(data.book.book_type);
      setEditTitle(data.book.title ?? "");
      setEditSeries(data.book.series_name ?? "");
      setEditVolume(data.book.series_index?.toString() ?? "");
      setIsEditing(false);

      if (rapidMode && isReliable(data)) {
        // Reliable → save immediately
        const saved = await doSave(data, "a_lire", data.book.book_type,
          data.book.title, data.book.series_name, data.book.series_index);
        if (saved) {
          setPhase("success");
          setTimeout(() => { setPhase("scanning"); setResult(null); setIsbn(""); processingRef.current = false; }, 800);
        } else {
          setPhase("error"); processingRef.current = false;
        }
      } else {
        // Classic mode OR rapid mode with doubt → show confirmation
        setNeedsCheck(rapidMode && !isReliable(data));
        setPhase("confirm");
        processingRef.current = false;
      }
    } catch {
      setPhase("error"); processingRef.current = false;
    }
  }, [rapidMode, libraryId]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Save ──────────────────────────────────────────────────────────────────
  const doSave = async (
    r: ScanResult, s: ReadStatus, bt: BookType,
    title: string, seriesName?: string, seriesIndex?: number
  ): Promise<SavedBook | null> => {
    try {
      let collectionId    = r.collection?.id;
      let collectionName  = r.collection?.name;
      let isNewCollection = r.isNewCollection;

      // If user manually set series info, resolve the collection now
      const hasManualSeries = seriesName && seriesIndex && (bt === "bd" || bt === "manga");
      const seriesChanged   = seriesName !== r.book.series_name || seriesIndex !== r.book.series_index;

      if (hasManualSeries && seriesChanged) {
        const colRes = await fetch(
          `/api/collections/resolve?library_id=${libraryId}&series_name=${encodeURIComponent(seriesName!)}&series_index=${seriesIndex}&book_type=${bt}`
        );
        if (colRes.ok) {
          const col = await colRes.json();
          collectionId    = col.collection?.id;
          collectionName  = col.collection?.name;
          isNewCollection = col.isNew;
        }
      }

      const res = await fetch("/api/books/add", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          isbn:           r.book.isbn,
          title,
          authors:        r.book.authors,
          cover_url:      r.book.cover_url,
          publisher:      r.book.publisher,
          published_year: r.book.published_year,
          page_count:     r.book.page_count,
          description:    r.book.description,
          book_type:      bt,
          status:         s,
          series_name:    seriesName || undefined,
          series_index:   seriesIndex || undefined,
          collection_id:  collectionId,
          library_id:     libraryId,
          email:          userEmail,
        }),
      });

      if (!res.ok) { const e = await res.json(); console.error("doSave:", e); return null; }
      const saved = await res.json();
      const out: SavedBook = {
        title:            saved.title ?? title,
        collection_name:  collectionName,
        is_new_collection: isNewCollection,
      };
      onSuccess(out);
      return out;
    } catch (e) { console.error("doSave:", e); return null; }
  };

  // ── Handlers ──────────────────────────────────────────────────────────────
  const handleConfirm = async () => {
    if (!result) return;
    setPhase("saving");
    const title      = editTitle.trim()  || result.book.title;
    const seriesName = editSeries.trim() || undefined;
    const seriesIdx  = editVolume        ? parseInt(editVolume) : undefined;
    const saved = await doSave(result, status, bookType, title, seriesName, seriesIdx);
    if (saved) { setPhase("success"); setTimeout(() => { reset(); if (!needsCheck) onClose(); else { setNeedsCheck(false); setPhase("scanning"); } }, 600); }
    else setPhase("error");
  };

  const reset = () => {
    setPhase("scanning"); setResult(null); setIsbn("");
    setNeedsCheck(false); processingRef.current = false;
  };

  const handleManual = () => {
    if (!manual.trim()) return;
    processingRef.current = true;
    doLookup(manual.trim());
  };

  // ── Render ────────────────────────────────────────────────────────────────
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

      {/* Mode banner */}
      {rapidMode && !needsCheck && (
        <div className="mx-5 mb-1 px-3 py-2 rounded-xl flex-shrink-0"
          style={{ background: "rgba(59,91,255,0.18)", border: "1px solid rgba(91,122,255,0.3)" }}>
          <span style={{ fontSize: 12, color: "#7B80FF" }}>Scan continu — ajout instantané si fiable</span>
        </div>
      )}
      {needsCheck && (
        <div className="mx-5 mb-1 px-3 py-2 rounded-xl flex items-center gap-2 flex-shrink-0"
          style={{ background: "rgba(245,158,11,0.15)", border: "1px solid rgba(245,158,11,0.3)" }}>
          <AlertTriangle className="w-4 h-4 flex-shrink-0" style={{ color: "#F59E0B" }} />
          <span style={{ fontSize: 12, color: "#F59E0B" }}>Métadonnées douteuses — corrige avant d&apos;ajouter</span>
        </div>
      )}

      {/* Camera — always running */}
      <div className="flex-1 flex items-center justify-center relative min-h-0">
        <div className="relative">
          <video ref={videoRef}
            style={{ width: 300, height: 220, objectFit: "cover", borderRadius: 12, display: "block" }} />
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
              <div className="w-5 h-5 rounded-full border-2 animate-spin"
                style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
            </div>
          )}
        </div>
      </div>

      {/* Manual ISBN */}
      {showKbd && (
        <div className="flex gap-2 px-5 mb-2 flex-shrink-0">
          <input type="text" value={manual} onChange={e => setManual(e.target.value)}
            placeholder="Saisir ISBN ou EAN..."
            onKeyDown={e => e.key === "Enter" && handleManual()}
            className="flex-1 px-4 py-3 rounded-2xl outline-none"
            style={{ background: "rgba(255,255,255,0.08)", color: "white", border: "1px solid rgba(91,122,255,0.3)", fontSize: 15 }} />
          <button onClick={handleManual} className="px-5 py-3 rounded-2xl font-bold"
            style={{ background: "var(--accent)", color: "#fff" }}>OK</button>
        </div>
      )}

      {/* Bottom panel */}
      <div className="flex-shrink-0 rounded-t-3xl p-4 flex flex-col gap-3"
        style={{ background: "var(--surface)", maxHeight: "55vh", overflowY: "auto" }}>

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
            ✅ {needsCheck ? "Corrigé et ajouté !" : "Ajouté !"}
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
            {/* Collection badge — only if not editing and series resolved */}
            {result.collection && !isEditing && (
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
                    : `Tome ${result.book.series_index} → ${result.collection.name}`}
                </p>
              </div>
            )}

            {/* Book preview + edit toggle */}
            <div className="flex gap-3 p-3 rounded-2xl flex-shrink-0"
              style={{ background: "var(--surface2)", border: `1px solid ${needsCheck ? "rgba(245,158,11,0.4)" : "var(--border)"}` }}>
              <Cover src={result.book.cover_url} alt={editTitle} width={44} height={62} className="rounded-lg flex-shrink-0" />
              <div className="flex-1 min-w-0">
                {isEditing ? (
                  <div className="flex flex-col gap-2">
                    <input
                      value={editTitle} onChange={e => setEditTitle(e.target.value)}
                      placeholder="Titre..."
                      className="w-full px-2 py-1.5 rounded-lg outline-none"
                      style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 13 }}
                    />
                    <div className="flex gap-2">
                      <input
                        value={editSeries} onChange={e => setEditSeries(e.target.value)}
                        placeholder="Série (ex: Les Schtroumpfs)"
                        className="flex-1 px-2 py-1.5 rounded-lg outline-none"
                        style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 12 }}
                      />
                      <input
                        value={editVolume} onChange={e => setEditVolume(e.target.value)}
                        placeholder="T." type="number"
                        className="w-14 px-2 py-1.5 rounded-lg outline-none text-center"
                        style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 12 }}
                      />
                    </div>
                  </div>
                ) : (
                  <>
                    <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{editTitle}</p>
                    <p className="truncate" style={{ fontSize: 12, color: "var(--txt2)", marginTop: 2 }}>
                      {result.book.authors.join(", ")}
                    </p>
                    {editSeries && (
                      <p style={{ fontSize: 11, color: "var(--accent)", marginTop: 2 }}>
                        {editSeries} #{editVolume}
                      </p>
                    )}
                  </>
                )}
              </div>
              <button
                onClick={() => setIsEditing(v => !v)}
                className="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 self-start"
                style={{
                  background: isEditing ? "var(--accent)" : needsCheck ? "rgba(245,158,11,0.2)" : "var(--surface)",
                  border: `1px solid ${isEditing ? "var(--accent)" : needsCheck ? "rgba(245,158,11,0.5)" : "var(--border)"}`,
                }}>
                <Edit2 className="w-3.5 h-3.5" style={{ color: isEditing ? "#fff" : needsCheck ? "#F59E0B" : "var(--txt3)" }} />
              </button>
            </div>

            {/* Type picker */}
            <div className="flex gap-2 flex-shrink-0">
              {(Object.entries(TYPE_CONFIG) as [BookType, { emoji: string; label: string }][]).map(([v, { emoji, label }]) => (
                <button key={v} onClick={() => setBookType(v)} className="flex-1 py-1.5 rounded-xl font-semibold"
                  style={{
                    fontSize: 11,
                    background: bookType === v ? "var(--accent)" : "var(--surface2)",
                    color:      bookType === v ? "#fff"          : "var(--txt2)",
                    border:     `1px solid ${bookType === v ? "var(--accent)" : "var(--border)"}`,
                  }}>
                  {emoji} {label}
                </button>
              ))}
            </div>

            {/* Status picker */}
            <div className="flex gap-2 flex-shrink-0">
              {(Object.entries(STATUS_CONFIG) as [ReadStatus, { emoji: string; label: string }][]).map(([v, { emoji, label }]) => (
                <button key={v} onClick={() => setStatus(v)} className="flex-1 py-2 rounded-xl font-semibold"
                  style={{
                    fontSize: 11,
                    background: status === v ? "var(--accent)" : "var(--surface2)",
                    color:      status === v ? "#fff"          : "var(--txt2)",
                    border:     `1px solid ${status === v ? "var(--accent)" : "var(--border)"}`,
                  }}>
                  {emoji} {label}
                </button>
              ))}
            </div>

            <Button onClick={handleConfirm} className="w-full py-3 rounded-2xl flex-shrink-0" style={{ fontSize: 14 }}>
              <Check className="w-4 h-4" />
              {needsCheck ? "Corriger et ajouter" : "Ajouter"}
            </Button>
          </>
        )}
      </div>
    </div>
  );
}
FILEOF
git add -A
git commit -m "feat: ISBN vs EAN distinction — always doubt mode for non-ISBN EAN codes"
git push
echo "🎉 Déployé !"
