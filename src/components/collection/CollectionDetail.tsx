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
  const viewMode = isBdManga || hasTotalVolumes ? "numbered" : "list";

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
    fetch(`/api/books/search?q=${encodeURIComponent(query)}`)
      .then(r => r.json())
      .then((results: any[]) => {
        const filtered = results.filter(r => {
          if (collection.author) {
            return r.authors?.some((a: string) => {
              const al = a.toLowerCase(), cl = collection.author!.toLowerCase();
              return al.includes(cl) || cl.includes(al) || al.split(" ").pop() === cl.split(" ").pop();
            });
          }
          return r.title.toLowerCase().includes(collection.name.toLowerCase()) || r.series_name?.toLowerCase().includes(collection.name.toLowerCase());
        });
        const mapped: RemoteBook[] = filtered.map(r => ({
          title: r.title, isbn: r.isbn, cover_url: r.cover_url,
          published_year: r.published_year, series_index: r.series_index,
          owned: ownedBooks.find(b => b.title.toLowerCase() === r.title.toLowerCase() || (b.isbn && b.isbn === r.isbn)),
        }));
        ownedBooks.forEach(ob => {
          if (!mapped.some(m => m.owned?.id === ob.id))
            mapped.push({ title: ob.title, isbn: ob.isbn ?? undefined, cover_url: ob.cover_url, series_index: ob.series_index, owned: ob });
        });
        const sortOrder = (rb: RemoteBook) => !rb.owned ? 4 : rb.owned.status === "en_cours" ? 0 : rb.owned.status === "a_lire" ? 1 : 2;
        mapped.sort((a, b) => sortOrder(a) - sortOrder(b) || a.title.localeCompare(b.title));
        setRemoteBooks(mapped);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [collection.name, collection.author, viewMode]); // eslint-disable-line

  const badge = (status: string) => {
    if (status === "lu")       return { label: "Lu",       bg: "var(--have-bg)", color: "var(--have-t)" };
    if (status === "en_cours") return { label: "En cours", bg: "#FEF9C3",        color: "#A16207" };
    return                            { label: "À lire",   bg: "var(--accent-l)", color: "var(--accent)" };
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full sm:max-w-md rounded-t-3xl overflow-hidden flex flex-col"
        style={{ background: "var(--surface)", maxHeight: "92vh" }}>
        <div className="flex justify-center pt-2 flex-shrink-0">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>

        {/* Compact header */}
        <div className="px-4 py-2 flex-shrink-0" style={{ borderBottom: "1px solid var(--border)" }}>
          <div className="flex items-center gap-2">
            <p className="font-bold flex-1 truncate" style={{ fontSize: 16, color: "var(--txt1)" }}>{emoji} {collection.name}</p>
            <button onClick={onClose} className="w-7 h-7 rounded-lg flex items-center justify-center" style={{ background: "var(--surface2)" }}>
              <X className="w-3.5 h-3.5" style={{ color: "var(--txt2)" }} />
            </button>
          </div>
          {/* Stats + actions row */}
          <div className="flex items-center justify-between mt-1.5">
            <div className="flex gap-2 flex-wrap">
              {collection.author && <span style={{ fontSize: 11, color: "var(--txt3)" }}>{collection.author}</span>}
              {enCoursCount > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 10, background: "#FEF9C3", color: "#A16207" }}>📖 {enCoursCount}</span>}
              {aLireCount > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 10, background: "var(--accent-l)", color: "var(--accent)" }}>📌 {aLireCount}</span>}
              {luCount > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 10, background: "var(--have-bg)", color: "var(--have-t)" }}>✅ {luCount}</span>}
            </div>
            <div className="flex gap-1">
              {onShare && <button onClick={onShare} className="w-7 h-7 rounded-lg flex items-center justify-center" style={{ background: "var(--surface2)" }}>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{ color: "var(--accent)" }}><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>
              </button>}
              <button onClick={onEdit} className="w-7 h-7 rounded-lg flex items-center justify-center" style={{ background: "var(--surface2)" }}>
                <Edit2 className="w-3 h-3" style={{ color: "var(--txt2)" }} />
              </button>
              {!confirmDel
                ? <button onClick={() => setConfirmDel(true)} className="w-7 h-7 rounded-lg flex items-center justify-center" style={{ background: "var(--miss-bg)" }}>
                    <Trash2 className="w-3 h-3" style={{ color: "var(--miss-t)" }} />
                  </button>
                : <button onClick={onDelete} className="px-2 h-7 rounded-lg font-bold" style={{ fontSize: 10, background: "var(--miss-t)", color: "#fff" }}>Suppr ?</button>}
            </div>
          </div>
          {/* Progress bar */}
          <div className="h-1 rounded-full overflow-hidden mt-2" style={{ background: "var(--border)" }}>
            <div className="h-full rounded-full" style={{ width: `${Math.max(pct, 2)}%`, background: pct === 100 ? "var(--have-t)" : "var(--accent)" }} />
          </div>
        </div>

        {/* Content */}
        <div className="overflow-y-auto flex-1">
          {viewMode === "numbered" && (
            <div className="p-3">
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
            </div>
          )}

          {viewMode === "list" && (
            <>
              {loading && <div className="flex justify-center py-6"><div className="w-5 h-5 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} /></div>}

              {!loading && remoteBooks.length === 0 && ownedBooks.length > 0 && ownedBooks.map(b => {
                const s = badge(b.status);
                return (
                  <div key={b.id} className="flex items-center gap-2 px-3 py-1.5" style={{ borderBottom: "1px solid var(--border)" }}>
                    <Cover src={b.cover_url} alt={b.title} width={28} height={40} className="rounded flex-shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="font-semibold truncate" style={{ fontSize: 12, color: "var(--txt1)" }}>{b.title}</p>
                      {b.series_index && <p style={{ fontSize: 10, color: "var(--txt3)" }}>Tome {b.series_index}</p>}
                    </div>
                    <span className="px-1.5 py-0.5 rounded font-semibold flex-shrink-0" style={{ fontSize: 9, background: s.bg, color: s.color }}>{s.label}</span>
                  </div>
                );
              })}

              {!loading && remoteBooks.map((rb, i) => {
                const s = rb.owned ? badge(rb.owned.status) : null;
                return (
                  <div key={i} className="flex items-center gap-2 px-3 py-1.5"
                    style={{ borderBottom: "1px solid var(--border)", opacity: rb.owned ? 1 : 0.5 }}>
                    <Cover src={rb.cover_url ?? undefined} alt={rb.title} width={28} height={40} className="rounded flex-shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="font-semibold truncate" style={{ fontSize: 12, color: rb.owned ? "var(--txt1)" : "var(--txt3)" }}>{rb.title}</p>
                      <p style={{ fontSize: 10, color: "var(--txt3)" }}>
                        {[rb.series_index ? `T.${rb.series_index}` : null, rb.published_year].filter(Boolean).join(" · ")}
                      </p>
                    </div>
                    {s
                      ? <span className="px-1.5 py-0.5 rounded font-semibold flex-shrink-0" style={{ fontSize: 9, background: s.bg, color: s.color }}>{s.label}</span>
                      : <span className="px-1.5 py-0.5 rounded flex-shrink-0" style={{ fontSize: 9, background: "var(--surface2)", color: "var(--txt3)", border: "1px dashed var(--border)" }}>—</span>}
                  </div>
                );
              })}

              {!loading && remoteBooks.length === 0 && ownedBooks.length === 0 && (
                <p className="text-center py-8" style={{ fontSize: 12, color: "var(--txt3)" }}>Aucun résultat</p>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
