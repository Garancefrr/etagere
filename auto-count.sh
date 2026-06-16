#!/bin/bash
set -e
echo "📊 Auto-détection nombre de tomes + chips verts/rouges..."
cd "$(git rev-parse --show-toplevel)"
mkdir -p src/app/api/collections/count
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
git add -A
git commit -m "feat: auto-fetch series volume count from Google Books, show green/red chips"
git push
echo "🎉 Déployé !"
