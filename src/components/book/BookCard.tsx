"use client";
import { Book } from "@/types";
import { useState } from "react";
import { BookOpen, Star } from "lucide-react";

const STATUS = {
  lu:       { label: "Lu",       bg: "var(--have-bg)", color: "var(--have-t)" },
  en_cours: { label: "En cours", bg: "#FEF9C3",        color: "#A16207"       },
  a_lire:   { label: "À lire",   bg: "var(--accent-l)", color: "var(--accent)" },
};
const TYPE_EMOJI: Record<string, string> = { livre: "📖", bd: "🎨", manga: "⛩️" };

export default function BookCard({ book, onClick }: { book: Book; onClick?: () => void }) {
  const [imgErr, setImgErr] = useState(false);
  const s = STATUS[book.status];

  return (
    <button onClick={onClick} className="flex flex-col rounded-xl overflow-hidden text-left w-full transition-transform active:scale-95"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
      {/* Cover */}
      <div className="relative w-full overflow-hidden" style={{ aspectRatio: "2/3" }}>
        {book.cover_url && !imgErr ? (
          <img src={book.cover_url} alt={book.title} className="w-full h-full object-cover"
            onError={() => setImgErr(true)} />
        ) : (
          <div className="w-full h-full flex items-center justify-center" style={{ background: "var(--placeholder)" }}>
            <BookOpen className="w-6 h-6" style={{ color: "var(--txt3)" }} />
          </div>
        )}
        {/* Status bottom bar */}
        <div className="absolute bottom-0 left-0 right-0 text-center py-0.5"
          style={{ background: s.bg, fontSize: 9, fontWeight: 700, color: s.color }}>
          {s.label}
        </div>
        {/* Type top-right */}
        <span className="absolute top-1 right-1" style={{ fontSize: 9 }}>{TYPE_EMOJI[book.book_type]}</span>
      </div>
      {/* Info */}
      <div className="p-1.5">
        <p className="font-semibold leading-tight line-clamp-2" style={{ fontSize: 9, color: "var(--txt1)" }}>
          {book.title}
        </p>
        <p className="truncate mt-0.5" style={{ fontSize: 8, color: "var(--txt2)" }}>
          {book.authors[0]}
        </p>
        {book.rating ? (
          <div className="flex gap-0.5 mt-1">
            {Array.from({ length: 5 }).map((_, i) => (
              <Star key={i} style={{ width: 8, height: 8, color: i < book.rating! ? "#FBBF24" : "var(--border)", fill: i < book.rating! ? "#FBBF24" : "var(--border)" }} />
            ))}
          </div>
        ) : null}
      </div>
    </button>
  );
}
