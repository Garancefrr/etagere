#!/bin/bash
set -e
echo "🔧 Fix titre nettoyé + cover préservée..."
cd "$(git rev-parse --show-toplevel)"
cat > "src/lib/isbn-lookup.ts" << 'FILEOF'
import { LookupResult, BookType } from "@/types";

function detectType(terms: string): BookType {
  const t = terms.toLowerCase();
  if (/manga|manhwa|shonen|shojo|seinen|josei|kodansha|shueisha|viz|one.piece|naruto|dragon.ball/.test(t)) return "manga";
  if (/bande.dessin|bd|comics|dargaud|dupuis|lombard|casterman|lucky|schtroumpf|ast[eé]rix|tintin|spirou|blake|mortimer|franco.belge/.test(t)) return "bd";
  return "livre";
}

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
      return { seriesName: m[1].replace(/\s+$/, "").trim() || undefined, seriesIndex: parseInt(m[2]) };
    }
  }
  return {};
}

// ISBN = 978/979 (13 digits) or 10 digits
function isISBN(code: string): boolean {
  if (/^(978|979)\d{10}$/.test(code)) return true; // ISBN-13
  if (/^\d{9}[\dXx]$/.test(code)) return true;      // ISBN-10
  return false;
}

// ── Google Books ──────────────────────────────────────────────────────────────

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
    const rawTitle   = vol.title ?? "";
    // Clean title: take first part before ";" (multi-story compilations)
    const cleanTitle = rawTitle.includes(";") ? rawTitle.split(";")[0].trim() : rawTitle;
    const fullTitle  = `${cleanTitle} ${vol.subtitle ?? ""}`.trim();

    let seriesName: string | undefined;
    let seriesIndex: number | undefined;
    const seriesInfo = data.items?.[0]?.volumeInfo?.seriesInfo;
    if (seriesInfo?.bookDisplayNumber) seriesIndex = parseInt(seriesInfo.bookDisplayNumber);

    // Try extracting series from "Series - Tome X - Title" pattern
    const parsed = extractSeries(fullTitle);
    seriesName  = parsed.seriesName ?? seriesName;
    seriesIndex = seriesIndex ?? parsed.seriesIndex;

    // If no series detected but it looks like a BD, try to extract series name
    // from the title pattern "Les X something" → series "Les X"
    if (!seriesName && seriesIndex) {
      // We have a volume number from seriesInfo but no name
      // Use the main title words as series name
      seriesName = cleanTitle.replace(/\s*[-–—].*$/, "").trim() || undefined;
    }

    let coverUrl = vol.imageLinks?.extraLarge ?? vol.imageLinks?.large ?? vol.imageLinks?.medium ?? vol.imageLinks?.thumbnail;
    if (coverUrl) coverUrl = coverUrl.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");

    return {
      isbn: code, title: cleanTitle, authors: vol.authors ?? [],
      cover_url: coverUrl, publisher: vol.publisher,
      published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : undefined,
      page_count: vol.pageCount, description: vol.description,
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
      if (!seriesName) { const p = extractSeries(title); seriesName = p.seriesName; seriesIndex = p.seriesIndex ?? seriesIndex; }

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
    const res = await fetch(
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
      page_count: b.number_of_pages, description: b.excerpts?.[0]?.text,
      series_name: (typeof series === "string" ? series.replace(/\s*#?\d+.*$/, "").trim() || undefined : undefined) ?? parsedName,
      series_index: numMatch ? parseInt(numMatch[1]) : parsedIdx,
      book_type: detectType(subjects + " " + b.title),
    };
  } catch { return null; }
}

// ── Main lookup ───────────────────────────────────────────────────────────────

// Convert ISBN-10 to ISBN-13
function isbn10to13(isbn10: string): string {
  const base = "978" + isbn10.slice(0, 9);
  let sum = 0;
  for (let i = 0; i < 12; i++) {
    sum += parseInt(base[i]) * (i % 2 === 0 ? 1 : 3);
  }
  const check = (10 - (sum % 10)) % 10;
  return base + check;
}

export async function lookupISBN(code: string): Promise<LookupResult | null> {
  const clean = code.replace(/[-\s]/g, "");

  // Prepare both ISBN-10 and ISBN-13 versions
  const isIsbn10 = /^\d{9}[\dXx]$/.test(clean);
  const isIsbn13 = /^(978|979)\d{10}$/.test(clean);
  const codes = [clean];
  if (isIsbn10) codes.push(isbn10to13(clean));

  // Try Google Books with all code variants
  for (const c of codes) {
    const gb = await fromGoogleBooks(c);
    if (gb?.title) return gb;
  }

  // Try BnF with all code variants (supports both ISBN-10 and ISBN-13)
  for (const c of codes) {
    const bnf = await fromBnF(c);
    if (bnf?.title) return bnf;
  }

  // Open Library with all variants
  for (const c of codes) {
    const ol = await fromOpenLibrary(c);
    if (ol?.title) {
      if (!isIsbn10 && !isIsbn13) ol._unreliable = true;
      return ol;
    }
  }

  return null;
}
FILEOF
cat > "src/components/scanner/Scanner.tsx" << 'FILEOF'
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
        setShowKbd(true); // Always open keyboard when not found
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
        setNeedsCheck(doubt);
        if (doubt) {
          setIsEditing(true);
          setShowKbd(true);
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

    // Only search for a cover if we don't have one
    let coverUrl = editCover;
    if (!coverUrl) {
      try {
        const q = serName ? `${serName} ${title}` : title;
        const coverRes = await fetch(`/api/books/cover?title=${encodeURIComponent(q)}`);
        if (coverRes.ok) {
          const coverData = await coverRes.json();
          if (coverData.cover_url) coverUrl = coverData.cover_url;
        }
      } catch { /* no cover found */ }
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

      {/* Camera — shrinks in correction mode */}
      <div className="flex items-center justify-center relative"
        style={{ flexShrink: 0, padding: phase === "confirm" ? "4px 0" : "12px 0" }}>
        <div className="relative">
          <video ref={videoRef}
            style={{
              width:  phase === "confirm" ? 180 : 300,
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

      {/* Bottom panel — includes ISBN input */}
      <div className="flex-1 flex-shrink rounded-t-3xl p-4 flex flex-col gap-3 overflow-y-auto"
        style={{ background: "var(--surface)" }}>

        {phase === "scanning" && (
          <p className="text-center py-2" style={{ fontSize: 14, color: "var(--txt2)" }}>Centrez le code-barres dans le cadre</p>
        )}

        {/* ISBN manual input — inside the panel */}
        {showKbd && (
          <div className="flex gap-2 flex-shrink-0">
            <input type="text" inputMode="numeric" pattern="[0-9-]*" value={manual} onChange={e => setManual(e.target.value.replace(/[^0-9-]/g, ""))}
              placeholder="ISBN : X-XXXX-XXXX-X"
              onKeyDown={e => e.key === "Enter" && manual.trim() && (processingRef.current = true, doLookup(manual.trim()))}
              className="flex-1 px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", color: "var(--txt1)", border: "1px solid var(--border)", fontSize: 15 }} />
            <button onClick={() => manual.trim() && (processingRef.current = true, doLookup(manual.trim()))}
              className="px-5 py-3 rounded-2xl font-bold" style={{ background: "var(--accent)", color: "#fff" }}>OK</button>
          </div>
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
            {phase === "not_found" && (
              <p style={{ fontSize: 12, color: "var(--txt2)", lineHeight: 1.5 }}>
                Tape un ISBN (978...) si tu en vois un imprimé sur le livre.
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
git commit -m "fix: clean title (remove ;), preserve Google Books cover, better series detection"
git push
echo "🎉 Déployé !"
