"use client";
import { Collection } from "@/types";
import { BookOpen } from "lucide-react";
import { useState } from "react";

interface Props { collection: Collection; onClick?: () => void; }

export default function CollectionCard({ collection, onClick }: Props) {
  const [imgErr, setImgErr] = useState(false);
  const owned = collection.owned_volumes.length;
  const total = collection.total_volumes;
  const pct = total ? Math.round((owned / total) * 100) : 0;
  const missing = total
    ? Array.from({ length: total }, (_, i) => i + 1).filter(n => !collection.owned_volumes.includes(n))
    : [];
  const TYPE_LABEL: Record<string, string> = { livre: "📖 Saga", bd: "🎨 BD", manga: "⛩️ Manga" };

  return (
    <div className="rounded-2xl overflow-hidden cursor-pointer transition-transform active:scale-[0.98]"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}
      onClick={onClick}>
      <div className="flex gap-3 p-3">
        <div className="w-12 h-16 rounded-lg overflow-hidden flex-shrink-0 flex items-center justify-center shadow-sm"
          style={{ background: "var(--placeholder)" }}>
          {collection.cover_url && !imgErr
            ? <img src={collection.cover_url} alt={collection.name} className="w-full h-full object-cover" onError={() => setImgErr(true)} />
            : <BookOpen className="w-5 h-5" style={{ color: "var(--txt3)" }} />}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <h3 className="font-bold text-sm leading-tight" style={{ color: "var(--txt1)" }}>{collection.name}</h3>
            <span className="text-xs flex-shrink-0 mt-0.5">{TYPE_LABEL[collection.book_type]}</span>
          </div>
          {collection.author && (
            <p className="text-xs mt-0.5 truncate" style={{ color: "var(--txt2)" }}>{collection.author}</p>
          )}
          <div className="flex items-center gap-2 mt-2">
            <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
              <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
            </div>
            <span className="text-xs font-bold flex-shrink-0" style={{ color: "var(--accent)" }}>
              {owned}{total ? `/${total}` : ""}
            </span>
            {missing.length > 0 && (
              <span className="text-xs font-bold px-2 py-0.5 rounded-full flex-shrink-0"
                style={{ background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px solid var(--miss-b)" }}>
                {missing.length} manquant{missing.length > 1 ? "s" : ""}
              </span>
            )}
          </div>
        </div>
      </div>
      {total && total <= 72 && (
        <div className="flex flex-wrap gap-1.5 px-3 pb-3">
          {Array.from({ length: Math.min(total, 20) }, (_, i) => i + 1).map(n => (
            <div key={n} className="vol-chip"
              style={collection.owned_volumes.includes(n)
                ? { background: "var(--have-bg)", color: "var(--have-t)", border: "1px solid var(--have-b)" }
                : { background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px dashed var(--miss-b)" }}>
              {n}
            </div>
          ))}
          {total > 20 && (
            <div className="vol-chip" style={{ background: "var(--accent-l)", color: "var(--accent)", border: "1px solid var(--border)" }}>
              +{total - 20}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
