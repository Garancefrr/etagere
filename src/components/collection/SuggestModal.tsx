"use client";
import { useState, useEffect } from "react";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";
import { X, Sparkles, ChevronRight, Check, Layers, User } from "lucide-react";

interface SuggestionBook { id: string; title: string; series_index?: number; }
interface Suggestion {
  type: "series" | "author";
  name: string;
  cover_url?: string;
  author?: string;
  book_type: "livre" | "bd" | "manga";
  books: SuggestionBook[];
}

interface Props {
  libraryId: string;
  onClose: () => void;
  onCreated: () => void;
}

export default function SuggestModal({ libraryId, onClose, onCreated }: Props) {
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [loading,     setLoading]     = useState(true);
  const [creating,    setCreating]    = useState<string | null>(null);
  const [created,     setCreated]     = useState<Set<string>>(new Set());

  useEffect(() => {
    fetch(`/api/collections/suggest?library_id=${libraryId}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setSuggestions(d) : [])
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [libraryId]);

  const handleCreate = async (s: Suggestion) => {
    setCreating(s.name);
    try {
      const res = await fetch("/api/collections/create-from-suggestion", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          library_id: libraryId,
          name: s.name,
          author: s.author,
          book_type: s.book_type,
          cover_url: s.cover_url,
          books: s.books,
        }),
      });
      if (res.ok) {
        setCreated(prev => { const next = new Set(Array.from(prev)); next.add(s.name); return next; });
        onCreated();
      }
    } finally {
      setCreating(null);
    }
  };

  const pending = suggestions.filter(s => !created.has(s.name));

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl flex flex-col"
        style={{ background: "var(--surface)", maxHeight: "85vh" }}>
        {/* Handle */}
        <div className="flex justify-center pt-3 flex-shrink-0">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>

        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 flex-shrink-0"
          style={{ borderBottom: "1px solid var(--border)" }}>
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-xl flex items-center justify-center"
              style={{ background: "var(--accent-l)" }}>
              <Sparkles className="w-4 h-4" style={{ color: "var(--accent)" }} />
            </div>
            <div>
              <h2 className="font-bold" style={{ fontSize: 17, color: "var(--txt1)" }}>Suggestions</h2>
              <p style={{ fontSize: 12, color: "var(--txt3)" }}>Basées sur ta bibliothèque</p>
            </div>
          </div>
          <button onClick={onClose} className="w-10 h-10 rounded-full flex items-center justify-center"
            style={{ background: "var(--surface2)" }}>
            <X className="w-5 h-5" style={{ color: "var(--txt2)" }} />
          </button>
        </div>

        {/* Content */}
        <div className="overflow-y-auto flex-1 px-4 py-4 flex flex-col gap-3">
          {loading && (
            <div className="flex justify-center py-12">
              <div className="w-8 h-8 rounded-full border-2 animate-spin"
                style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
            </div>
          )}

          {!loading && suggestions.length === 0 && (
            <div className="flex flex-col items-center py-12 gap-3">
              <span style={{ fontSize: 40 }}>📚</span>
              <p className="font-semibold text-center" style={{ fontSize: 16, color: "var(--txt1)" }}>
                Pas de suggestion pour le moment
              </p>
              <p className="text-center px-4" style={{ fontSize: 14, color: "var(--txt3)", lineHeight: 1.5 }}>
                Continue à ajouter des livres ! Des collections seront proposées dès que des séries ou des auteurs récurrents seront détectés.
              </p>
            </div>
          )}

          {!loading && pending.length === 0 && created.size > 0 && (
            <div className="flex flex-col items-center py-8 gap-3">
              <div className="w-14 h-14 rounded-2xl flex items-center justify-center"
                style={{ background: "var(--have-bg)" }}>
                <Check className="w-7 h-7" style={{ color: "var(--have-t)" }} />
              </div>
              <p className="font-semibold" style={{ fontSize: 16, color: "var(--txt1)" }}>
                {Array.from(created.values()).length} {Array.from(created.values()).length > 1 ? "collections créées" : "collection créée"} !
              </p>
            </div>
          )}

          {pending.map(s => (
            <div key={s.name} className="flex items-center gap-3 p-4 rounded-2xl"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
              <Cover src={s.cover_url} alt={s.name} width={52} height={72} className="rounded-xl flex-shrink-0" />
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-1.5 mb-0.5">
                  {s.type === "series"
                    ? <Layers className="w-3.5 h-3.5 flex-shrink-0" style={{ color: "var(--accent)" }} />
                    : <User className="w-3.5 h-3.5 flex-shrink-0" style={{ color: "#FB923C" }} />}
                  <span style={{ fontSize: 10, fontWeight: 700, color: s.type === "series" ? "var(--accent)" : "#FB923C", textTransform: "uppercase", letterSpacing: "0.08em" }}>
                    {s.type === "series" ? "Série" : "Auteur"}
                  </span>
                </div>
                <p className="font-bold truncate" style={{ fontSize: 15, color: "var(--txt1)" }}>{s.name}</p>
                {s.author && s.type !== "author" && (
                  <p style={{ fontSize: 12, color: "var(--txt2)", marginTop: 1 }}>{s.author}</p>
                )}
                <p style={{ fontSize: 12, color: "var(--txt3)", marginTop: 2 }}>
                  {s.books.length} {s.books.length > 1 ? "livres" : "livre"} dans ta biblio
                </p>
                {/* Book titles preview */}
                <p className="truncate mt-1" style={{ fontSize: 11, color: "var(--txt3)" }}>
                  {s.books.slice(0, 3).map(b => b.title).join(", ")}
                  {s.books.length > 3 ? `… +${s.books.length - 3}` : ""}
                </p>
              </div>
              <button onClick={() => handleCreate(s)}
                disabled={creating === s.name}
                className="flex-shrink-0 w-10 h-10 rounded-2xl flex items-center justify-center"
                style={{ background: "var(--accent)", opacity: creating === s.name ? 0.6 : 1 }}>
                {creating === s.name
                  ? <div className="w-4 h-4 rounded-full border-2 animate-spin"
                      style={{ borderColor: "#fff", borderTopColor: "transparent" }} />
                  : <ChevronRight className="w-5 h-5 text-white" />}
              </button>
            </div>
          ))}

          {/* Created ones */}
          {Array.from(created.values()).map(name => (
            <div key={name} className="flex items-center gap-3 p-4 rounded-2xl"
              style={{ background: "var(--have-bg)", border: "1px solid var(--have-b)", opacity: 0.7 }}>
              <div className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
                style={{ background: "var(--have-t)" }}>
                <Check className="w-5 h-5 text-white" />
              </div>
              <p className="font-semibold" style={{ fontSize: 14, color: "var(--have-t)" }}>
                {name} — créée ✅
              </p>
            </div>
          ))}
        </div>

        {/* Footer */}
        {!loading && pending.length > 0 && (
          <div className="px-4 pb-8 pt-3 flex-shrink-0" style={{ borderTop: "1px solid var(--border)" }}>
            <Button
              onClick={async () => {
                for (const s of pending) await handleCreate(s);
              }}
              disabled={creating !== null}
              className="w-full py-4 rounded-2xl"
              style={{ fontSize: 15 }}>
              <Sparkles className="w-5 h-5" />
              Créer toutes les suggestions ({pending.length})
            </Button>
          </div>
        )}
      </div>
    </div>
  );
}
