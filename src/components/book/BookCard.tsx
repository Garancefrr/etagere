"use client";
import { Book } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Star } from "lucide-react";

interface Props {
  book: Book;
  onClick?: () => void;
}

export default function BookCard({ book, onClick }: Props) {
  const { bg, color, label } = STATUS_CONFIG[book.status];
  const { emoji } = TYPE_CONFIG[book.book_type];

  return (
    <button
      onClick={onClick}
      className="flex flex-col rounded-2xl overflow-hidden text-left w-full active:scale-95 transition-transform"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}
    >
      {/* Cover */}
      <div className="relative w-full" style={{ aspectRatio: "2/3" }}>
        <Cover src={book.cover_url} alt={book.title} className="w-full h-full" />

        {/* Status bar */}
        <span className="absolute bottom-0 left-0 right-0 text-center"
          style={{ background: bg, color, fontSize: 10, fontWeight: 700, padding: "3px 0" }}>
          {label}
        </span>

        {/* Type emoji */}
        <span className="absolute top-1.5 right-1.5" style={{ fontSize: 11 }}>
          {emoji}
        </span>

        {/* Collection tag — compact, top-left */}
        {book.series_name && (
          <div className="absolute top-1.5 left-1.5 flex items-center gap-0.5 rounded-md px-1 py-0.5 max-w-[65%]"
            style={{ background: "rgba(10,13,31,0.75)", backdropFilter: "blur(4px)" }}>
            <span style={{ fontSize: 7 }}>📚</span>
            <span className="truncate" style={{ fontSize: 7, fontWeight: 700, color: "#fff", lineHeight: 1.2 }}>
              {book.series_name.length > 12 ? book.series_name.slice(0, 12) + "…" : book.series_name}
              {book.series_index ? ` #${book.series_index}` : ""}
            </span>
          </div>
        )}
      </div>

      {/* Info — fixed height */}
      <div style={{ padding: "6px 6px 8px", height: 58 }}>
        <p className="font-semibold line-clamp-2" style={{ fontSize: 11, color: "var(--txt1)", lineHeight: 1.3 }}>
          {book.title}
        </p>
        <p className="truncate mt-0.5" style={{ fontSize: 10, color: "var(--txt2)" }}>
          {book.authors[0]}
        </p>
        {book.rating && (
          <div className="flex gap-0.5 mt-1">
            {Array.from({ length: 5 }).map((_, i) => (
              <Star key={i} style={{
                width: 9, height: 9,
                color: i < book.rating! ? "#FBBF24" : "var(--border)",
                fill:  i < book.rating! ? "#FBBF24" : "var(--border)",
              }} />
            ))}
          </div>
        )}
      </div>
    </button>
  );
}
