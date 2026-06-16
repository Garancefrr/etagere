#!/bin/bash
set -e
echo "🔍 Recherche de séries dans Google Books..."
cd "$(git rev-parse --show-toplevel)"
mkdir -p src/app/api/series src/app/api/collections/count
cat > "src/app/api/series/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";

interface SeriesSuggestion {
  name: string;
  author?: string;
  total_volumes?: number;
  cover_url?: string;
  book_type: "livre" | "bd" | "manga";
}

export async function GET(req: NextRequest) {
  const q = req.nextUrl.searchParams.get("q");
  if (!q || q.length < 2) return NextResponse.json([]);

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:"${encodeURIComponent(q)}"+Tome&langRestrict=fr&maxResults=20${keyParam}`,
      { signal: AbortSignal.timeout(6000) }
    );
    if (!res.ok) return NextResponse.json([]);

    const data = await res.json();
    if (!data.items?.length) return NextResponse.json([]);

    // Group results by series name and find the highest tome
    const seriesMap = new Map<string, SeriesSuggestion>();

    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.title) continue;

      // Extract series name from title pattern "Series - Tome X"
      const match = vol.title.match(/^(.+?)\s*[-–—]\s*(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i);
      if (!match) continue;

      const seriesName = match[1].trim();
      const tomeNum = parseInt(match[2]);
      const key = seriesName.toLowerCase();

      const existing = seriesMap.get(key);
      const currentMax = existing?.total_volumes ?? 0;

      // Detect type
      const categories = (vol.categories ?? []).join(" ").toLowerCase();
      const allText = categories + " " + vol.title + " " + (vol.publisher ?? "");
      let bookType: "livre" | "bd" | "manga" = "livre";
      if (/manga|manhwa|shonen|shojo|seinen/.test(allText)) bookType = "manga";
      else if (/bande.dessin|bd|comics|dargaud|dupuis|lombard|casterman/.test(allText)) bookType = "bd";

      // Get cover
      let coverUrl = vol.imageLinks?.thumbnail;
      if (coverUrl) coverUrl = coverUrl.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");

      if (tomeNum > currentMax || !existing) {
        seriesMap.set(key, {
          name: seriesName,
          author: vol.authors?.[0],
          total_volumes: Math.max(tomeNum, currentMax),
          cover_url: existing?.cover_url ?? coverUrl,
          book_type: existing?.book_type ?? bookType,
        });
      }
    }

    // Sort by relevance (name closest to query first)
    const results = Array.from(seriesMap.values())
      .sort((a, b) => {
        const aMatch = a.name.toLowerCase().startsWith(q.toLowerCase()) ? 0 : 1;
        const bMatch = b.name.toLowerCase().startsWith(q.toLowerCase()) ? 0 : 1;
        return aMatch - bMatch || a.name.localeCompare(b.name);
      })
      .slice(0, 8);

    return NextResponse.json(results);
  } catch {
    return NextResponse.json([]);
  }
}
FILEOF
cat > "src/app/api/collections/count/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";

export async function GET(req: NextRequest) {
  const series = req.nextUrl.searchParams.get("series");
  if (!series) return NextResponse.json({ total: null });

  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    // Search for all volumes in this series
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:"${encodeURIComponent(series)}"+Tome&langRestrict=fr&maxResults=40&orderBy=relevance${keyParam}`,
      { signal: AbortSignal.timeout(8000) }
    );
    if (!res.ok) return NextResponse.json({ total: null });

    const data = await res.json();
    if (!data.items?.length) return NextResponse.json({ total: null });

    let maxVolume = 0;
    const seriesLower = series.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");

    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.title) continue;

      const titleLower = vol.title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      
      // Check that this result actually matches our series
      const seriesWords = seriesLower.split(/\s+/).filter(w => w.length >= 3);
      const isMatch = seriesWords.every(w => titleLower.includes(w));
      if (!isMatch) continue;

      // Extract volume number from seriesInfo
      const displayNum = item.volumeInfo?.seriesInfo?.bookDisplayNumber;
      if (displayNum) {
        const n = parseInt(displayNum);
        if (n > maxVolume) maxVolume = n;
      }

      // Extract volume number from title (Tome XX, T.XX, Vol.XX)
      const tomeMatch = vol.title.match(/(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i);
      if (tomeMatch) {
        const n = parseInt(tomeMatch[1]);
        if (n > maxVolume) maxVolume = n;
      }
    }

    return NextResponse.json({ 
      total: maxVolume > 0 ? maxVolume : null,
      results_count: data.items.length,
    });
  } catch {
    return NextResponse.json({ total: null });
  }
}
FILEOF
cat > "src/app/api/collections/resolve/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { resolveCollection, patchCollection } from "@/lib/db";
import { BookType } from "@/types";

