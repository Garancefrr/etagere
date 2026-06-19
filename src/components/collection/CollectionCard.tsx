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
      className="w-full flex items-center gap-2.5 px-3 py-2 active:opacity-70"
      style={{ borderBottom: "1px solid var(--border)" }}>
      {/* Cover or initial — small square */}
      {collection.cover_url ? (
        <Cover src={collection.cover_url} alt={collection.name} width={36} height={36} className="rounded-lg flex-shrink-0" />
      ) : (
        <div className="flex items-center justify-center flex-shrink-0 rounded-lg font-bold"
          style={{ width: 36, height: 36, background: "var(--accent-l)", color: "var(--accent)", fontSize: 15 }}>
          {initial}
        </div>
      )}

      {/* Info + progress */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5">
          <p className="font-bold truncate" style={{ fontSize: 13, color: "var(--txt1)" }}>{collection.name}</p>
          <span className="flex-shrink-0" style={{ fontSize: 10 }}>{emoji}</span>
        </div>
        <div className="flex items-center gap-2 mt-0.5">
          <p className="truncate" style={{ fontSize: 11, color: "var(--txt3)" }}>
            {collection.author ?? "—"}
          </p>
          <span className="flex-shrink-0 font-semibold" style={{ fontSize: 11, color: total > 0 && pct === 100 ? "var(--have-t)" : "var(--accent)" }}>
            {owned.length}{total > 0 ? `/${total}` : ""}
          </span>
        </div>
        {/* Progress bar — always visible */}
        <div className="h-1 rounded-full overflow-hidden mt-1" style={{ background: "var(--border)" }}>
          <div className="h-full rounded-full"
            style={{
              width: total > 0 ? `${pct}%` : "100%",
              background: total > 0 ? (pct === 100 ? "var(--have-t)" : "var(--accent)") : "var(--accent)",
              opacity: total > 0 ? 1 : 0.3,
            }} />
        </div>
      </div>

      {/* Chevron */}
      <svg width="12" height="12" viewBox="0 0 16 16" fill="none" style={{ flexShrink: 0, color: "var(--txt3)" }}>
        <path d="M6 4l4 4-4 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    </button>
  );
}
