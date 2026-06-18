"use client";
import { Collection } from "@/types";
import { TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";

interface Props {
  collection: Collection;
  onClick: () => void;
}

export default function CollectionCard({ collection, onClick }: Props) {
  const { emoji } = TYPE_CONFIG[collection.book_type] ?? { emoji: "📖" };
  const owned = Array.from(new Set(collection.owned_volumes ?? []));
  const total = collection.total_volumes ?? 0;
  const pct   = total > 0 ? Math.round((owned.length / total) * 100) : 0;

  return (
    <button onClick={onClick}
      className="w-full flex items-center gap-3 px-4 py-3 active:opacity-70"
      style={{ borderBottom: "1px solid var(--border)" }}>
      {/* Cover */}
      <Cover src={collection.cover_url} alt={collection.name} width={42} height={58} className="rounded-lg flex-shrink-0" />

      {/* Info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5">
          <span style={{ fontSize: 11 }}>{emoji}</span>
          <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{collection.name}</p>
        </div>
        {collection.author && (
          <p className="truncate" style={{ fontSize: 12, color: "var(--txt2)", marginTop: 1 }}>{collection.author}</p>
        )}
        {/* Progress */}
        {total > 0 ? (
          <div className="flex items-center gap-2 mt-1.5">
            <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
              <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
            </div>
            <span className="flex-shrink-0 font-semibold" style={{ fontSize: 11, color: "var(--accent)" }}>
              {owned.length}/{total}
            </span>
          </div>
        ) : (
          <p style={{ fontSize: 11, color: "var(--accent)", marginTop: 1 }}>
            {owned.length} {owned.length > 1 ? "livres" : "livre"}
          </p>
        )}
      </div>

      {/* Chevron */}
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" style={{ flexShrink: 0, color: "var(--txt3)" }}>
        <path d="M6 4l4 4-4 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    </button>
  );
}
