"use client";
import { useState, useMemo } from "react";
import { Book } from "@/types";
import { Cover } from "@/components/ui/Cover";
import { ChevronRight, X } from "lucide-react";

interface Props {
  books: Book[];
}

interface AuthorGroup {
  name: string;
  books: Book[];
  cover?: string;
}

interface DisplayBook {
  title: string;
  cover_url?: string | null;
  published_year?: number | null;
  owned?: Book;
}

export default function AuthorView({ books }: Props) {
  const [selected, setSelected] = useState<AuthorGroup | null>(null);
  const [search, setSearch] = useState("");
  const [allBooks, setAllBooks] = useState<DisplayBook[]>([]);
  const [loading, setLoading] = useState(false);

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
      .map(([name, authorBooks]) => ({
        name,
        books: authorBooks.sort((a, b) => {
          const order: Record<string, number> = { en_cours: 0, a_lire: 1, lu: 2 };
          return (order[a.status] ?? 9) - (order[b.status] ?? 9);
        }),
        cover: authorBooks.find(b => b.cover_url)?.cover_url,
      }));
  }, [books]);

  const filtered = authors.filter(a =>
    !search || a.name.toLowerCase().includes(search.toLowerCase())
  );

  const statusTag = (b?: Book) => {
    if (!b) return { label: "Manquant", bg: "var(--miss-bg)", color: "var(--miss-t)", border: true };
    if (b.status === "lu")       return { label: "Lu",       bg: "var(--have-bg)", color: "var(--have-t)", border: false };
    if (b.status === "en_cours") return { label: "En cours", bg: "#FEF9C3",        color: "#A16207",      border: false };
    return                              { label: "À lire",   bg: "var(--accent-l)", color: "var(--accent)", border: false };
  };

  const openAuthor = async (a: AuthorGroup) => {
    setSelected(a);
    setAllBooks([]);
    setLoading(true);
    try {
      const res = await fetch(`/api/authors/books?author=${encodeURIComponent(a.name)}`);
      if (!res.ok) { setLoading(false); return; }
      const remote: any[] = await res.json();
      const mapped: DisplayBook[] = remote.map(r => ({
        title: r.title, cover_url: r.cover_url, published_year: r.published_year,
        owned: a.books.find(b => b.title.toLowerCase().trim() === r.title.toLowerCase().trim() || (b.isbn && b.isbn === r.isbn)),
      }));
      a.books.forEach(ob => {
        if (!mapped.some(m => m.owned?.id === ob.id))
          mapped.push({ title: ob.title, cover_url: ob.cover_url, owned: ob });
      });
      const so = (db: DisplayBook) => !db.owned ? 4 : db.owned.status === "en_cours" ? 0 : db.owned.status === "a_lire" ? 1 : 2;
      mapped.sort((a, b) => so(a) - so(b) || a.title.localeCompare(b.title));
      setAllBooks(mapped);
    } catch { /* ignore */ }
    setLoading(false);
  };

  // Detail modal — same grid design as CollectionDetail
  if (selected) {
    const lu      = selected.books.filter(b => b.status === "lu").length;
    const enCours = selected.books.filter(b => b.status === "en_cours").length;
    const aLire   = selected.books.filter(b => b.status === "a_lire").length;
    const nonOwned = allBooks.filter(b => !b.owned).length;
    const ownedCount = selected.books.length;
    const pct = ownedCount > 0 ? Math.round((lu / ownedCount) * 100) : 0;

    const displayBooks = allBooks.length > 0
      ? allBooks
      : selected.books.map(b => ({ title: b.title, cover_url: b.cover_url, owned: b } as DisplayBook));

    return (
      <div className="fixed inset-0 z-50 flex items-end justify-center">
        <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={() => setSelected(null)} />
        <div className="relative w-full sm:max-w-md rounded-t-3xl overflow-hidden flex flex-col"
          style={{ background: "var(--surface)", maxHeight: "92vh" }}>
          <div className="flex justify-center pt-2 flex-shrink-0">
            <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
          </div>

          {/* Header — same as CollectionDetail */}
          <div className="px-4 pt-1 pb-2 flex-shrink-0" style={{ borderBottom: "1px solid var(--border)" }}>
            <div className="flex items-center gap-2 mb-1">
              <p className="font-bold flex-1 truncate" style={{ fontSize: 16, color: "var(--txt1)" }}>✍️ {selected.name}</p>
              <button onClick={() => setSelected(null)} className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
                style={{ background: "var(--surface2)" }}>
                <X className="w-5 h-5" style={{ color: "var(--txt2)" }} />
              </button>
            </div>
            <div className="flex items-center gap-2 flex-wrap">
              {enCours > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 11, background: "#FEF9C3", color: "#A16207" }}>📖 {enCours}</span>}
              {aLire > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 11, background: "var(--accent-l)", color: "var(--accent)" }}>📌 {aLire}</span>}
              {lu > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 11, background: "var(--have-bg)", color: "var(--have-t)" }}>✅ {lu}</span>}
              {nonOwned > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 11, background: "var(--surface2)", color: "var(--txt3)" }}>📕 {nonOwned}</span>}
            </div>
            <div className="h-1 rounded-full overflow-hidden mt-1.5" style={{ background: "var(--border)" }}>
              <div className="h-full rounded-full" style={{ width: `${Math.max(pct, 2)}%`, background: pct === 100 ? "var(--have-t)" : "var(--accent)" }} />
            </div>
          </div>

          {/* Grid — same as CollectionDetail */}
          <div className="overflow-y-auto flex-1 p-3">
            {loading && <div className="flex justify-center py-8"><div className="w-5 h-5 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} /></div>}
            {!loading && (() => {
              const owned = displayBooks.filter(b => b.owned);
              const missing = displayBooks.filter(b => !b.owned);
              const renderGrid = (items: typeof displayBooks) => (
                <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10 }}>
                  {items.map((rb, i) => {
                    const s = statusTag(rb.owned);
                    return (
                      <div key={i} className="flex flex-col" style={{ opacity: rb.owned ? 1 : 0.5 }}>
                        <div className="relative w-full overflow-hidden rounded-lg" style={{ height: 150 }}>
                          <Cover src={rb.cover_url ?? undefined} alt={rb.title} className="w-full h-full object-cover" />
                          <span className="absolute bottom-0 left-0 right-0 text-center py-0.5 font-bold"
                            style={{ fontSize: 10, background: s.bg, color: s.color,
                              border: s.border ? "1px dashed var(--border)" : "none", borderTop: "none" }}>
                            {s.label}
                          </span>
                        </div>
                        <div style={{ height: 28 }}>
                          <p className="font-semibold mt-1 line-clamp-2" style={{ fontSize: 10, color: rb.owned ? "var(--txt1)" : "var(--txt3)", lineHeight: 1.2 }}>
                            {rb.title}
                          </p>
                        </div>
                      </div>
                    );
                  })}
                </div>
              );
              return <>
                {owned.length > 0 && <>
                  <p className="font-bold uppercase tracking-wider mb-2" style={{ fontSize: 11, color: "var(--accent)" }}>
                    📚 Ma bibliothèque ({owned.length})
                  </p>
                  {renderGrid(owned)}
                </>}
                {missing.length > 0 && <>
                  <p className="font-bold uppercase tracking-wider mt-4 mb-2" style={{ fontSize: 11, color: "var(--miss-t)" }}>
                    📕 Manquants ({missing.length})
                  </p>
                  {renderGrid(missing)}
                </>}
              </>;
            })()}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="mx-4 mb-3 flex items-center gap-2 px-4 py-3 rounded-2xl"
        style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
        <span style={{ fontSize: 16 }}>🔍</span>
        <input type="text" value={search} onChange={e => setSearch(e.target.value)}
          placeholder="Rechercher un auteur..."
          className="flex-1 outline-none bg-transparent" style={{ color: "var(--txt1)", fontSize: 16 }} />
      </div>

      <div className="mx-4 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        {filtered.length === 0 ? (
          <p className="text-center py-12" style={{ fontSize: 14, color: "var(--txt3)" }}>Aucun auteur trouvé</p>
        ) : filtered.map(a => {
          const lu      = a.books.filter(b => b.status === "lu").length;
          const enCours = a.books.filter(b => b.status === "en_cours").length;
          const aLire   = a.books.filter(b => b.status === "a_lire").length;
          return (
            <button key={a.name} onClick={() => openAuthor(a)}
              className="w-full flex items-center gap-3 px-4 py-3 active:opacity-70"
              style={{ borderBottom: "1px solid var(--border)" }}>
              <div className="w-10 h-10 rounded-xl overflow-hidden flex-shrink-0" style={{ background: "var(--surface2)" }}>
                {a.cover
                  ? <Cover src={a.cover} alt={a.name} width={40} height={40} className="w-full h-full object-cover" />
                  : <div className="w-full h-full flex items-center justify-center font-bold" style={{ fontSize: 15, color: "var(--accent)", background: "var(--accent-l)" }}>{a.name[0]}</div>}
              </div>
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
