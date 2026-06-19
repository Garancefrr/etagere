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

  const statusBadge = (status: string) => {
    if (status === "lu")       return { label: "Lu",       bg: "var(--have-bg)", color: "var(--have-t)" };
    if (status === "en_cours") return { label: "En cours", bg: "#FEF9C3",        color: "#A16207" };
    return                            { label: "À lire",   bg: "var(--accent-l)", color: "var(--accent)" };
  };

  const openAuthor = async (a: AuthorGroup) => {
    setSelected(a);
    setAllBooks([]);
    setLoading(true);

    try {
      // Fetch ALL books by this author from Google Books
      const res = await fetch(`/api/authors/books?author=${encodeURIComponent(a.name)}`);
      if (!res.ok) { setLoading(false); return; }
      const remote: any[] = await res.json();

      // Merge with owned books
      const mapped: DisplayBook[] = remote.map(r => ({
        title: r.title,
        cover_url: r.cover_url,
        published_year: r.published_year,
        owned: a.books.find(b =>
          b.title.toLowerCase().trim() === r.title.toLowerCase().trim() ||
          (b.isbn && b.isbn === r.isbn)
        ),
      }));

      // Add owned books not found in Google Books
      a.books.forEach(ob => {
        if (!mapped.some(m => m.owned?.id === ob.id)) {
          mapped.push({ title: ob.title, cover_url: ob.cover_url, owned: ob });
        }
      });

      // Sort: en_cours > a_lire > lu > non possédé
      const sortOrder = (db: DisplayBook) => {
        if (!db.owned) return 4;
        if (db.owned.status === "en_cours") return 0;
        if (db.owned.status === "a_lire") return 1;
        return 2;
      };
      mapped.sort((a, b) => {
        const so = sortOrder(a) - sortOrder(b);
        if (so !== 0) return so;
        return a.title.localeCompare(b.title);
      });

      setAllBooks(mapped);
    } catch { /* ignore */ }
    setLoading(false);
  };

  // Detail modal
  if (selected) {
    const lu      = selected.books.filter(b => b.status === "lu").length;
    const enCours = selected.books.filter(b => b.status === "en_cours").length;
    const aLire   = selected.books.filter(b => b.status === "a_lire").length;
    const nonPossedes = allBooks.filter(b => !b.owned).length;

    return (
      <div className="fixed inset-0 z-50 flex items-end justify-center">
        <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={() => setSelected(null)} />
        <div className="relative w-full sm:max-w-md rounded-t-3xl overflow-hidden flex flex-col"
          style={{ background: "var(--surface)", maxHeight: "90vh" }}>
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
              <div className="flex gap-2 mt-1 flex-wrap">
                {enCours > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 10, background: "#FEF9C3", color: "#A16207" }}>📖 {enCours} en cours</span>}
                {aLire > 0   && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 10, background: "var(--accent-l)", color: "var(--accent)" }}>📌 {aLire} à lire</span>}
                {lu > 0      && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 10, background: "var(--have-bg)", color: "var(--have-t)" }}>✅ {lu}</span>}
                {nonPossedes > 0 && <span className="px-1.5 py-0.5 rounded" style={{ fontSize: 10, background: "var(--surface2)", color: "var(--txt3)" }}>📕 {nonPossedes} manquant{nonPossedes > 1 ? "s" : ""}</span>}
              </div>
            </div>
            <button onClick={() => setSelected(null)} className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
              style={{ background: "var(--surface2)" }}>
              <span style={{ fontSize: 20, color: "var(--txt2)" }}>×</span>
            </button>
          </div>

          {/* Book list */}
          <div className="overflow-y-auto flex-1">
            {loading && (
              <div className="flex flex-col items-center gap-2 py-8">
                <div className="w-5 h-5 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
                <p style={{ fontSize: 12, color: "var(--txt3)" }}>Recherche des livres...</p>
              </div>
            )}
            {!loading && allBooks.map((db, i) => {
              const s = db.owned ? statusBadge(db.owned.status) : null;
              return (
                <div key={i} className="flex items-center gap-3 px-4 py-2.5"
                  style={{ borderBottom: "1px solid var(--border)", opacity: db.owned ? 1 : 0.55 }}>
                  <Cover src={db.cover_url ?? undefined} alt={db.title} width={34} height={48} className="rounded-lg flex-shrink-0" />
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold truncate" style={{ fontSize: 13, color: db.owned ? "var(--txt1)" : "var(--txt3)" }}>{db.title}</p>
                    {db.published_year && <p style={{ fontSize: 10, color: "var(--txt3)", marginTop: 1 }}>{db.published_year}</p>}
                  </div>
                  {s ? (
                    <span className="px-2 py-1 rounded-lg font-semibold flex-shrink-0"
                      style={{ fontSize: 10, background: s.bg, color: s.color }}>{s.label}</span>
                  ) : (
                    <span className="px-2 py-1 rounded-lg flex-shrink-0"
                      style={{ fontSize: 10, background: "var(--surface2)", color: "var(--txt3)", border: "1px dashed var(--border)" }}>
                      Manquant
                    </span>
                  )}
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
      <div className="mx-4 mb-3 flex items-center gap-2 px-4 py-3 rounded-2xl"
        style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
        <span style={{ fontSize: 16 }}>🔍</span>
        <input type="text" value={search} onChange={e => setSearch(e.target.value)}
          placeholder="Rechercher un auteur..."
          className="flex-1 outline-none bg-transparent" style={{ color: "var(--txt1)", fontSize: 15 }} />
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
                  : <div className="w-full h-full flex items-center justify-center" style={{ fontSize: 18 }}>✍️</div>}
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
