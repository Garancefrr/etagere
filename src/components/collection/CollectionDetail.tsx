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
  const pct = total > 0 ? Math.round((ownedNums.length / total) * 100) : 0;
  const [confirmDel, setConfirmDel] = useState(false);
  const [remoteBooks, setRemoteBooks] = useState<RemoteBook[]>([]);
  const [loading, setLoading] = useState(false);

  // Determine view mode:
  // "numbered" = BD/manga with numbered chips
  // "series" = book series (search by series name)
  // "author" = author collection (search by author name)
  const hasTotalVolumes = total > 0;
  const isBdManga = collection.book_type === "bd" || collection.book_type === "manga";
  const viewMode = isBdManga || hasTotalVolumes ? "numbered" : collection.author ? "author" : "series";

  // Books in this collection from user's library
  const ownedBooks = books.filter(b =>
    b.series_name?.toLowerCase().trim() === collection.name.toLowerCase().trim() ||
    (collection.author && b.authors.some(a =>
      a.toLowerCase().trim() === collection.author!.toLowerCase().trim()
    ))
  );

  // Fetch remote books for series/author view
  useEffect(() => {
    if (viewMode === "numbered") return;
    setLoading(true);

    const query = viewMode === "author"
      ? collection.author!
      : collection.name;

    fetch(`/api/books/search?q=${encodeURIComponent(query)}`)
      .then(r => r.json())
      .then((results: any[]) => {
        // For author: keep only books by this exact author
        // For series: keep only books matching the series name
        const filtered = results.filter(r => {
          if (viewMode === "author") {
            return r.authors?.some((a: string) =>
              a.toLowerCase().includes(collection.author!.toLowerCase()) ||
              collection.author!.toLowerCase().includes(a.toLowerCase().split(" ").pop() ?? "")
            );
          } else {
            // Series: title contains collection name or series_name matches
            return r.title.toLowerCase().includes(collection.name.toLowerCase()) ||
              r.series_name?.toLowerCase().includes(collection.name.toLowerCase());
          }
        });

        // Map owned books
        const mapped: RemoteBook[] = filtered.map(r => ({
          title: r.title,
          isbn: r.isbn,
          cover_url: r.cover_url,
          published_year: r.published_year,
          series_index: r.series_index,
          owned: ownedBooks.find(b =>
            b.title.toLowerCase() === r.title.toLowerCase() ||
            (b.isbn && b.isbn === r.isbn)
          ),
        }));

        // Add owned books not found in remote results
        ownedBooks.forEach(ob => {
          if (!mapped.some(m => m.owned?.id === ob.id)) {
            mapped.push({
              title: ob.title, isbn: ob.isbn ?? undefined,
              cover_url: ob.cover_url, series_index: ob.series_index,
              owned: ob,
            });
          }
        });

        // Sort: owned first (en_cours > a_lire > lu > non possédé), then by series_index or title
        const statusOrder = (b: RemoteBook) => {
          if (!b.owned) return 4;
          if (b.owned.status === "en_cours") return 0;
          if (b.owned.status === "a_lire")   return 1;
          return 2; // lu
        };
        mapped.sort((a, b) => {
          const so = statusOrder(a) - statusOrder(b);
          if (so !== 0) return so;
          if (a.series_index && b.series_index) return a.series_index - b.series_index;
          if (a.series_index) return -1;
          if (b.series_index) return 1;
          return a.title.localeCompare(b.title);
        });

        setRemoteBooks(mapped);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [collection.name, collection.author, viewMode]); // eslint-disable-line

  const statusBadge = (b: Book) => {
    if (b.status === "lu")       return { label: "Lu",       bg: "var(--have-bg)", color: "var(--have-t)" };
    if (b.status === "en_cours") return { label: "En cours", bg: "#FEF9C3",        color: "#A16207" };
    return                              { label: "À lire",   bg: "var(--accent-l)", color: "var(--accent)" };
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full sm:max-w-md rounded-t-3xl overflow-hidden flex flex-col"
        style={{ background: "var(--surface)", maxHeight: "90vh" }}>

        {/* Handle */}
        <div className="flex justify-center pt-3 flex-shrink-0">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>

        {/* Header */}
        <div className="flex items-center gap-3 px-4 py-3 flex-shrink-0"
          style={{ borderBottom: "1px solid var(--border)" }}>
          <Cover src={collection.cover_url} alt={collection.name} width={50} height={70} className="rounded-xl flex-shrink-0" />
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5 mb-0.5">
              <span style={{ fontSize: 12 }}>{emoji}</span>
              <p className="font-bold truncate" style={{ fontSize: 16, color: "var(--txt1)" }}>{collection.name}</p>
            </div>
            {collection.author && <p style={{ fontSize: 12, color: "var(--txt2)" }}>{collection.author}</p>}
            {total > 0 ? (
              <div className="flex items-center gap-2 mt-1.5">
                <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
                  <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
                </div>
                <span className="font-semibold flex-shrink-0" style={{ fontSize: 11, color: "var(--accent)" }}>
                  {ownedNums.length}/{total}
                </span>
              </div>
            ) : (
              <p style={{ fontSize: 11, color: "var(--accent)", marginTop: 2 }}>
                {ownedBooks.length} {ownedBooks.length > 1 ? "livres" : "livre"} possédé{ownedBooks.length > 1 ? "s" : ""}
              </p>
            )}
          </div>

          {/* Actions */}
          <div className="flex gap-1.5 flex-shrink-0">
            {onShare && (
              <button onClick={onShare} className="w-8 h-8 rounded-xl flex items-center justify-center"
                style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ color: "var(--accent)" }}>
                  <circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/>
                  <line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/>
                </svg>
              </button>
            )}
            <button onClick={onEdit} className="w-8 h-8 rounded-xl flex items-center justify-center"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
              <Edit2 className="w-3.5 h-3.5" style={{ color: "var(--txt2)" }} />
            </button>
            {!confirmDel ? (
              <button onClick={() => setConfirmDel(true)} className="w-8 h-8 rounded-xl flex items-center justify-center"
                style={{ background: "var(--miss-bg)", border: "1px solid var(--miss-b)" }}>
                <Trash2 className="w-3.5 h-3.5" style={{ color: "var(--miss-t)" }} />
              </button>
            ) : (
              <button onClick={onDelete} className="px-2 h-8 rounded-xl font-bold"
                style={{ fontSize: 10, background: "var(--miss-t)", color: "#fff" }}>
                Confirmer ?
              </button>
            )}
            <button onClick={onClose} className="w-8 h-8 rounded-xl flex items-center justify-center"
              style={{ background: "var(--surface2)" }}>
              <X className="w-3.5 h-3.5" style={{ color: "var(--txt2)" }} />
            </button>
          </div>
        </div>

        {/* Content */}
        <div className="overflow-y-auto flex-1">

          {/* NUMBERED view — BD/manga chips */}
          {viewMode === "numbered" && (
            <div className="p-4">
              {total > 0 && (
                <p className="text-xs font-bold uppercase tracking-wider mb-3" style={{ color: "var(--txt3)" }}>Tomes</p>
              )}
              <div className="flex flex-wrap gap-1.5">
                {(total > 0
                  ? Array.from({ length: Math.min(total, 40) }, (_, i) => i + 1)
                  : ownedNums
                ).map(n => {
                  const isOwned = ownedNums.includes(n);
                  return (
                    <div key={n} className="flex items-center justify-center font-bold"
                      style={{ width: 32, height: 32, borderRadius: 8, fontSize: 11,
                        background: isOwned ? "var(--have-bg)" : "var(--miss-bg)",
                        color: isOwned ? "var(--have-t)" : "var(--miss-t)",
                        border: isOwned ? "1px solid var(--have-b)" : "1px dashed var(--miss-b)" }}>
                      {n}
                    </div>
                  );
                })}
                {total > 40 && (
                  <div className="flex items-center justify-center font-bold"
                    style={{ width: 32, height: 32, borderRadius: 8, fontSize: 11, background: "var(--accent-l)", color: "var(--accent)" }}>
                    +{total - 40}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* SERIES / AUTHOR view — book list with status */}
          {(viewMode === "series" || viewMode === "author") && (
            <div>
              {loading && (
                <div className="flex justify-center py-8">
                  <div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
                </div>
              )}

              {!loading && remoteBooks.length === 0 && ownedBooks.length > 0 && (
                /* Fallback: just show owned books if no remote results */
                ownedBooks.map(b => {
                  const s = statusBadge(b);
                  return (
                    <div key={b.id} className="flex items-center gap-3 px-4 py-3" style={{ borderBottom: "1px solid var(--border)" }}>
                      <Cover src={b.cover_url} alt={b.title} width={38} height={52} className="rounded-lg flex-shrink-0" />
                      <div className="flex-1 min-w-0">
                        <p className="font-semibold truncate" style={{ fontSize: 13, color: "var(--txt1)" }}>{b.title}</p>
                        {b.series_index && <p style={{ fontSize: 11, color: "var(--txt3)", marginTop: 1 }}>Tome {b.series_index}</p>}
                      </div>
                      <span className="px-2 py-1 rounded-lg font-semibold flex-shrink-0"
                        style={{ fontSize: 10, background: s.bg, color: s.color }}>{s.label}</span>
                    </div>
                  );
                })
              )}

              {!loading && remoteBooks.map((rb, i) => {
                const s = rb.owned ? statusBadge(rb.owned) : null;
                return (
                  <div key={i} className="flex items-center gap-3 px-4 py-3" style={{ borderBottom: "1px solid var(--border)" }}>
                    <Cover src={rb.cover_url ?? undefined} alt={rb.title} width={38} height={52} className="rounded-lg flex-shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="font-semibold truncate" style={{ fontSize: 13, color: rb.owned ? "var(--txt1)" : "var(--txt3)" }}>{rb.title}</p>
                      <p style={{ fontSize: 11, color: "var(--txt3)", marginTop: 1 }}>
                        {[rb.series_index ? `Tome ${rb.series_index}` : null, rb.published_year].filter(Boolean).join(" · ")}
                      </p>
                    </div>
                    {s ? (
                      <span className="px-2 py-1 rounded-lg font-semibold flex-shrink-0"
                        style={{ fontSize: 10, background: s.bg, color: s.color }}>{s.label}</span>
                    ) : (
                      <span className="px-2 py-1 rounded-lg flex-shrink-0"
                        style={{ fontSize: 10, background: "var(--surface2)", color: "var(--txt3)", border: "1px dashed var(--border)" }}>
                        Non possédé
                      </span>
                    )}
                  </div>
                );
              })}

              {!loading && remoteBooks.length === 0 && ownedBooks.length === 0 && (
                <p className="text-center py-8" style={{ fontSize: 13, color: "var(--txt3)" }}>Aucun résultat trouvé</p>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
