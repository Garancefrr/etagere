"use client";
import { useState } from "react";
import { Book, ReadStatus, BookType } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";
import { X, Star, Trash2, Save } from "lucide-react";

interface Props {
  book: Book;
  onClose: () => void;
  onUpdate: (id: string, updates: Partial<Book>) => void;
  onDelete: (id: string) => void;
}

export default function BookDetail({ book, onClose, onUpdate, onDelete }: Props) {
  const [status,       setStatus]       = useState<ReadStatus>(book.status);
  const [bookType,     setBookType]     = useState<BookType>(book.book_type);
  const [rating,       setRating]       = useState(book.rating ?? 0);
  const [note,         setNote]         = useState(book.note ?? "");
  const [confirmDel,   setConfirmDel]   = useState(false);

  const handleSave = () => {
    onUpdate(book.id, { status, book_type: bookType, rating: rating || undefined, note: note || undefined });
    onClose();
  };

  const handleDelete = () => {
    onDelete(book.id);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 backdrop-blur-sm"
        style={{ background: "rgba(10,13,31,0.6)" }}
        onClick={onClose}
      />

      {/* Sheet */}
      <div
        className="relative w-full sm:max-w-md rounded-t-3xl sm:rounded-3xl overflow-hidden"
        style={{ background: "var(--surface)", maxHeight: "92vh" }}
      >
        {/* Drag handle */}
        <div className="flex justify-center pt-3 sm:hidden">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>

        <button
          onClick={onClose}
          className="absolute top-4 right-4 w-8 h-8 rounded-full flex items-center justify-center z-10"
          style={{ background: "var(--surface2)" }}
        >
          <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
        </button>

        <div className="overflow-y-auto" style={{ maxHeight: "calc(92vh - 32px)" }}>
          {/* Header */}
          <div className="flex gap-4 p-5 pt-3">
            <Cover
              src={book.cover_url}
              alt={book.title}
              width={80}
              height={112}
              className="rounded-xl shadow-md flex-shrink-0"
            />
            <div className="flex-1 min-w-0 pt-1">
              <h2 className="font-bold text-lg leading-tight" style={{ color: "var(--txt1)" }}>
                {book.title}
              </h2>
              <p className="text-sm mt-1" style={{ color: "var(--txt2)" }}>{book.authors.join(", ")}</p>
              {book.publisher && (
                <p className="text-xs mt-0.5" style={{ color: "var(--txt3)" }}>
                  {book.publisher}{book.published_year ? ` · ${book.published_year}` : ""}
                </p>
              )}
              {book.page_count && (
                <p className="text-xs" style={{ color: "var(--txt3)" }}>{book.page_count} pages</p>
              )}
              {book.series_name && (
                <p className="text-xs mt-1 font-semibold" style={{ color: "var(--accent)" }}>
                  {book.series_name} — Tome {book.series_index}
                </p>
              )}
            </div>
          </div>

          <div className="px-5 pb-6 space-y-5">
            {/* Type */}
            <Section label="Type">
              <SegmentedControl
                options={Object.entries(TYPE_CONFIG).map(([v, { label, emoji }]) => ({ value: v, label: `${emoji} ${label}` }))}
                value={bookType}
                onChange={(v) => setBookType(v as BookType)}
              />
            </Section>

            {/* Status */}
            <Section label="Statut">
              <SegmentedControl
                options={Object.entries(STATUS_CONFIG).map(([v, { emoji, label }]) => ({ value: v, label: `${emoji} ${label}` }))}
                value={status}
                onChange={(v) => setStatus(v as ReadStatus)}
              />
            </Section>

            {/* Rating */}
            <Section label="Note">
              <div className="flex gap-2">
                {Array.from({ length: 5 }).map((_, i) => (
                  <button
                    key={i}
                    onClick={() => setRating(i + 1 === rating ? 0 : i + 1)}
                    className="flex-1 py-2 rounded-xl flex items-center justify-center"
                    style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}
                  >
                    <Star style={{ width: 18, height: 18, color: i < rating ? "#FBBF24" : "var(--border)", fill: i < rating ? "#FBBF24" : "none" }} />
                  </button>
                ))}
              </div>
            </Section>

            {/* Note */}
            <Section label="Mon avis">
              <textarea
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="Vos impressions..."
                rows={3}
                className="w-full p-3 rounded-xl text-sm resize-none outline-none"
                style={{
                  background: "var(--surface2)", color: "var(--txt1)",
                  border: "1px solid var(--border)", fontFamily: "inherit",
                }}
              />
            </Section>

            {/* Description */}
            {book.description && (
              <Section label="Résumé">
                <p className="text-sm leading-relaxed line-clamp-4" style={{ color: "var(--txt2)" }}>
                  {book.description}
                </p>
              </Section>
            )}

            {/* Actions */}
            <div className="flex gap-3 pt-1">
              <Button onClick={handleSave} className="flex-1 py-3.5 rounded-2xl">
                <Save className="w-4 h-4" /> Enregistrer
              </Button>
              {!confirmDel ? (
                <Button
                  variant="ghost"
                  onClick={() => setConfirmDel(true)}
                  className="w-12 h-12 rounded-2xl"
                >
                  <Trash2 className="w-4 h-4" style={{ color: "var(--miss-t)" }} />
                </Button>
              ) : (
                <Button variant="danger" onClick={handleDelete} className="px-4 rounded-2xl text-xs">
                  Confirmer ?
                </Button>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Internal helpers ──────────────────────────────────────────────────────────

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs font-bold uppercase tracking-wider mb-2" style={{ color: "var(--txt3)" }}>{label}</p>
      {children}
    </div>
  );
}

function SegmentedControl({ options, value, onChange }: {
  options: { value: string; label: string }[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="flex gap-2">
      {options.map((o) => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          className="flex-1 py-2.5 rounded-xl text-sm font-semibold transition-all"
          style={{
            background: value === o.value ? "var(--accent)" : "var(--surface2)",
            color:      value === o.value ? "#fff"          : "var(--txt2)",
            border:     `1px solid ${value === o.value ? "var(--accent)" : "var(--border)"}`,
          }}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}
