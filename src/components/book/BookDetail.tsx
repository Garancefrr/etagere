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
        style={{ background: "var(--surface)", maxHeight: "92vh" }}>
        <div className="flex justify-center pt-3 sm:hidden">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>
        <button onClick={onClose} className="absolute top-4 right-4 w-8 h-8 rounded-full flex items-center justify-center z-10"
          style={{ background: "var(--surface2)" }}>
          <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
        </button>

        <div className="overflow-y-auto" style={{ maxHeight: "calc(92vh - 32px)" }}>
          {/* Header */}
          <div className="flex gap-4 p-5 pt-3">
            <Cover src={book.cover_url} alt={book.title} width={80} height={112} className="rounded-xl shadow-md flex-shrink-0" />
            <div className="flex-1 min-w-0 pt-1">
              <h2 className="font-bold text-lg leading-tight" style={{ color: "var(--txt1)" }}>{book.title}</h2>
              <p className="text-sm mt-1" style={{ color: "var(--txt2)" }}>{book.authors.join(", ")}</p>
              {book.publisher && (
                <p className="text-xs mt-0.5" style={{ color: "var(--txt3)" }}>
                  {book.publisher}{book.published_year ? ` · ${book.published_year}` : ""}
                </p>
              )}
              {book.page_count && <p className="text-xs" style={{ color: "var(--txt3)" }}>{book.page_count} pages</p>}
            </div>
          </div>

          {/* Description under header */}
          {book.description && (
            <div className="px-5 -mt-1 mb-2">
              <p className="text-xs leading-relaxed line-clamp-4" style={{ color: "var(--txt3)" }}>{book.description}</p>
            </div>
          )}

          <div className="px-5 pb-6 space-y-5">
            {/* Collection */}
            <Section label="Collection">
              <div className="flex gap-2">
                <div className="flex-1 relative">
                  <div className="flex items-center gap-2 px-3 py-2.5 rounded-xl cursor-pointer"
                    onClick={() => setShowDrop(v => !v)}
                    style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                    <Layers className="w-4 h-4 flex-shrink-0" style={{ color: seriesName ? "var(--accent)" : "var(--txt3)" }} />
                    <input
                      value={seriesName}
                      onChange={e => { setSeriesName(e.target.value); setShowDrop(true); }}
                      onClick={e => { e.stopPropagation(); setShowDrop(true); }}
                      placeholder="Aucune collection"
                      className="flex-1 outline-none bg-transparent text-sm"
                      style={{ color: "var(--txt1)" }}
                    />
                    <ChevronDown className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
                  </div>
                  {showDrop && (
                    <div className="absolute left-0 right-0 top-full mt-1 rounded-xl overflow-hidden z-20 max-h-36 overflow-y-auto"
                      style={{ background: "var(--surface2)", border: "1px solid var(--border)", boxShadow: "0 4px 16px rgba(0,0,0,0.3)" }}>
                      {/* Remove from collection */}
                      {seriesName && (
                        <button onClick={() => { setSeriesName(""); setSeriesIndex(""); setShowDrop(false); }}
                          className="w-full text-left px-3 py-2.5 text-sm" style={{ color: "var(--miss-t)", borderBottom: "1px solid var(--border)" }}>
                          ✕ Retirer de la collection
                        </button>
                      )}
                      {filteredCollections.map(c => (
                        <button key={c.id} onClick={() => { setSeriesName(c.name); setShowDrop(false); }}
                          className="w-full text-left px-3 py-2.5 text-sm active:opacity-70"
                          style={{ color: "var(--txt1)", borderBottom: "1px solid var(--border)" }}>
                          {c.name}
                          <span style={{ color: "var(--txt3)", marginLeft: 6, fontSize: 11 }}>{c.owned_volumes?.length ?? 0} tomes</span>
                        </button>
                      ))}
                      {seriesName.trim() && !collections.some(c => c.name.toLowerCase() === seriesName.trim().toLowerCase()) && (
                        <button onClick={() => setShowDrop(false)}
                          className="w-full text-left px-3 py-2.5 text-sm font-semibold"
                          style={{ color: "var(--accent)" }}>
                          + Créer « {seriesName.trim()} »
                        </button>
                      )}
                    </div>
                  )}
                </div>
                <input
                  value={seriesIndex}
                  onChange={e => setSeriesIndex(e.target.value)}
                  placeholder="T."
                  type="number"
                  className="w-16 px-3 py-2.5 rounded-xl outline-none text-sm text-center"
                  style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)" }}
                />
              </div>
            </Section>

            {/* Type */}
            <Section label="Type">
              <SegmentedControl
                options={Object.entries(TYPE_CONFIG).map(([v, { label, emoji }]) => ({ value: v, label: `${emoji} ${label}` }))}
                value={bookType} onChange={v => setBookType(v as BookType)} />
            </Section>

            {/* Status */}
            <Section label="Statut">
              <SegmentedControl
                options={Object.entries(STATUS_CONFIG).map(([v, { emoji, label }]) => ({ value: v, label: `${emoji} ${label}` }))}
                value={status} onChange={v => setStatus(v as ReadStatus)} />
            </Section>

            {/* Rating */}
            <Section label="Note">
              <div className="flex gap-2">
                {Array.from({ length: 5 }).map((_, i) => (
                  <button key={i} onClick={() => setRating(i + 1 === rating ? 0 : i + 1)}
                    className="flex-1 py-2 rounded-xl flex items-center justify-center"
                    style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                    <Star style={{ width: 18, height: 18, color: i < rating ? "#FBBF24" : "var(--border)", fill: i < rating ? "#FBBF24" : "none" }} />
                  </button>
                ))}
              </div>
            </Section>

            {/* Note */}
            <Section label="Mon avis">
              <textarea value={note} onChange={e => setNote(e.target.value)} placeholder="Vos impressions..."
                rows={3} className="w-full p-3 rounded-xl text-sm resize-none outline-none"
                style={{ background: "var(--surface2)", color: "var(--txt1)", border: "1px solid var(--border)", fontFamily: "inherit" }} />
            </Section>

            {/* Actions */}
            <div className="flex gap-3 pt-1">
              <Button onClick={handleSave} className="flex-1 py-3.5 rounded-2xl">
                <Save className="w-4 h-4" /> Enregistrer
              </Button>
              {!confirmDel ? (
                <Button variant="ghost" onClick={() => setConfirmDel(true)} className="w-12 h-12 rounded-2xl">
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
      <p className="text-xs font-bold uppercase tracking-wider mb-2" style={{ color: "var(--txt3)" }}>{label}</p>
      {children}
    </div>
  );
}

function SegmentedControl({ options, value, onChange }: { options: { value: string; label: string }[]; value: string; onChange: (v: string) => void }) {
  return (
    <div className="flex gap-2">
      {options.map(o => (
        <button key={o.value} onClick={() => onChange(o.value)}
          className="flex-1 py-2.5 rounded-xl text-sm font-semibold"
          style={{ background: value === o.value ? "var(--accent)" : "var(--surface2)", color: value === o.value ? "#fff" : "var(--txt2)", border: `1px solid ${value === o.value ? "var(--accent)" : "var(--border)"}` }}>
          {o.label}
        </button>
      ))}
    </div>
  );
}
