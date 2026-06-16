#!/bin/bash
set -e
echo "📷 Scanner v2 — dropdown collections, recherche cover, fix ajout..."
cd "$(git rev-parse --show-toplevel)"
mkdir -p src/app/api/books/cover src/app/api/collections/resolve
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
cat > "src/app/api/books/add/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { insertBook } from "@/lib/db";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();

    // Resolve added_by from email
    let addedBy: string | undefined;
    if (body.email) {
      addedBy = (await getProfileId(body.email)) ?? undefined;
    }

    // Whitelist only valid DB columns — no extra fields
    const bookData: Record<string, any> = {
      library_id:     body.library_id,
      isbn:           body.isbn,
      title:          body.title,
      authors:        body.authors ?? [],
      cover_url:      body.cover_url || null,
      publisher:      body.publisher || null,
      published_year: body.published_year || null,
      page_count:     body.page_count || null,
      description:    body.description || null,
      book_type:      body.book_type ?? "livre",
      status:         body.status ?? "a_lire",
      series_name:    body.series_name || null,
      series_index:   body.series_index || null,
      added_by:       addedBy || null,
    };

    const book = await insertBook(bookData as any);
    return NextResponse.json(book);
  } catch (e: any) {
    console.error("POST /api/books/add:", e);
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
FILEOF
cat > "src/app/api/books/cover/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";

export async function GET(req: NextRequest) {
  const title = req.nextUrl.searchParams.get("title");
  if (!title) return NextResponse.json({ cover_url: null });

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(title)}&langRestrict=fr${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return NextResponse.json({ cover_url: null });

    const data = await res.json();
    const vol = data.items?.[0]?.volumeInfo;
    if (!vol) return NextResponse.json({ cover_url: null });

    let coverUrl = vol.imageLinks?.large
      ?? vol.imageLinks?.medium
      ?? vol.imageLinks?.thumbnail;

    if (coverUrl) {
      coverUrl = coverUrl
        .replace("http:", "https:")
        .replace("&edge=curl", "")
        .replace(/zoom=\d/, "zoom=3");
    }

    return NextResponse.json({
      cover_url: coverUrl ?? null,
      found_title: vol.title,
      found_authors: vol.authors ?? [],
    });
  } catch {
    return NextResponse.json({ cover_url: null });
  }
}
FILEOF
cat > "src/components/scanner/Scanner.tsx" << 'FILEOF'
"use client";
import { useEffect, useRef, useState, useCallback } from "react";
import { BrowserMultiFormatReader } from "@zxing/library";
import { X, Keyboard, Check, Plus, RefreshCw, Edit2, AlertTriangle, Search, ChevronDown } from "lucide-react";
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
  const [searchingCover, setSearchingCover] = useState(false);

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

    try {
      const res = await fetch(`/api/books/lookup?isbn=${encodeURIComponent(code)}&library_id=${libraryId}`);
      if (!res.ok) { setPhase("not_found"); processingRef.current = false; return; }

      const data: ScanResult = await res.json();
      setResult(data);
      setBookType(data.book.book_type);
      setEditTitle(data.book.title ?? "");
      setEditSeries(data.book.series_name ?? "");
      setEditVolume(data.book.series_index?.toString() ?? "");
      setEditCover(data.book.cover_url);

      if (rapidMode && isReliable(data)) {
        const saved = await doSave(data, "a_lire", data.book.book_type,
          data.book.title, data.book.cover_url, data.book.series_name, data.book.series_index);
        if (saved) {
          setPhase("success");
          setTimeout(() => { setPhase("scanning"); setResult(null); setIsbn(""); processingRef.current = false; }, 800);
        } else { setPhase("error"); processingRef.current = false; }
      } else {
        setNeedsCheck(rapidMode && !isReliable(data));
        if (rapidMode && !isReliable(data)) setIsEditing(true);
        setPhase("confirm");
        processingRef.current = false;
      }
    } catch {
      setPhase("error"); processingRef.current = false;
    }
  }, [rapidMode, libraryId]); // eslint-disable-line react-hooks/exhaustive-deps

  // Search cover by title
  const searchCover = async () => {
    if (!editTitle.trim()) return;
    setSearchingCover(true);
    try {
      const q = editSeries ? `${editSeries} ${editTitle}` : editTitle;
      const res = await fetch(`/api/books/cover?title=${encodeURIComponent(q)}`);
      if (res.ok) {
        const data = await res.json();
        if (data.cover_url) setEditCover(data.cover_url);
      }
    } finally {
      setSearchingCover(false);
    }
  };

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
    const saved = await doSave(result, status, bookType, title, editCover, serName, serIdx);
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
          <span style={{ fontSize: 12, color: "#F59E0B" }}>Métadonnées douteuses — corrige avant d&apos;ajouter</span>
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
          <input type="text" value={manual} onChange={e => setManual(e.target.value)} placeholder="Saisir ISBN ou EAN..."
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
          <div className="flex items-center justify-between gap-3 py-1">
            <p style={{ fontSize: 14, color: "var(--miss-t)" }}>{phase === "error" ? "Erreur lors de l'ajout" : `Introuvable — ${isbn}`}</p>
            <Button onClick={reset} size="sm" variant="secondary"><RefreshCw className="w-4 h-4" /> Réessayer</Button>
          </div>
        )}

        {phase === "confirm" && result && (
          <>
            {/* Book preview + edit */}
            <div className="flex gap-3 p-3 rounded-2xl flex-shrink-0"
              style={{ background: "var(--surface2)", border: `1px solid ${needsCheck ? "rgba(245,158,11,0.4)" : "var(--border)"}` }}>
              <div className="flex flex-col items-center gap-1 flex-shrink-0">
                <Cover src={editCover} alt={editTitle} width={44} height={62} className="rounded-lg" />
                {isEditing && (
                  <button onClick={searchCover} disabled={searchingCover}
                    className="px-2 py-0.5 rounded-md flex items-center gap-1"
                    style={{ background: "var(--accent-l)", fontSize: 10, color: "var(--accent)" }}>
                    {searchingCover
                      ? <div className="w-3 h-3 rounded-full border animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
                      : <Search className="w-3 h-3" />}
                    Photo
                  </button>
                )}
              </div>
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
                        style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
                        <input value={editSeries}
                          onChange={e => { setEditSeries(e.target.value); setShowDropdown(true); }}
                          onClick={e => { e.stopPropagation(); setShowDropdown(true); }}
                          placeholder="Série (ex: Les Schtroumpfs)"
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

            <Button onClick={handleConfirm} className="w-full py-3 rounded-2xl flex-shrink-0" style={{ fontSize: 14 }}>
              <Check className="w-4 h-4" /> {needsCheck ? "Corriger et ajouter" : "Ajouter"}
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
import { useState, useCallback, useEffect } from "react";
import { useLibrary } from "@/hooks/useLibrary";
import { useToast } from "@/hooks/useToast";
import { useFirstUse } from "@/hooks/useFirstUse";
import { Collection } from "@/types";
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
  { key: true,  icon: Zap,       label: "Mode rapide",    sub: "Ajout instantané si fiable" },
] as const;

export default function ScanPage() {
  const { library_id, email, loading }    = useLibrary();
  const [scanning,    setScanning]        = useState(false);
  const [rapidMode,   setRapidMode]       = useState(false);
  const [collections, setCollections]     = useState<Collection[]>([]);
  const isFirstUse                        = useFirstUse("folio_scan_seen");
  const { toasts, push, dismiss }         = useToast();

  // Fetch existing collections for the dropdown
  useEffect(() => {
    if (!library_id) return;
    fetch(`/api/collections?library_id=${library_id}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setCollections(d) : [])
      .catch(console.error);
  }, [library_id]);

  const handleSuccess = useCallback((saved: SavedBook) => {
    push(saved.title, saved.is_new_collection
      ? `Collection « ${saved.collection_name} » créée`
      : saved.collection_name
        ? `Ajouté à ${saved.collection_name}`
        : undefined);
    if (!rapidMode) setScanning(false);
    // Refresh collections list after adding
    if (library_id) {
      fetch(`/api/collections?library_id=${library_id}`)
        .then(r => r.json())
        .then(d => Array.isArray(d) ? setCollections(d) : [])
        .catch(console.error);
    }
  }, [rapidMode, push, library_id]);

  if (isFirstUse === null) return null;
  const ready = !!library_id && !!email && !loading;

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

        {isFirstUse
          ? <FirstUseView onStart={() => ready && setScanning(true)} ready={ready} />
          : <ScanButton rapidMode={rapidMode} onStart={() => ready && setScanning(true)} ready={ready} />}
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

function ScanButton({ rapidMode, onStart, ready }: { rapidMode: boolean; onStart: () => void; ready: boolean }) {
  return (
    <div className="flex flex-col items-center gap-4 px-5">
      <button onClick={onStart} disabled={!ready}
        className="w-full py-5 rounded-3xl flex items-center justify-center gap-3 active:scale-95"
        style={{ background: ready ? "var(--accent)" : "var(--surface)", boxShadow: ready ? "0 8px 32px rgba(59,91,255,0.35)" : "none", opacity: ready ? 1 : 0.6, cursor: ready ? "pointer" : "default" }}>
        {!ready
          ? <div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
          : <ScanLine className="w-7 h-7 text-white" />}
        <span className="font-bold text-white" style={{ fontSize: 17 }}>
          {!ready ? "Chargement…" : rapidMode ? "Lancer le mode rapide" : "Ouvrir le scanner"}
        </span>
      </button>
      {ready && <p className="text-center" style={{ fontSize: 13, color: "var(--txt3)" }}>
        {rapidMode ? "Ajout auto si fiable, sinon correction" : "ISBN ou EAN détecté automatiquement"}
      </p>}
    </div>
  );
}

function FirstUseView({ onStart, ready }: { onStart: () => void; ready: boolean }) {
  return (
    <div className="flex flex-col items-center gap-6 px-5">
      <button onClick={onStart} disabled={!ready}
        className="w-32 h-32 rounded-3xl flex flex-col items-center justify-center gap-2 active:scale-95"
        style={{ background: ready ? "var(--accent)" : "var(--surface)", boxShadow: ready ? "0 8px 32px rgba(59,91,255,0.35)" : "none", opacity: ready ? 1 : 0.6 }}>
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
        {["Pointez la caméra vers le code-barres", "La détection est automatique", "Corrigez si besoin, la collection se crée toute seule"].map((text, i) => (
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
git commit -m "feat: scanner v2 — collection dropdown, cover search, reliable add route"
git push
echo "🎉 Déployé !"
