"use client";
import { Collection } from "@/types";
import { TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";

interface Props {
  collection: Collection;
  onEdit?: () => void;
  onDelete?: () => void;
}

export default function CollectionCard({ collection, onEdit, onDelete }: Props) {
  const { emoji } = TYPE_CONFIG[collection.book_type] ?? { emoji: "📖" };
  const owned = Array.from(new Set(collection.owned_volumes ?? [])).sort((a, b) => a - b);
  const total = collection.total_volumes ?? 0;
  const pct   = total > 0 ? Math.round((owned.length / total) * 100) : 0;

  // Build the list of volumes to display
  // If total is set: show 1..total with green (owned) and red (missing)
  // If total is not set: show only owned volumes in green
  const maxDisplay = total > 0 ? Math.min(total, 40) : owned.length;
  const volumes = total > 0
    ? Array.from({ length: maxDisplay }, (_, i) => i + 1)
    : owned;

  return (
    <div className="rounded-2xl overflow-hidden"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
      <div className="flex gap-3 p-4">
        <Cover src={collection.cover_url} alt={collection.name} width={56} height={78} className="rounded-xl flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="font-bold truncate" style={{ fontSize: 16, color: "var(--txt1)" }}>{collection.name}</p>
              {collection.author && <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{collection.author}</p>}
            </div>
            <span style={{ fontSize: 14, flexShrink: 0 }}>{emoji}</span>
          </div>

          {/* Progress bar — only if total is set */}
          {total > 0 && (
            <div className="flex items-center gap-2 mt-3">
              <div className="flex-1 h-2 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
                <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
              </div>
              <span className="font-bold flex-shrink-0" style={{ fontSize: 13, color: "var(--accent)" }}>
                {owned.length}/{total}
              </span>
            </div>
          )}

          {/* Count without bar — when total is not set */}
          {total === 0 && owned.length > 0 && (
            <p className="mt-2 font-semibold" style={{ fontSize: 13, color: "var(--accent)" }}>
              {owned.length} tome{owned.length > 1 ? "s" : ""}
            </p>
          )}
        </div>
      </div>

      {/* Volume chips */}
      {volumes.length > 0 && (
        <div className="flex flex-wrap gap-1.5 px-4 pb-4">
          {volumes.map(n => {
            const isOwned = owned.includes(n);
            return (
              <div key={n} className="flex items-center justify-center font-bold"
                style={{
                  width: 30, height: 30, borderRadius: 8, fontSize: 11,
                  background: isOwned ? "var(--have-bg)" : "var(--miss-bg)",
                  color:      isOwned ? "var(--have-t)"  : "var(--miss-t)",
                  border:     isOwned ? "1px solid var(--have-b)" : "1px dashed var(--miss-b)",
                }}>
                {n}
              </div>
            );
          })}
          {total > 40 && (
            <div className="flex items-center justify-center font-bold"
              style={{ width: 30, height: 30, borderRadius: 8, fontSize: 11, background: "var(--accent-l)", color: "var(--accent)" }}>
              +{total - 40}
            </div>
          )}
        </div>
      )}

      {/* Actions */}
      {(onEdit || onDelete) && (
        <div className="flex gap-2 px-4 pb-4">
          {onEdit && (
            <button onClick={onEdit} className="flex-1 py-2 rounded-xl font-semibold text-center"
              style={{ fontSize: 12, background: "var(--surface2)", color: "var(--txt2)", border: "1px solid var(--border)" }}>
              ✏️ Modifier
            </button>
          )}
          {onDelete && (
            <button onClick={onDelete} className="py-2 px-4 rounded-xl font-semibold"
              style={{ fontSize: 12, background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px solid var(--miss-b)" }}>
              🗑️
            </button>
          )}
        </div>
      )}
    </div>
  );
}
