"use client";
import { useState, useEffect } from "react";
import { Collection, Book } from "@/types";
import { TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { X, Edit2, Trash2 } from "lucide-react";

interface AllBook {
  title: string;
  isbn?: string;
  cover_url?: string;
  published_year?: number;
  owned?: Book; // if user owns it
}

interface Props {
  collection: Collection;
  books: Book[]; // all user's books
  onClose: () => void;
  onEdit: () => void;
  onDelete: () => void;
  onShare?: () => void;
}

export default function CollectionDetail({ collection, books, onClose, onEdit, onDelete, onShare }: Props) {
  const { emoji } = TYPE_CONFIG[collection.book_type] ?? { emoji: "📖" };
  const owned = Array.from(new Set(collection.owned_volumes ?? [])).sort((a, b) => a - b);
  const total = collection.total_volumes ?? 0;
  const pct = total > 0 ? Math.round((owned.length / total) * 100) : 0;
  const [confirmDel, setConfirmDel] = useState(false);
  const [authorBooks, setAuthorBooks] = useState<AllBook[]>([]);
  const [loadingAuthor, setLoadingAuthor] = useState(false);

  const isAuthorCollection = collection.book_type === "livre";

  // For author collections: fetch all their books from Google Books
  useEffect(() => {
    if (!isAuthorCollection || !collection.author) return;
    setLoadingAuthor(true);
    fetch(`/api/books/search?q=${encodeURIComponent(collection.author)}`)
      .then(r => r.json())
      .then((results: any[]) => {
        // Map against owned books
        const ownedInCollection = books.filter(b =>
          b.series_name?.toLowerCase() === collection.name.toLowerCase() ||
          b.authors.some(a => a.toLowerCase().includes((collection.author ?? "").toLowerCase()))
        );
        const allBooks: AllBook[] = results
          .filter(r => r.authors?.some((a: string) => a.toLowerCase().includes((collection.author ?? "").toLowerCase())))
          .map(r => ({
            title: r.title,
            isbn: r.isbn,
            cover_url: r.cover_url,
            published_year: r.published_year,
            owned: ownedInCollection.find(b =>
              b.title.toLowerCase() === r.title.toLowerCase() ||
              (b.isbn && b.isbn === r.isbn)
            ),
          }));
        // Also add owned books not found in Google Books search
        ownedInCollection.forEach(ob => {
          if (!allBooks.some(ab => ab.owned?.id === ob.id)) {
            allBooks.push({ title: ob.title, isbn: ob.isbn ?? undefined, cover_url: ob.cover_url, owned: ob });
          }
        });
        setAuthorBooks(allBooks);
      })
      .catch(() => {})
      .finally(() => setLoadingAuthor(false));
  }, [collection.author, collection.name, isAuthorCollection]); // eslint-disable-line

  const statusLabel = (b: Book) => {
    if (b.status === "lu")       return { label: "Lu",       bg: "var(--have-bg)", color: "var(--have-t)" };
    if (b.status === "en_cours") return { label: "En cours", bg: "#FEF9C3",        color: "#A16207" };
    return                              { label: "À lire",   bg: "var(--accent-l)", color: "var(--accent)" };
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full sm:max-w-md rounded-t-3xl overflow-hidden flex flex-col"
        style={{ background: "var(--surface)", maxHeight: "88vh" }}>

        {/* Handle */}
        <div className="flex justify-center pt-3 flex-shrink-0">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>

        {/* Header */}
        <div className="flex items-center gap-3 px-4 py-3 flex-shrink-0"
          style={{ borderBottom: "1px solid var(--border)" }}>
          <Cover src={collection.cover_url} alt={collection.name} width={48} height={66} className="rounded-xl flex-shrink-0" />
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5">
              <span style={{ fontSize: 12 }}>{emoji}</span>
              <p className="font-bold truncate" style={{ fontSize: 16, color: "var(--txt1)" }}>{collection.name}</p>
            </div>
            {collection.author && <p style={{ fontSize: 13, color: "var(--txt2)" }}>{collection.author}</p>}
            {total > 0 && (
              <div className="flex items-center gap-2 mt-1.5">
                <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
                  <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
                </div>
                <span className="font-semibold flex-shrink-0" style={{ fontSize: 11, color: "var(--accent)" }}>
                  {owned.length}/{total}
                </span>
              </div>
            )}
          </div>
          <div className="flex gap-2 flex-shrink-0">
            {onShare && (
              <button onClick={onShare} className="w-8 h-8 rounded-xl flex items-center justify-center"
                style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ color: "var(--accent)" }}><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>
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
              <button onClick={onDelete} className="px-3 h-8 rounded-xl font-bold"
                style={{ fontSize: 11, background: "var(--miss-t)", color: "#fff" }}>
                Confirmer
              </button>
            )}
          </div>
          <button onClick={onClose} className="w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0"
            style={{ background: "var(--surface2)" }}>
            <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
          </button>
        </div>

        {/* Content */}
        <div className="overflow-y-auto flex-1">
          {/* Series view — numbered chips */}
          {!isAuthorCollection && (
            <div className="p-4">
              {total > 0 && (
                <p className="text-xs font-bold uppercase tracking-wider mb-3" style={{ color: "var(--txt3)" }}>
                  Tomes
                </p>
              )}
              <div className="flex flex-wrap gap-1.5">
                {(total > 0 ? Array.from({ length: Math.min(total, 40) }, (_, i) => i + 1) : owned).map(n => {
                  const isOwned = owned.includes(n);
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

          {/* Author collection — book list */}
          {isAuthorCollection && (
            <div>
              {loadingAuthor && (
                <div className="flex justify-center py-8">
                  <div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
                </div>
              )}
              {!loadingAuthor && authorBooks.map((ab, i) => {
                const status = ab.owned ? statusLabel(ab.owned) : null;
                return (
                  <div key={i} className="flex items-center gap-3 px-4 py-3"
                    style={{ borderBottom: "1px solid var(--border)" }}>
                    <Cover src={ab.cover_url} alt={ab.title} width={36} height={50} className="rounded-lg flex-shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="font-semibold truncate" style={{ fontSize: 13, color: "var(--txt1)" }}>{ab.title}</p>
                      {ab.published_year && (
                        <p style={{ fontSize: 11, color: "var(--txt3)", marginTop: 1 }}>{ab.published_year}</p>
                      )}
                    </div>
                    {status ? (
                      <span className="px-2 py-1 rounded-lg font-semibold flex-shrink-0"
                        style={{ fontSize: 10, background: status.bg, color: status.color }}>
                        {status.label}
                      </span>
                    ) : (
                      <span className="px-2 py-1 rounded-lg flex-shrink-0"
                        style={{ fontSize: 10, background: "var(--surface2)", color: "var(--txt3)", border: "1px dashed var(--border)" }}>
                        Non possédé
                      </span>
                    )}
                  </div>
                );
              })}
              {!loadingAuthor && authorBooks.length === 0 && (
                <p className="text-center py-8" style={{ fontSize: 13, color: "var(--txt3)" }}>
                  Aucun livre trouvé pour cet auteur
                </p>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
