"use client";
import { useState, useMemo } from "react";
import { Book } from "@/types";
import { Cover } from "@/components/ui/Cover";
import { ChevronRight } from "lucide-react";

interface Props {
  books: Book[];
}

interface AuthorGroup {
  name: string;
  books: Book[];
  cover?: string;
}

export default function AuthorView({ books }: Props) {
  const [selected, setSelected] = useState<AuthorGroup | null>(null);
  const [search, setSearch] = useState("");

  // Group books by first author
  const authors: AuthorGroup[] = useMemo(() => {
    const map: Record<string, Book[]> = {};
    books.forEach(b => {
      const author = b.authors[0];
      if (!author) return;
      if (!map[author]) map[author] = [];
      map[author].push(b);
    });
    return Object.entries(map)
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([name, books]) => ({
        name,
        books: books.sort((a, b) => {
          // Sort: en_cours first, then a_lire, then lu
          const order = { en_cours: 0, a_lire: 1, lu: 2 };
          return order[a.status] - order[b.status];
        }),
        cover: books.find(b => b.cover_url)?.cover_url,
      }));
  }, [books]);

  const filtered = authors.filter(a =>
    !search || a.name.toLowerCase().includes(search.toLowerCase())
  );

  const statusBadge = (status: string) => {
    if (status === "lu")       return { label: "Lu",       bg: "var(--have-bg)", color: "var(--have-t)" };
    if (status === "en_cours") return { label: "En cours", bg: "#FEF9C3",        color: "#A16207" };
    return                            { label: "À lire",   bg: "var(--accent-l)", color: "var(--accent)" };
  };

  // Author detail modal
  if (selected) {
    const lu      = selected.books.filter(b => b.status === "lu").length;
    const enCours = selected.books.filter(b => b.status === "en_cours").length;
    const aLire   = selected.books.filter(b => b.status === "a_lire").length;

    return (
      <div className="fixed inset-0 z-50 flex items-end justify-center">
        <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={() => setSelected(null)} />
        <div className="relative w-full sm:max-w-md rounded-t-3xl overflow-hidden flex flex-col"
          style={{ background: "var(--surface)", maxHeight: "90vh" }}>
          {/* Handle */}
          <div className="flex justify-center pt-3 flex-shrink-0">
            <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
          </div>

          {/* Header */}
          <div className="flex items-center gap-3 px-4 py-3 flex-shrink-0"
            style={{ borderBottom: "1px solid var(--border)" }}>
            <div className="w-12 h-12 rounded-xl overflow-hidden flex-shrink-0" style={{ background: "var(--surface2)" }}>
              {selected.cover
                ? <Cover src={selected.cover} alt={selected.name} width={48} height={48} className="w-full h-full object-cover" />
                : <div className="w-full h-full flex items-center justify-center" style={{ fontSize: 22 }}>✍️</div>}
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-bold truncate" style={{ fontSize: 17, color: "var(--txt1)" }}>{selected.name}</p>
              <div className="flex gap-3 mt-1">
                {enCours > 0 && <span style={{ fontSize: 11, color: "#A16207" }}>📖 {enCours} en cours</span>}
                {aLire > 0   && <span style={{ fontSize: 11, color: "var(--accent)" }}>📌 {aLire} à lire</span>}
                {lu > 0      && <span style={{ fontSize: 11, color: "var(--have-t)" }}>✅ {lu} lu{lu > 1 ? "s" : ""}</span>}
              </div>
            </div>
            <button onClick={() => setSelected(null)} className="w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0"
              style={{ background: "var(--surface2)" }}>
              <span style={{ fontSize: 16, color: "var(--txt2)" }}>×</span>
            </button>
          </div>

          {/* Book list */}
          <div className="overflow-y-auto flex-1">
            {selected.books.map(b => {
              const s = statusBadge(b.status);
              return (
                <div key={b.id} className="flex items-center gap-3 px-4 py-3"
                  style={{ borderBottom: "1px solid var(--border)" }}>
                  <Cover src={b.cover_url} alt={b.title} width={38} height={52} className="rounded-lg flex-shrink-0" />
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold truncate" style={{ fontSize: 13, color: "var(--txt1)" }}>{b.title}</p>
                    <p style={{ fontSize: 11, color: "var(--txt3)", marginTop: 1 }}>
                      {[b.series_name ? `${b.series_name}${b.series_index ? ` #${b.series_index}` : ""}` : null, b.published_year].filter(Boolean).join(" · ")}
                    </p>
                  </div>
                  <span className="px-2 py-1 rounded-lg font-semibold flex-shrink-0"
                    style={{ fontSize: 10, background: s.bg, color: s.color }}>
                    {s.label}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div>
      {/* Search */}
      <div className="mx-4 mb-3 flex items-center gap-2 px-4 py-3 rounded-2xl"
        style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
        <span style={{ fontSize: 16 }}>🔍</span>
        <input type="text" value={search} onChange={e => setSearch(e.target.value)}
          placeholder="Rechercher un auteur..."
          className="flex-1 outline-none bg-transparent" style={{ color: "var(--txt1)", fontSize: 15 }} />
      </div>

      {/* Author list */}
      <div className="mx-4 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        {filtered.length === 0 ? (
          <p className="text-center py-12" style={{ fontSize: 14, color: "var(--txt3)" }}>Aucun auteur trouvé</p>
        ) : filtered.map(a => {
          const lu      = a.books.filter(b => b.status === "lu").length;
          const enCours = a.books.filter(b => b.status === "en_cours").length;
          const aLire   = a.books.filter(b => b.status === "a_lire").length;
          return (
            <button key={a.name} onClick={() => setSelected(a)}
              className="w-full flex items-center gap-3 px-4 py-3 active:opacity-70"
              style={{ borderBottom: "1px solid var(--border)" }}>
              {/* Avatar */}
              <div className="w-10 h-10 rounded-xl overflow-hidden flex-shrink-0" style={{ background: "var(--surface2)" }}>
                {a.cover
                  ? <Cover src={a.cover} alt={a.name} width={40} height={40} className="w-full h-full object-cover" />
                  : <div className="w-full h-full flex items-center justify-center" style={{ fontSize: 18 }}>✍️</div>}
              </div>
              {/* Info */}
              <div className="flex-1 min-w-0 text-left">
                <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{a.name}</p>
                <div className="flex gap-2 mt-0.5 flex-wrap">
                  {enCours > 0 && <span style={{ fontSize: 11, color: "#A16207" }}>📖 {enCours}</span>}
                  {aLire > 0   && <span style={{ fontSize: 11, color: "var(--accent)" }}>📌 {aLire}</span>}
                  {lu > 0      && <span style={{ fontSize: 11, color: "var(--have-t)" }}>✅ {lu}</span>}
                </div>
              </div>
              <ChevronRight className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
            </button>
          );
        })}
      </div>
    </div>
  );
}
