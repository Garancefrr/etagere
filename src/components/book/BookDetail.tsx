"use client";
import { useState } from "react";
import { Book, ReadStatus, BookType, Collection } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";
import { X, Star, Trash2, Save, Layers, ChevronDown } from "lucide-react";

interface Props {
  book: Book;
  collections: Collection[];
  onClose: () => void;
  onUpdate: (id: string, updates: Partial<Book>) => void;
  onDelete: (id: string) => void;
}

export default function BookDetail({ book, collections, onClose, onUpdate, onDelete }: Props) {
  const [status,      setStatus]       = useState<ReadStatus>(book.status);
  const [bookType,    setBookType]     = useState<BookType>(book.book_type);
  const [rating,      setRating]       = useState(book.rating ?? 0);
  const [note,        setNote]         = useState(book.note ?? "");
  const [seriesName,  setSeriesName]   = useState(book.series_name ?? "");
  const [seriesIndex, setSeriesIndex]  = useState(book.series_index?.toString() ?? "");
  const [showDrop,    setShowDrop]     = useState(false);
  const [confirmDel,  setConfirmDel]   = useState(false);

  const handleSave = async () => {
    await onUpdate(book.id, {
      status, book_type: bookType,
      rating: rating || undefined,
      note: note || undefined,
      series_name: seriesName.trim() || undefined,
      series_index: seriesIndex ? parseInt(seriesIndex) : undefined,
    });
    onClose();
  };

  const handleDelete = () => { onDelete(book.id); onClose(); };

  const filteredCollections = collections.filter(c =>
    !seriesName || c.name.toLowerCase().includes(seriesName.toLowerCase())
  );

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full sm:max-w-md rounded-t-3xl sm:rounded-3xl overflow-hidden"
        style={{ background: "var(--surface)", maxHeight: "90vh" }}>
        <div className="flex justify-center pt-2 sm:hidden">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>
        <button onClick={onClose} className="absolute top-3 right-4 w-10 h-10 rounded-full flex items-center justify-center z-10"
          style={{ background: "var(--surface2)" }}>
          <X className="w-5 h-5" style={{ color: "var(--txt2)" }} />
        </button>

        <div className="overflow-y-auto" style={{ maxHeight: "calc(90vh - 20px)" }}>
          {/* Header — compact */}
          <div className="flex gap-3 px-4 pt-2 pb-1">
            <Cover src={book.cover_url} alt={book.title} width={64} height={90} className="rounded-lg shadow-md flex-shrink-0" />
            <div className="flex-1 min-w-0 pt-0.5">
              <h2 className="font-bold leading-tight" style={{ fontSize: 16, color: "var(--txt1)" }}>{book.title}</h2>
              <p className="text-sm mt-0.5" style={{ color: "var(--txt2)" }}>{book.authors.join(", ")}</p>
              <p className="text-xs mt-0.5" style={{ color: "var(--txt3)" }}>
                {[book.publisher, book.published_year, book.page_count ? `${book.page_count}p` : null].filter(Boolean).join(" · ")}
              </p>
            </div>
          </div>

          {/* Description — compact */}
          {book.description && (
            <div className="px-4 pb-1">
              <p className="leading-relaxed line-clamp-3" style={{ fontSize: 11, color: "var(--txt3)" }}>{book.description}</p>
            </div>
          )}

          <div className="px-4 pb-5 space-y-3">
            {/* Collection */}
            <Section label="Collection">
              <div className="flex gap-2">
                <div className="flex-1 relative">
                  <div className="flex items-center gap-2 px-3 py-2 rounded-xl cursor-pointer"
                    onClick={() => setShowDrop(v => !v)}
                    style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                    <Layers className="w-3.5 h-3.5 flex-shrink-0" style={{ color: seriesName ? "var(--accent)" : "var(--txt3)" }} />
                    <input
                      value={seriesName}
                      onChange={e => { setSeriesName(e.target.value); setShowDrop(true); }}
                      onClick={e => { e.stopPropagation(); setShowDrop(true); }}
                      placeholder="Aucune collection"
                      className="flex-1 outline-none bg-transparent"
                      style={{ color: "var(--txt1)", fontSize: 16 }}
                    />
                    <ChevronDown className="w-3.5 h-3.5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
                  </div>
                  {showDrop && (
                    <div className="absolute left-0 right-0 top-full mt-1 rounded-xl overflow-hidden z-20 max-h-36 overflow-y-auto"
                      style={{ background: "var(--surface2)", border: "1px solid var(--border)", boxShadow: "0 4px 16px rgba(0,0,0,0.3)" }}>
                      {seriesName && (
                        <button onClick={() => { setSeriesName(""); setSeriesIndex(""); setShowDrop(false); }}
                          className="w-full text-left px-3 py-2 text-xs" style={{ color: "var(--miss-t)", borderBottom: "1px solid var(--border)" }}>
                          ✕ Retirer de la collection
                        </button>
                      )}
                      {filteredCollections.map(c => (
                        <button key={c.id} onClick={() => { setSeriesName(c.name); setShowDrop(false); }}
                          className="w-full text-left px-3 py-2 text-xs active:opacity-70"
                          style={{ color: "var(--txt1)", borderBottom: "1px solid var(--border)" }}>
                          {c.name}
                          <span style={{ color: "var(--txt3)", marginLeft: 6, fontSize: 10 }}>{c.owned_volumes?.length ?? 0} tomes</span>
                        </button>
                      ))}
                      {seriesName.trim() && !collections.some(c => c.name.toLowerCase() === seriesName.trim().toLowerCase()) && (
                        <button onClick={() => setShowDrop(false)}
                          className="w-full text-left px-3 py-2 text-xs font-semibold"
                          style={{ color: "var(--accent)" }}>
                          + Créer « {seriesName.trim()} »
                        </button>
                      )}
                    </div>
                  )}
                </div>
                <input value={seriesIndex} onChange={e => setSeriesIndex(e.target.value)}
                  placeholder="T." type="number"
                  className="w-14 px-2 py-2 rounded-xl outline-none text-center"
                  style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 16 }} />
              </div>
            </Section>

            {/* Type + Statut — side by side */}
            <div className="grid grid-cols-2 gap-3">
              <Section label="Type">
                <div className="flex flex-col gap-1">
                  {Object.entries(TYPE_CONFIG).map(([v, { label, emoji }]) => (
                    <button key={v} onClick={() => setBookType(v as BookType)}
                      className="py-1.5 rounded-lg text-xs font-semibold"
                      style={{ background: bookType === v ? "var(--accent)" : "var(--surface2)", color: bookType === v ? "#fff" : "var(--txt2)", border: `1px solid ${bookType === v ? "var(--accent)" : "var(--border)"}` }}>
                      {emoji} {label}
                    </button>
                  ))}
                </div>
              </Section>
              <Section label="Statut">
                <div className="flex flex-col gap-1">
                  {Object.entries(STATUS_CONFIG).map(([v, { emoji, label }]) => (
                    <button key={v} onClick={() => setStatus(v as ReadStatus)}
                      className="py-1.5 rounded-lg text-xs font-semibold"
                      style={{ background: status === v ? "var(--accent)" : "var(--surface2)", color: status === v ? "#fff" : "var(--txt2)", border: `1px solid ${status === v ? "var(--accent)" : "var(--border)"}` }}>
                      {emoji} {label}
                    </button>
                  ))}
                </div>
              </Section>
            </div>

            {/* Rating */}
            <Section label="Note">
              <div className="flex gap-1.5">
                {Array.from({ length: 5 }).map((_, i) => (
                  <button key={i} onClick={() => setRating(i + 1 === rating ? 0 : i + 1)}
                    className="flex-1 py-1.5 rounded-lg flex items-center justify-center"
                    style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                    <Star style={{ width: 16, height: 16, color: i < rating ? "#FBBF24" : "var(--border)", fill: i < rating ? "#FBBF24" : "none" }} />
                  </button>
                ))}
              </div>
            </Section>

            {/* Note */}
            <Section label="Mon avis">
              <textarea value={note} onChange={e => setNote(e.target.value)} placeholder="Vos impressions..."
                rows={2} className="w-full p-2.5 rounded-xl resize-none outline-none"
                style={{ background: "var(--surface2)", color: "var(--txt1)", border: "1px solid var(--border)", fontFamily: "inherit", fontSize: 16 }} />
            </Section>

            {/* Actions */}
            <div className="flex gap-3">
              <Button onClick={handleSave} className="flex-1 py-3 rounded-2xl">
                <Save className="w-4 h-4" /> Enregistrer
              </Button>
              {!confirmDel ? (
                <Button variant="ghost" onClick={() => setConfirmDel(true)} className="w-11 h-11 rounded-2xl">
                  <Trash2 className="w-4 h-4" style={{ color: "var(--miss-t)" }} />
                </Button>
              ) : (
                <Button variant="danger" onClick={handleDelete} className="px-4 rounded-2xl text-xs">Confirmer ?</Button>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="font-bold uppercase tracking-wider mb-1" style={{ fontSize: 10, color: "var(--accent)" }}>{label}</p>
      {children}
    </div>
  );
}
