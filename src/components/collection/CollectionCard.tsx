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
  const initial = collection.name[0]?.toUpperCase() ?? "?";

  return (
    <button onClick={onClick}
      className="w-full flex items-center gap-3 px-3 py-2.5 active:opacity-70"
      style={{ borderBottom: "1px solid var(--border)" }}>
      {/* Cover or colored initial */}
      {collection.cover_url ? (
        <Cover src={collection.cover_url} alt={collection.name} width={38} height={52} className="rounded-lg flex-shrink-0" />
      ) : (
        <div className="flex items-center justify-center flex-shrink-0 rounded-lg font-bold"
          style={{ width: 38, height: 52, background: "var(--accent-l)", color: "var(--accent)", fontSize: 18 }}>
          {initial}
        </div>
      )}

      {/* Info */}
      <div className="flex-1 min-w-0">
        <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>
          {collection.name}
        </p>
        <p className="truncate" style={{ fontSize: 12, color: "var(--txt2)", marginTop: 1 }}>
          {collection.author ?? emoji}
          <span style={{ color: "var(--txt3)", marginLeft: 6 }}>
            · {owned.length}{total > 0 ? `/${total}` : ""} {emoji}
          </span>
        </p>
        {/* Progress bar */}
        {total > 0 && (
          <div className="h-1 rounded-full overflow-hidden mt-1.5" style={{ background: "var(--border)", maxWidth: 120 }}>
            <div className="h-full rounded-full" style={{ width: `${pct}%`, background: pct === 100 ? "var(--have-t)" : "var(--accent)" }} />
          </div>
        )}
      </div>

      {/* Chevron */}
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none" style={{ flexShrink: 0, color: "var(--txt3)" }}>
        <path d="M6 4l4 4-4 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    </button>
  );
}
