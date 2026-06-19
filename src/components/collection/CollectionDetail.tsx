"use client";
import { useState, useEffect } from "react";
import { Collection, Book } from "@/types";
import { TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { X, Edit2, Trash2 } from "lucide-react";

interface RemoteBook {
  title: string;
  isbn?: string;
  cover_url?: string | null;
  published_year?: number | null;
  series_index?: number | null;
  owned?: Book;
}

interface Props {
  collection: Collection;
  books: Book[];
  onClose: () => void;
  onEdit: () => void;
  onDelete: () => void;
  onShare?: () => void;
}

export default function CollectionDetail({ collection, books, onClose, onEdit, onDelete, onShare }: Props) {
  const { emoji } = TYPE_CONFIG[collection.book_type] ?? { emoji: "📖" };
  const ownedNums = Array.from(new Set(collection.owned_volumes ?? [])).sort((a, b) => a - b);
  const total = collection.total_volumes ?? 0;
  const [confirmDel, setConfirmDel] = useState(false);
  const [remoteBooks, setRemoteBooks] = useState<RemoteBook[]>([]);
  const [loading, setLoading] = useState(false);

  const isBdManga = collection.book_type === "bd" || collection.book_type === "manga";
  const hasTotalVolumes = total > 0;
  const viewMode = isBdManga || hasTotalVolumes ? "numbered" : "grid";

  const ownedBooks = books.filter(b =>
    b.series_name?.toLowerCase().trim() === collection.name.toLowerCase().trim() ||
    (collection.author && b.authors.some(a => a.toLowerCase().trim() === collection.author!.toLowerCase().trim()))
  );
  const luCount = ownedBooks.filter(b => b.status === "lu").length;
  const enCoursCount = ownedBooks.filter(b => b.status === "en_cours").length;
  const aLireCount = ownedBooks.filter(b => b.status === "a_lire").length;
  const pct = hasTotalVolumes
    ? Math.round((ownedNums.length / total) * 100)
    : ownedBooks.length > 0 ? Math.round((luCount / ownedBooks.length) * 100) : 0;

  useEffect(() => {
    if (viewMode === "numbered") return;
    setLoading(true);
    const query = collection.author ?? collection.name;
    fetch(`/api/authors/books?author=${encodeURIComponent(query)}`)
      .then(r => r.json())
      .then((results: any[]) => {
        const mapped: RemoteBook[] = results.map(r => ({
          title: r.title, isbn: r.isbn, cover_url: r.cover_url,
          published_year: r.published_year, series_index: r.series_index,
          owned: ownedBooks.find(b => b.title.toLowerCase().trim() === r.title.toLowerCase().trim() || (b.isbn && b.isbn === r.isbn)),
        }));
        ownedBooks.forEach(ob => {
          if (!mapped.some(m => m.owned?.id === ob.id))
            mapped.push({ title: ob.title, isbn: ob.isbn ?? undefined, cover_url: ob.cover_url, series_index: ob.series_index, owned: ob });
        });
        const so = (rb: RemoteBook) => !rb.owned ? 4 : rb.owned.status === "en_cours" ? 0 : rb.owned.status === "a_lire" ? 1 : 2;
        mapped.sort((a, b) => so(a) - so(b) || a.title.localeCompare(b.title));
        setRemoteBooks(mapped);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [collection.name, collection.author, viewMode]); // eslint-disable-line

  const statusTag = (b?: Book) => {
    if (!b) return { label: "Non possédé", bg: "var(--surface2)", color: "var(--txt3)", border: true };
    if (b.status === "lu")       return { label: "Lu",       bg: "var(--have-bg)", color: "var(--have-t)", border: false };
    if (b.status === "en_cours") return { label: "En cours", bg: "#FEF9C3",        color: "#A16207",      border: false };
    return                              { label: "À lire",   bg: "var(--accent-l)", color: "var(--accent)", border: false };
  };

  const displayBooks = remoteBooks.length > 0
    ? remoteBooks
    : ownedBooks.map(b => ({ title: b.title, cover_url: b.cover_url, series_index: b.series_index, owned: b } as RemoteBook));
  const nonOwnedCount = remoteBooks.filter(b => !b.owned).length;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full sm:max-w-md rounded-t-3xl overflow-hidden flex flex-col"
        style={{ background: "var(--surface)", maxHeight: "92vh" }}>
        <div className="flex justify-center pt-2 flex-shrink-0">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>

        {/* Header */}
        <div className="px-4 pt-1 pb-2 flex-shrink-0" style={{ borderBottom: "1px solid var(--border)" }}>
          <div className="flex items-center gap-2 mb-1">
            <p className="font-bold flex-1 truncate" style={{ fontSize: 16, color: "var(--txt1)" }}>{emoji} {collection.name}</p>
            <div className="flex gap-1 flex-shrink-0">
              {onShare && <button onClick={onShare} className="w-9 h-9 rounded-xl flex items-center justify-center" style={{ background: "var(--surface2)" }}>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{ color: "var(--accent)" }}><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>
              </button>}
              <button onClick={onEdit} className="w-9 h-9 rounded-xl flex items-center justify-center" style={{ background: "var(--surface2)" }}>
                <Edit2 className="w-4 h-4" style={{ color: "var(--txt2)" }} />
              </button>
              {!confirmDel
                ? <button onClick={() => setConfirmDel(true)} className="w-9 h-9 rounded-xl flex items-center justify-center" style={{ background: "var(--miss-bg)" }}>
                    <Trash2 className="w-4 h-4" style={{ color: "var(--miss-t)" }} />
                  </button>
                : <button onClick={onDelete} className="px-3 h-9 rounded-xl font-bold" style={{ fontSize: 11, background: "var(--miss-t)", color: "#fff" }}>Suppr</button>}
              <button onClick={onClose} className="w-6 h-6 rounded-md flex items-center justify-center" style={{ background: "var(--surface2)" }}>
                <X className="w-3 h-3" style={{ color: "var(--txt2)" }} />
              </button>
            </div>
          </div>
          <div className="flex items-center gap-2 flex-wrap">
            {collection.author && <span style={{ fontSize: 11, color: "var(--txt3)" }}>{collection.author}</span>}
            {enCoursCount > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 11, background: "#FEF9C3", color: "#A16207" }}>📖 {enCoursCount}</span>}
            {aLireCount > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 11, background: "var(--accent-l)", color: "var(--accent)" }}>📌 {aLireCount}</span>}
            {luCount > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 11, background: "var(--have-bg)", color: "var(--have-t)" }}>✅ {luCount}</span>}
            {nonOwnedCount > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 11, background: "var(--surface2)", color: "var(--txt3)" }}>📕 {nonOwnedCount}</span>}
          </div>
          <div className="h-1 rounded-full overflow-hidden mt-1.5" style={{ background: "var(--border)" }}>
            <div className="h-full rounded-full" style={{ width: `${Math.max(pct, 2)}%`, background: pct === 100 ? "var(--have-t)" : "var(--accent)" }} />
          </div>
        </div>

        {/* Content */}
        <div className="overflow-y-auto flex-1 p-3">
          {/* Numbered chips for BD/manga */}
          {viewMode === "numbered" && (
            <div className="flex flex-wrap gap-1">
              {(total > 0 ? Array.from({ length: Math.min(total, 50) }, (_, i) => i + 1) : ownedNums).map(n => {
                const isOwned = ownedNums.includes(n);
                return (
                  <div key={n} className="flex items-center justify-center font-bold"
                    style={{ width: 28, height: 28, borderRadius: 6, fontSize: 10,
                      background: isOwned ? "var(--have-bg)" : "var(--miss-bg)",
                      color: isOwned ? "var(--have-t)" : "var(--miss-t)",
                      border: isOwned ? "1px solid var(--have-b)" : "1px dashed var(--miss-b)" }}>
                    {n}
                  </div>
                );
              })}
            </div>
          )}

          {/* Grid for books */}
          {viewMode === "grid" && (
            <>
              {loading && <div className="flex justify-center py-8"><div className="w-5 h-5 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} /></div>}
              {!loading && (
                <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10 }}>
                  {displayBooks.map((rb, i) => {
                    const s = statusTag(rb.owned);
                    return (
                      <div key={i} className="flex flex-col"
                        style={{ opacity: rb.owned ? 1 : 0.45 }}>
                        <div className="relative w-full" style={{ aspectRatio: "2/3" }}>
                          <Cover src={rb.cover_url ?? undefined} alt={rb.title} className="w-full h-full rounded-lg" />
                          <span className="absolute bottom-0 left-0 right-0 text-center py-0.5 font-bold"
                            style={{
                              fontSize: 10, background: s.bg, color: s.color,
                              borderRadius: "0 0 8px 8px",
                              border: s.border ? "1px dashed var(--border)" : "none",
                              borderTop: "none",
                            }}>
                            {s.label}
                          </span>
                        </div>
                        <div style={{ height: 28 }}>
                          <p className="font-semibold mt-1 line-clamp-2" style={{ fontSize: 10, color: rb.owned ? "var(--txt1)" : "var(--txt3)", lineHeight: 1.2 }}>
                            {rb.title}
                          </p>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