async function fetchSeriesCount(seriesName: string): Promise<number | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:"${encodeURIComponent(seriesName)}"+Tome&langRestrict=fr&maxResults=40&orderBy=relevance${keyParam}`,
      { signal: AbortSignal.timeout(8000) }
    );
    if (!res.ok) return null;

    const data = await res.json();
    if (!data.items?.length) return null;

    let maxVolume = 0;
    const seriesLower = seriesName.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    const seriesWords = seriesLower.split(/\s+/).filter((w: string) => w.length >= 3);

    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.title) continue;
      const titleLower = vol.title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      if (!seriesWords.every((w: string) => titleLower.includes(w))) continue;

      const displayNum = item.volumeInfo?.seriesInfo?.bookDisplayNumber;
      if (displayNum) { const n = parseInt(displayNum); if (n > maxVolume) maxVolume = n; }

      const tomeMatch = vol.title.match(/(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i);
      if (tomeMatch) { const n = parseInt(tomeMatch[1]); if (n > maxVolume) maxVolume = n; }
    }

    return maxVolume > 0 ? maxVolume : null;
  } catch { return null; }
}

export async function GET(req: NextRequest) {
  const library_id   = req.nextUrl.searchParams.get("library_id");
  const series_name  = req.nextUrl.searchParams.get("series_name");
  const series_index = req.nextUrl.searchParams.get("series_index");
  const book_type    = (req.nextUrl.searchParams.get("book_type") ?? "bd") as BookType;

  if (!library_id || !series_name || !series_index)
    return NextResponse.json({ error: "Paramètres manquants" }, { status: 400 });

  try {
    const { collection, isNew, isNewVolume } = await resolveCollection(
      library_id, series_name, parseInt(series_index), { book_type }
    );

    // Auto-fetch total volumes for new collections
    if (isNew && collection.id) {
      const total = await fetchSeriesCount(series_name);
      if (total) {
        await patchCollection(collection.id, { total_volumes: total });
        collection.total_volumes = total;
      }
    }

    return NextResponse.json({ collection, isNew, isNewVolume });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
FILEOF
cat > "src/app/api/books/lookup/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { lookupISBN } from "@/lib/isbn-lookup";
import { resolveCollection, getCollections, patchCollection } from "@/lib/db";
import { ScanResult, Collection } from "@/types";

function matchCollection(title: string, collections: Collection[]): Collection | null {
  const t = title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  for (const col of collections) {
    const colName = col.name.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    if (t.includes(colName) || colName.includes(t)) return col;
    const words = colName.split(/\s+/).filter(w => w.length >= 3);
    if (words.length > 0 && words.every(w => t.includes(w))) return col;
  }
  return null;
}

async function searchCover(title: string): Promise<string | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";
  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:${encodeURIComponent(`"${title}"`)}&langRestrict=fr&maxResults=5${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.items?.length) return null;
    const titleLower = title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    const titleWords = titleLower.split(/\s+/).filter(w => w.length >= 3);
    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.imageLinks) continue;
      const volTitle = (vol.title ?? "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      if (titleWords.filter(w => volTitle.includes(w)).length < titleWords.length * 0.6) continue;
      let url = vol.imageLinks.large ?? vol.imageLinks.medium ?? vol.imageLinks.thumbnail;
      if (url) url = url.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");
      return url ?? null;
    }
    return null;
  } catch { return null; }
}

async function fetchSeriesCount(seriesName: string): Promise<number | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";
  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:"${encodeURIComponent(seriesName)}"+Tome&langRestrict=fr&maxResults=40${keyParam}`,
      { signal: AbortSignal.timeout(8000) }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.items?.length) return null;
    let maxVolume = 0;
    const seriesLower = seriesName.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    const seriesWords = seriesLower.split(/\s+/).filter((w: string) => w.length >= 3);
    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.title) continue;
      const titleLower = vol.title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      if (!seriesWords.every((w: string) => titleLower.includes(w))) continue;
      const displayNum = item.volumeInfo?.seriesInfo?.bookDisplayNumber;
      if (displayNum) { const n = parseInt(displayNum); if (n > maxVolume) maxVolume = n; }
      const tomeMatch = vol.title.match(/(?:tome|t\.?|vol(?:ume)?\.?)\s*(\d+)/i);
      if (tomeMatch) { const n = parseInt(tomeMatch[1]); if (n > maxVolume) maxVolume = n; }
    }
    return maxVolume > 0 ? maxVolume : null;
  } catch { return null; }
}

