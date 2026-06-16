"use client";
import { Collection } from "@/types";
import { TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";

interface Props {
  collection: Collection;
  onClick?: () => void;
}

export default function CollectionCard({ collection, onClick }: Props) {
  const owned   = collection.owned_volumes.length;
  const total   = collection.total_volumes;
  const pct     = total ? Math.round((owned / total) * 100) : 0;
  const missing = total
    ? Array.from({ length: total }, (_, i) => i + 1).filter(n => !collection.owned_volumes.includes(n))
    : [];

  return (
    <div
      className="rounded-2xl overflow-hidden cursor-pointer active:scale-[0.98] transition-transform"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}
      onClick={onClick}
    >
      {/* Header */}
      <div className="flex gap-3 p-3">
        <Cover
          src={collection.cover_url}
          alt={collection.name}
          width={48}
          height={64}
          className="rounded-lg shadow-sm flex-shrink-0"
        />

        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <h3 className="font-bold text-sm leading-tight" style={{ color: "var(--txt1)" }}>
              {collection.name}
            </h3>
            <span style={{ fontSize: 11, flexShrink: 0, marginTop: 1 }}>
              {TYPE_CONFIG[collection.book_type].emoji}
            </span>
          </div>

          {collection.author && (
            <p className="text-xs mt-0.5 truncate" style={{ color: "var(--txt2)" }}>{collection.author}</p>
          )}

          {/* Progress */}
          <div className="flex items-center gap-2 mt-2">
            <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
              <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
            </div>
            <span className="text-xs font-bold flex-shrink-0" style={{ color: "var(--accent)" }}>
              {owned}{total ? `/${total}` : ""}
            </span>
            {missing.length > 0 && (
              <span
                className="text-xs font-bold px-2 py-0.5 rounded-full flex-shrink-0"
                style={{ background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px solid var(--miss-b)" }}
              >
                {missing.length} manquant{missing.length > 1 ? "s" : ""}
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Volume chips — only if collection has ≤ 40 volumes */}
      {total && total <= 40 && (
        <div className="flex flex-wrap gap-1.5 px-3 pb-3">
          {Array.from({ length: Math.min(total, 20) }, (_, i) => i + 1).map(n => (
            <VolumeChip key={n} n={n} owned={collection.owned_volumes.includes(n)} />
          ))}
          {total > 20 && (
            <div
              className="flex items-center justify-center font-bold"
              style={{ width: 28, height: 28, borderRadius: 7, background: "var(--accent-l)", color: "var(--accent)", fontSize: 10 }}
            >
              +{total - 20}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function VolumeChip({ n, owned }: { n: number; owned: boolean }) {
  return (
    <div
      className="flex items-center justify-center font-bold"
      style={{
        width: 28, height: 28, borderRadius: 7, fontSize: 10,
        background: owned ? "var(--have-bg)" : "var(--miss-bg)",
        color:      owned ? "var(--have-t)"  : "var(--miss-t)",
        border:     owned ? "1px solid var(--have-b)" : "1px dashed var(--miss-b)",
      }}
    >
      {n}
    </div>
  );
}

