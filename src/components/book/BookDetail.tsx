"use client";
import { Book, ReadStatus, BookType } from "@/types";
import { X, Star, Trash2, Save, BookOpen } from "lucide-react";
import { useState } from "react";

const STATUSES: { value: ReadStatus; label: string; emoji: string }[] = [
  { value: "a_lire",   label: "À lire",   emoji: "📌" },
  { value: "en_cours", label: "En cours", emoji: "📖" },
  { value: "lu",       label: "Lu",       emoji: "✅" },
];
const TYPES: { value: BookType; label: string }[] = [
  { value: "livre", label: "📖 Livre" },
  { value: "bd",    label: "🎨 BD"    },
  { value: "manga", label: "⛩️ Manga" },
];

interface Props {
  book: Book;
  onClose: () => void;
  onUpdate: (id: string, u: Partial<Book>) => void;
  onDelete: (id: string) => void;
}

export default function BookDetail({ book, onClose, onUpdate, onDelete }: Props) {
  const [status, setStatus]   = useState<ReadStatus>(book.status);
  const [type, setType]       = useState<BookType>(book.book_type);
  const [rating, setRating]   = useState(book.rating ?? 0);
  const [note, setNote]       = useState(book.note ?? "");
  const [confirmDel, setCDel] = useState(false);
  const [saving, setSaving]   = useState(false);
  const [imgErr, setImgErr]   = useState(false);

  const save = async () => {
    setSaving(true);
    onUpdate(book.id, { status, book_type: type, rating: rating || undefined, note: note || undefined });
    setSaving(false);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full sm:max-w-md rounded-t-3xl sm:rounded-3xl overflow-hidden"
        style={{ background: "var(--surface)", maxHeight: "92vh" }}>
        {/* Drag handle */}
        <div className="flex justify-center pt-3 sm:hidden">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>
        <button onClick={onClose}
          className="absolute top-4 right-4 w-8 h-8 rounded-full flex items-center justify-center z-10"
          style={{ background: "var(--surface2)" }}>
          <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
        </button>

        <div className="overflow-y-auto" style={{ maxHeight: "calc(92vh - 32px)" }}>
          {/* Header */}
          <div className="flex gap-4 p-5 pt-3">
            <div className="w-20 h-28 rounded-xl overflow-hidden flex-shrink-0 flex items-center justify-center shadow-md"
              style={{ background: "var(--placeholder)" }}>
              {book.cover_url && !imgErr
                ? <img src={book.cover_url} alt={book.title} className="w-full h-full object-cover" onError={() => setImgErr(true)} />
                : <BookOpen className="w-7 h-7" style={{ color: "var(--txt3)" }} />}
            </div>
            <div className="flex-1 min-w-0 pt-1">
              <h2 className="font-bold text-lg leading-tight" style={{ color: "var(--txt1)" }}>{book.title}</h2>
              <p className="text-sm mt-1" style={{ color: "var(--txt2)" }}>{book.authors.join(", ")}</p>
              {book.publisher && <p className="text-xs mt-0.5" style={{ color: "var(--txt3)" }}>{book.publisher}{book.published_year ? ` · ${book.published_year}` : ""}</p>}
              {book.page_count && <p className="text-xs" style={{ color: "var(--txt3)" }}>{book.page_count} pages</p>}
              {book.series_name && (
                <p className="text-xs mt-1 font-semibold" style={{ color: "var(--accent)" }}>
                  {book.series_name}{book.series_index ? ` — Tome ${book.series_index}` : ""}
                </p>
              )}
            </div>
          </div>

          <div className="px-5 pb-6 space-y-4">
            {/* Type */}
            <div>
              <label className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--txt3)" }}>Type</label>
              <div className="flex gap-2 mt-2">
                {TYPES.map(t => (
                  <button key={t.value} onClick={() => setType(t.value)}
                    className="flex-1 py-2 rounded-xl text-sm font-semibold transition-all"
                    style={{ background: type === t.value ? "var(--accent)" : "var(--surface2)", color: type === t.value ? "#fff" : "var(--txt2)", border: `1px solid ${type === t.value ? "var(--accent)" : "var(--border)"}` }}>
                    {t.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Status */}
            <div>
              <label className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--txt3)" }}>Statut</label>
              <div className="flex gap-2 mt-2">
                {STATUSES.map(s => (
                  <button key={s.value} onClick={() => setStatus(s.value)}
                    className="flex-1 py-2.5 rounded-xl text-xs font-semibold flex flex-col items-center gap-1 transition-all"
                    style={{ background: status === s.value ? "var(--accent)" : "var(--surface2)", color: status === s.value ? "#fff" : "var(--txt2)", border: `1px solid ${status === s.value ? "var(--accent)" : "var(--border)"}` }}>
                    <span className="text-base">{s.emoji}</span>{s.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Rating */}
            <div>
              <label className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--txt3)" }}>Note</label>
              <div className="flex gap-2 mt-2">
                {Array.from({ length: 5 }).map((_, i) => (
                  <button key={i} onClick={() => setRating(i + 1 === rating ? 0 : i + 1)}
                    className="flex-1 py-2 rounded-xl flex items-center justify-center"
                    style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                    <Star style={{ width: 18, height: 18, color: i < rating ? "#FBBF24" : "var(--border)", fill: i < rating ? "#FBBF24" : "none" }} />
                  </button>
                ))}
              </div>
            </div>

            {/* Note */}
            <div>
              <label className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--txt3)" }}>Mon avis</label>
              <textarea value={note} onChange={e => setNote(e.target.value)}
                placeholder="Vos impressions..." rows={3}
                className="w-full mt-2 p-3 rounded-xl text-sm resize-none outline-none"
                style={{ background: "var(--surface2)", color: "var(--txt1)", border: "1px solid var(--border)", fontFamily: "inherit" }} />
            </div>

            {book.description && (
              <div>
                <label className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--txt3)" }}>Résumé</label>
                <p className="text-sm mt-2 leading-relaxed line-clamp-4" style={{ color: "var(--txt2)" }}>{book.description}</p>
              </div>
            )}

            {/* Actions */}
            <div className="flex gap-3 pt-1">
              <button onClick={save} disabled={saving}
                className="flex-1 py-3.5 rounded-2xl font-bold text-sm flex items-center justify-center gap-2 transition-all active:scale-95"
                style={{ background: "var(--accent)", color: "#fff" }}>
                <Save className="w-4 h-4" />{saving ? "Enregistrement..." : "Enregistrer"}
              </button>
              {!confirmDel
                ? <button onClick={() => setCDel(true)}
                    className="w-12 h-12 rounded-2xl flex items-center justify-center"
                    style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                    <Trash2 className="w-4 h-4" style={{ color: "var(--miss-t)" }} />
                  </button>
                : <button onClick={() => onDelete(book.id)}
                    className="px-3 py-2 rounded-2xl font-bold text-xs"
                    style={{ background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px solid var(--miss-b)" }}>
                    Confirmer ?
                  </button>}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