export async function GET(req: NextRequest) {
  const isbn        = req.nextUrl.searchParams.get("isbn");
  const library_id  = req.nextUrl.searchParams.get("library_id");

  if (!isbn)       return NextResponse.json({ error: "isbn manquant" },       { status: 400 });
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });

  const book = await lookupISBN(isbn);
  if (!book) return NextResponse.json({ error: "Livre introuvable" }, { status: 404 });

  // Auto-search cover if missing
  if (!book.cover_url && book.title) {
    const cover = await searchCover(book.title);
    if (cover) book.cover_url = cover;
  }

  // Auto-resolve collection for BD/manga with series
  const isSeries = (book.book_type === "bd" || book.book_type === "manga")
    && book.series_name && book.series_index !== undefined;

  if (isSeries) {
    try {
      const { collection, isNew, isNewVolume } = await resolveCollection(
        library_id, book.series_name!, book.series_index!,
        { cover_url: book.cover_url, author: book.authors[0], book_type: book.book_type }
      );
      // Auto-fetch total for new collections
      if (isNew && collection.id) {
        const total = await fetchSeriesCount(book.series_name!);
        if (total) {
          await patchCollection(collection.id, { total_volumes: total });
          collection.total_volumes = total;
        }
      }
      return NextResponse.json({ book, collection, isNewCollection: isNew, isNewVolume } satisfies ScanResult);
    } catch (e: any) {
      console.error("resolveCollection:", e);
    }
  } else if (book.book_type === "bd" || book.book_type === "manga") {
    // Fuzzy match against existing collections
    try {
      const existingCollections = await getCollections(library_id);
      const matched = matchCollection(book.title, existingCollections);
      if (matched) {
        return NextResponse.json({
          book: { ...book, series_name: matched.name },
          collection: matched, isNewCollection: false, isNewVolume: false,
        } satisfies ScanResult);
      }
    } catch (e: any) {
      console.error("matchCollection:", e);
    }
  }

  return NextResponse.json({ book, isNewCollection: false, isNewVolume: false } satisfies ScanResult);
}
FILEOF
cat > "src/components/collection/CollectionCard.tsx" << 'FILEOF'
"use client";
import { Collection } from "@/types";
import { TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";

interface Props {
  collection: Collection;
  onEdit?: () => void;
  onDelete?: () => void;
}

export default function CollectionCard({ collection, onEdit, onDelete }: Props) {
  const { emoji } = TYPE_CONFIG[collection.book_type] ?? { emoji: "📖" };
  const owned = (collection.owned_volumes ?? []).sort((a, b) => a - b);
  const total = collection.total_volumes ?? 0;
  const pct   = total > 0 ? Math.round((owned.length / total) * 100) : 0;

  // Build the list of volumes to display
  // If total is set: show 1..total with green (owned) and red (missing)
  // If total is not set: show only owned volumes in green
  const maxDisplay = total > 0 ? Math.min(total, 40) : owned.length;
  const volumes = total > 0
    ? Array.from({ length: maxDisplay }, (_, i) => i + 1)
    : owned;

  return (
    <div className="rounded-2xl overflow-hidden"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
      <div className="flex gap-3 p-4">
        <Cover src={collection.cover_url} alt={collection.name} width={56} height={78} className="rounded-xl flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="font-bold truncate" style={{ fontSize: 16, color: "var(--txt1)" }}>{collection.name}</p>
              {collection.author && <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{collection.author}</p>}
            </div>
            <span style={{ fontSize: 14, flexShrink: 0 }}>{emoji}</span>
          </div>

          {/* Progress bar — only if total is set */}
          {total > 0 && (
            <div className="flex items-center gap-2 mt-3">
              <div className="flex-1 h-2 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
                <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
              </div>
              <span className="font-bold flex-shrink-0" style={{ fontSize: 13, color: "var(--accent)" }}>
                {owned.length}/{total}
              </span>
            </div>
          )}

          {/* Count without bar — when total is not set */}
          {total === 0 && owned.length > 0 && (
            <p className="mt-2 font-semibold" style={{ fontSize: 13, color: "var(--accent)" }}>
              {owned.length} tome{owned.length > 1 ? "s" : ""}
            </p>
          )}
        </div>
      </div>

      {/* Volume chips */}
      {volumes.length > 0 && (
        <div className="flex flex-wrap gap-1.5 px-4 pb-4">
          {volumes.map(n => {
            const isOwned = owned.includes(n);
            return (
              <div key={n} className="flex items-center justify-center font-bold"
                style={{
                  width: 30, height: 30, borderRadius: 8, fontSize: 11,
                  background: isOwned ? "var(--have-bg)" : "var(--miss-bg)",
                  color:      isOwned ? "var(--have-t)"  : "var(--miss-t)",
                  border:     isOwned ? "1px solid var(--have-b)" : "1px dashed var(--miss-b)",
                }}>
                {n}
              </div>
            );
          })}
          {total > 40 && (
            <div className="flex items-center justify-center font-bold"
              style={{ width: 30, height: 30, borderRadius: 8, fontSize: 11, background: "var(--accent-l)", color: "var(--accent)" }}>
              +{total - 40}
            </div>
          )}
        </div>
      )}

      {/* Actions */}
      {(onEdit || onDelete) && (
        <div className="flex gap-2 px-4 pb-4">
          {onEdit && (
            <button onClick={onEdit} className="flex-1 py-2 rounded-xl font-semibold text-center"
              style={{ fontSize: 12, background: "var(--surface2)", color: "var(--txt2)", border: "1px solid var(--border)" }}>
              ✏️ Modifier
            </button>
          )}
          {onDelete && (
            <button onClick={onDelete} className="py-2 px-4 rounded-xl font-semibold"
              style={{ fontSize: 12, background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px solid var(--miss-b)" }}>
              🗑️
            </button>
          )}
        </div>
      )}
    </div>
  );
}
FILEOF
cat > "src/app/collections/page.tsx" << 'FILEOF'
"use client";
import { useState, useEffect, useRef } from "react";
import { Collection, BookType } from "@/types";
import { useLibrary } from "@/hooks/useLibrary";
import CollectionCard from "@/components/collection/CollectionCard";
import BottomNav from "@/components/layout/BottomNav";
import { Button } from "@/components/ui/Button";
import { Cover } from "@/components/ui/Cover";
import { Search, Plus, X, Share2, Check, MessageCircle } from "lucide-react";

interface SeriesSuggestion {
  name: string;
  author?: string;
  total_volumes?: number;
  cover_url?: string;
  book_type: "livre" | "bd" | "manga";
}

function CreateModal({ onClose, onCreate }: { onClose: () => void; onCreate: (c: Partial<Collection>) => void }) {
  const [name,        setName]        = useState("");
  const [type,        setType]        = useState<BookType>("bd");
  const [author,      setAuthor]      = useState("");
  const [total,       setTotal]       = useState("");
  const [coverUrl,    setCoverUrl]    = useState<string | undefined>();
  const [suggestions, setSuggestions] = useState<SeriesSuggestion[]>([]);
  const [searching,   setSearching]   = useState(false);
  const timerRef = useRef<NodeJS.Timeout | null>(null);

  // Debounced search
  const handleNameChange = (value: string) => {
    setName(value);
    if (timerRef.current) clearTimeout(timerRef.current);
    if (value.length < 2) { setSuggestions([]); return; }
    setSearching(true);
    timerRef.current = setTimeout(async () => {
      try {
        const res = await fetch(`/api/series?q=${encodeURIComponent(value)}`);
        if (res.ok) setSuggestions(await res.json());
      } catch { /* ignore */ }
      setSearching(false);
    }, 400);
  };

  const selectSuggestion = (s: SeriesSuggestion) => {
    setName(s.name);
    setAuthor(s.author ?? "");
    setTotal(s.total_volumes?.toString() ?? "");
    setType(s.book_type);
    setCoverUrl(s.cover_url);
    setSuggestions([]);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)", maxHeight: "90vh", overflowY: "auto" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-5">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Nouvelle collection</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}>
            <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
          </button>
        </div>
        <div className="space-y-4">
          {/* Name with API search */}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>
              Nom de la série
            </label>
            <div className="relative">
              <div className="flex items-center gap-2 px-4 py-3 rounded-2xl"
                style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                <Search className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
                <input type="text" value={name} onChange={e => handleNameChange(e.target.value)}
                  placeholder="Rechercher une série..."
                  className="flex-1 outline-none bg-transparent"
                  style={{ color: "var(--txt1)", fontSize: 15 }} />
                {searching && (
                  <div className="w-4 h-4 rounded-full border-2 animate-spin flex-shrink-0"
                    style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
                )}
              </div>

              {/* Suggestions dropdown */}
              {suggestions.length > 0 && (
                <div className="absolute left-0 right-0 top-full mt-1 rounded-2xl overflow-hidden z-20 max-h-64 overflow-y-auto"
                  style={{ background: "var(--surface2)", border: "1px solid var(--border)", boxShadow: "0 8px 24px rgba(0,0,0,0.4)" }}>
                  {suggestions.map(s => (
                    <button key={s.name} onClick={() => selectSuggestion(s)}
                      className="w-full flex items-center gap-3 px-4 py-3 text-left active:opacity-70"
                      style={{ borderBottom: "1px solid var(--border)" }}>
                      <Cover src={s.cover_url} alt={s.name} width={36} height={50} className="rounded-lg flex-shrink-0" />
                      <div className="flex-1 min-w-0">
                        <p className="font-semibold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{s.name}</p>
                        <p style={{ fontSize: 12, color: "var(--txt2)", marginTop: 1 }}>
                          {s.author ?? ""}{s.total_volumes ? ` · ${s.total_volumes} tomes` : ""}
                        </p>
                      </div>
                      <span style={{ fontSize: 12, color: "var(--accent)", fontWeight: 600, flexShrink: 0 }}>
                        {s.book_type === "bd" ? "🎨" : s.book_type === "manga" ? "⛩️" : "📖"}
                      </span>
                    </button>
                  ))}
                </div>
              )}
            </div>
            <p style={{ fontSize: 11, color: "var(--txt3)", marginTop: 4 }}>
              Tape le nom pour chercher dans Google Books
            </p>
          </div>

          {/* Preview if suggestion selected */}
          {coverUrl && (
            <div className="flex items-center gap-3 p-3 rounded-2xl" style={{ background: "var(--have-bg)", border: "1px solid var(--have-b)" }}>
              <Check className="w-4 h-4 flex-shrink-0" style={{ color: "var(--have-t)" }} />
              <p style={{ fontSize: 13, color: "var(--have-t)", fontWeight: 600 }}>
                {name} — {total} tomes · {author}
              </p>
            </div>
          )}

          {/* Type */}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Type</label>
            <div className="flex gap-2">
              {(["livre","bd","manga"] as BookType[]).map(t => (
                <button key={t} onClick={() => setType(t)} className="flex-1 py-2.5 rounded-xl font-semibold"
                  style={{ fontSize: 13, background: type === t ? "var(--accent)" : "var(--surface2)", color: type === t ? "#fff" : "var(--txt2)", border: `1px solid ${type === t ? "var(--accent)" : "var(--border)"}` }}>
                  {t === "livre" ? "📖 Livre" : t === "bd" ? "🎨 BD" : "⛩️ Manga"}
                </button>
              ))}
            </div>
          </div>

          {/* Author */}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Auteur</label>
            <input type="text" value={author} onChange={e => setAuthor(e.target.value)} placeholder="Ex: Peyo..."
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>

          {/* Total volumes */}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Nombre total de tomes</label>
            <input type="number" value={total} onChange={e => setTotal(e.target.value)} placeholder="Ex: 40"
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>

          <Button onClick={() => {
            if (name.trim()) {
              onCreate({
                name: name.trim(), book_type: type,
                author: author.trim() || undefined,
                total_volumes: total ? parseInt(total) : undefined,
                cover_url: coverUrl,
                owned_volumes: [],
              });
              onClose();
            }
          }} className="w-full py-4 rounded-2xl" style={{ fontSize: 15 }}>
            Créer la collection
          </Button>
        </div>
      </div>
    </div>
  );
}

function ShareModal({ collection, profileId, onClose }: { collection: Collection; profileId: string; onClose: () => void }) {
  const [link, setLink]     = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    fetch("/api/share", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ collection_id: collection.id, profile_id: profileId }) })
      .then(r => r.json()).then(d => setLink(`${window.location.origin}/share/${d.token}`));
  }, [collection.id, profileId]);
  const copy = () => { if (!link) return; navigator.clipboard.writeText(link); setCopied(true); setTimeout(() => setCopied(false), 2000); };
  const shareVia = (m: "whatsapp"|"sms") => { if (!link) return; const t = `👀 Regarde ma collection "${collection.name}" sur Folio : ${link}`; window.open(m === "whatsapp" ? `https://wa.me/?text=${encodeURIComponent(t)}` : `sms:?body=${encodeURIComponent(t)}`); };
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Partager</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}><X className="w-4 h-4" style={{ color: "var(--txt2)" }} /></button>
        </div>
        {!link ? <div className="flex justify-center py-6"><div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} /></div> : (
          <div className="flex flex-col gap-3">
            <div className="px-3 py-2 rounded-xl truncate" style={{ background: "var(--surface2)", border: "1px solid var(--border)", fontSize: 12, color: "var(--txt3)" }}>{link}</div>
            <button onClick={() => shareVia("whatsapp")} className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3" style={{ background: "#25D366", color: "#fff", fontSize: 15 }}><MessageCircle className="w-5 h-5" /> WhatsApp</button>
            <button onClick={() => shareVia("sms")} className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3" style={{ background: "var(--surface2)", color: "var(--txt1)", fontSize: 15, border: "1px solid var(--border)" }}><MessageCircle className="w-5 h-5" /> SMS / iMessage</button>
            <button onClick={copy} className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3" style={{ background: copied ? "var(--have-bg)" : "var(--accent-l)", color: copied ? "var(--have-t)" : "var(--accent)", fontSize: 15 }}>
              {copied ? <Check className="w-5 h-5" /> : <Share2 className="w-5 h-5" />}{copied ? "Copié !" : "Copier le lien"}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

function EditModal({ collection, onClose, onSave }: { collection: Collection; onClose: () => void; onSave: (id: string, updates: Partial<Collection>) => void }) {
  const [name,   setName]   = useState(collection.name);
  const [author, setAuthor] = useState(collection.author ?? "");
  const [total,  setTotal]  = useState(collection.total_volumes?.toString() ?? "");
  const [type,   setType]   = useState<BookType>(collection.book_type);
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-5">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Modifier</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}><X className="w-4 h-4" style={{ color: "var(--txt2)" }} /></button>
        </div>
        <div className="space-y-4">
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Nom</label>
            <input type="text" value={name} onChange={e => setName(e.target.value)} className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Auteur</label>
            <input type="text" value={author} onChange={e => setAuthor(e.target.value)} className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Nombre total de tomes</label>
            <input type="number" value={total} onChange={e => setTotal(e.target.value)} className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Type</label>
            <div className="flex gap-2">
              {(["livre","bd","manga"] as BookType[]).map(t => (
                <button key={t} onClick={() => setType(t)} className="flex-1 py-2.5 rounded-xl font-semibold"
                  style={{ fontSize: 13, background: type === t ? "var(--accent)" : "var(--surface2)", color: type === t ? "#fff" : "var(--txt2)", border: `1px solid ${type === t ? "var(--accent)" : "var(--border)"}` }}>
                  {t === "livre" ? "📖 Livre" : t === "bd" ? "🎨 BD" : "⛩️ Manga"}
                </button>
              ))}
            </div>
          </div>
          <Button onClick={() => { if (name.trim()) onSave(collection.id, { name: name.trim(), author: author.trim() || undefined, total_volumes: total ? parseInt(total) : undefined, book_type: type }); }}
            className="w-full py-4 rounded-2xl" style={{ fontSize: 15 }}>Enregistrer</Button>
        </div>
      </div>
    </div>
  );
}

type Filter = "all" | "bd" | "manga" | "livre";

export default function CollectionsPage() {
  const { library_id, profile_id, loading: libLoading } = useLibrary();
  const [collections,     setCollections]    = useState<Collection[]>([]);
  const [colLoading,      setColLoading]     = useState(false);
  const [search,          setSearch]         = useState("");
  const [filter,          setFilter]         = useState<Filter>("all");
  const [showCreate,      setShowCreate]     = useState(false);
  const [shareCol,        setShareCol]       = useState<Collection | null>(null);
  const [editCol,         setEditCol]        = useState<Collection | null>(null);
  const [deleteId,        setDeleteId]       = useState<string | null>(null);

  useEffect(() => {
    if (!library_id) return;
    setColLoading(true);
    fetch(`/api/collections?library_id=${library_id}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setCollections(d) : [])
      .catch(console.error)
      .finally(() => setColLoading(false));
  }, [library_id]);

  const handleCreate = async (data: Partial<Collection>) => {
    if (!library_id) return;
    const res = await fetch("/api/collections", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...data, library_id, owned_volumes: data.owned_volumes ?? [] }) });
    if (res.ok) { const col = await res.json(); setCollections(prev => [col, ...prev]); }
  };

  const handleEdit = async (id: string, updates: Partial<Collection>) => {
    await fetch("/api/collections", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id, ...updates }) });
    setCollections(prev => prev.map(c => c.id === id ? { ...c, ...updates } : c));
    setEditCol(null);
  };

  const handleDelete = async (id: string) => {
    await fetch("/api/collections", { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id }) });
    setCollections(prev => prev.filter(c => c.id !== id));
    setDeleteId(null);
  };

  const filtered = collections.filter(c =>
    (filter === "all" || c.book_type === filter) &&
    (!search || c.name.toLowerCase().includes(search.toLowerCase()) || c.author?.toLowerCase().includes(search.toLowerCase()))
  );
  const loading = libLoading || colLoading;

  return (
    <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="sticky top-0 z-30 px-4 pt-12 pb-3" style={{ background: "var(--bg)" }}>
        <div className="flex items-center justify-between mb-4">
          <div>
            <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Collections</p>
            <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>{collections.length} <span style={{ fontSize: 16, fontWeight: 400, opacity: 0.35 }}>séries</span></h1>
          </div>
          <button onClick={() => setShowCreate(true)} className="w-11 h-11 rounded-2xl flex items-center justify-center active:scale-95" style={{ background: "var(--accent)" }}><Plus className="w-5 h-5 text-white" /></button>
        </div>
        <div className="flex items-center gap-2 px-4 py-3 rounded-2xl mb-3" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          <Search className="w-5 h-5" style={{ color: "var(--txt3)" }} />
          <input type="text" value={search} onChange={e => setSearch(e.target.value)} placeholder="Rechercher..." className="flex-1 outline-none bg-transparent" style={{ color: "var(--txt1)", fontSize: 15 }} />
        </div>
        <div className="flex gap-2 overflow-x-auto pb-1" style={{ scrollbarWidth: "none" }}>
          {(["all","livre","bd","manga"] as Filter[]).map(f => (
            <button key={f} onClick={() => setFilter(f)} className="flex-shrink-0 px-4 py-2 rounded-full font-semibold"
              style={{ fontSize: 13, background: filter === f ? "var(--accent)" : "var(--surface)", color: filter === f ? "#fff" : "var(--txt2)", border: `1px solid ${filter === f ? "var(--accent)" : "var(--border)"}` }}>
              {f === "all" ? "Toutes" : f === "livre" ? "📖 Livres" : f === "bd" ? "🎨 BD" : "⛩️ Manga"}
            </button>
          ))}
        </div>
      </div>

      <div className="px-4 flex flex-col gap-4">
        {loading ? (
          <div className="flex justify-center py-20"><div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} /></div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center py-20 gap-4">
            <p className="font-semibold" style={{ fontSize: 17, color: "var(--txt1)" }}>Aucune collection</p>
            <Button onClick={() => setShowCreate(true)}>+ Créer une collection</Button>
          </div>
        ) : filtered.map(c => (
          <div key={c.id}>
            <CollectionCard collection={c} onEdit={() => setEditCol(c)} onDelete={() => setDeleteId(c.id)} />
            {deleteId === c.id && (
              <div className="flex gap-2 mt-2">
                <button onClick={() => handleDelete(c.id)} className="flex-1 py-3 rounded-2xl font-semibold"
                  style={{ background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px solid var(--miss-b)", fontSize: 13 }}>
                  Confirmer la suppression
                </button>
                <button onClick={() => setDeleteId(null)} className="px-4 py-3 rounded-2xl font-semibold"
                  style={{ background: "var(--surface)", color: "var(--txt2)", border: "1px solid var(--border)", fontSize: 13 }}>
                  Annuler
                </button>
              </div>
            )}
            <button onClick={() => setShareCol(c)} className="w-full mt-2 py-3 rounded-2xl font-semibold flex items-center justify-center gap-2 active:scale-95"
              style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt2)", fontSize: 13 }}>
              <Share2 className="w-4 h-4" style={{ color: "var(--accent)" }} /> Partager
            </button>
          </div>
        ))}
      </div>

      {showCreate && <CreateModal onClose={() => setShowCreate(false)} onCreate={handleCreate} />}
      {editCol && <EditModal collection={editCol} onClose={() => setEditCol(null)} onSave={handleEdit} />}
      {shareCol && profile_id && <ShareModal collection={shareCol} profileId={profile_id} onClose={() => setShareCol(null)} />}
      <BottomNav />
    </div>
  );
}
FILEOF
git add -A
git commit -m "feat: API-powered series search, auto volume count, green/red chips"
git push
echo "🎉 Déployé !"
