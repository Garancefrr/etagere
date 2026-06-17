"use client";
import { useState, useEffect, useMemo } from "react";
import { useLibrary } from "@/hooks/useLibrary";
import { Book } from "@/types";
import BottomNav from "@/components/layout/BottomNav";
import { BookOpen, TrendingUp, FileText, Star } from "lucide-react";

export default function StatsPage() {
  const { library_id, loading: libLoading } = useLibrary();
  const [books,   setBooks]   = useState<Book[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!library_id) return;
    fetch(`/api/books?library_id=${library_id}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setBooks(d) : [])
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [library_id]);

  // Auto-refresh on focus
  useEffect(() => {
    if (!library_id) return;
    const refresh = () => {
      fetch(`/api/books?library_id=${library_id}`)
        .then(r => r.json())
        .then(d => Array.isArray(d) ? setBooks(d) : [])
        .catch(console.error);
    };
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") refresh(); });
    return () => window.removeEventListener("focus", refresh);
  }, [library_id]);

  const stats = useMemo(() => {
    const lu      = books.filter(b => b.status === "lu");
    const pages   = lu.reduce((s, b) => s + (b.page_count ?? 0), 0);
    const ratings = lu.filter(b => b.rating).map(b => b.rating!);
    const avg     = ratings.length ? (ratings.reduce((a, b) => a + b, 0) / ratings.length).toFixed(1) : null;
    const thisYear = new Date().getFullYear();
    const luThisYear = lu.filter(b => new Date(b.updated_at).getFullYear() === thisYear).length;
    const authorCount: Record<string, number> = {};
    books.forEach(b => b.authors.forEach(a => { authorCount[a] = (authorCount[a] ?? 0) + 1; }));
    const topAuthors = Object.entries(authorCount).sort((a, b) => b[1] - a[1]).slice(0, 5);
    return {
      total: books.length,
      lu: lu.length,
      en_cours: books.filter(b => b.status === "en_cours").length,
      a_lire: books.filter(b => b.status === "a_lire").length,
      livres: books.filter(b => b.book_type === "livre").length,
      bds: books.filter(b => b.book_type === "bd").length,
      mangas: books.filter(b => b.book_type === "manga").length,
      pages, avg, luThisYear, topAuthors,
    };
  }, [books]);

  const isLoading = libLoading || loading;

  if (isLoading) return (
    <div className="min-h-screen flex items-center justify-center" style={{ background: "var(--bg)" }}>
      <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
      <BottomNav />
    </div>
  );

  if (stats.total === 0) return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4 pb-24" style={{ background: "var(--bg)" }}>
      <BookOpen className="w-12 h-12" style={{ color: "var(--txt3)", opacity: 0.3 }} />
      <p className="font-bold" style={{ fontSize: 17, color: "var(--txt1)" }}>Aucune stat pour l&apos;instant</p>
      <p className="text-center px-8" style={{ fontSize: 14, color: "var(--txt3)" }}>Scannez vos premiers livres pour voir vos statistiques</p>
      <BottomNav />
    </div>
  );

  const KPI_ITEMS = [
    { icon: BookOpen,   label: "Lus au total",  value: stats.lu,                                        sub: `sur ${stats.total} ouvrages`, color: "var(--accent)" },
    { icon: TrendingUp, label: "Cette année",   value: stats.luThisYear,                                sub: "livres terminés",             color: "#22C55E"       },
    { icon: FileText,   label: "Pages lues",    value: stats.pages > 0 ? stats.pages.toLocaleString("fr") : "—", sub: "livres terminés",    color: "#FB923C"       },
    { icon: Star,       label: "Note moyenne",  value: stats.avg ?? "—",                                sub: "sur 5 étoiles",               color: "#FBBF24"       },
  ];

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-12 pb-4">
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Vos stats</p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Tableau de bord</h1>
      </div>

      <div className="grid grid-cols-2 gap-3 px-4 mb-4">
        {KPI_ITEMS.map(({ icon: Icon, label, value, sub, color }) => (
          <div key={label} className="p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
            <div className="w-7 h-7 rounded-lg flex items-center justify-center mb-3" style={{ background: `${color}18` }}>
              <Icon style={{ width: 15, height: 15, color }} />
            </div>
            <p className="text-xl font-bold" style={{ color: "var(--txt1)" }}>{value}</p>
            <p className="text-xs font-bold mt-0.5" style={{ color }}>{label}</p>
            <p className="text-xs mt-0.5" style={{ color: "var(--txt3)" }}>{sub}</p>
          </div>
        ))}
      </div>

      <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Avancement</h3>
        <div className="flex gap-3">
          {[
            { label: "Lus",      n: stats.lu,       emoji: "✅", bg: "var(--have-bg)", color: "var(--have-t)" },
            { label: "En cours", n: stats.en_cours,  emoji: "📖", bg: "#FEF9C3",        color: "#A16207"       },
            { label: "À lire",   n: stats.a_lire,    emoji: "📌", bg: "var(--accent-l)", color: "var(--accent)" },
          ].map(({ label, n, emoji, bg, color }) => (
            <div key={label} className="flex-1 flex flex-col items-center p-3 rounded-xl" style={{ background: bg }}>
              <span className="text-xl">{emoji}</span>
              <span className="text-xl font-bold mt-1" style={{ color }}>{n}</span>
              <span className="text-xs mt-0.5" style={{ color, opacity: 0.8 }}>{label}</span>
            </div>
          ))}
        </div>
      </div>

      {stats.total > 0 && (
        <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Répartition par type</h3>
          {[
            { label: "📖 Livres", value: stats.livres, color: "var(--accent)" },
            { label: "🎨 BD",     value: stats.bds,    color: "#FB923C"       },
            { label: "⛩️ Manga",  value: stats.mangas, color: "#22C55E"       },
          ].filter(t => t.value > 0).map(({ label, value, color }) => (
            <div key={label} className="mb-3">
              <div className="flex justify-between mb-1.5">
                <span style={{ fontSize: 13, color: "var(--txt2)" }}>{label}</span>
                <span className="font-bold" style={{ fontSize: 13, color }}>{value}</span>
              </div>
              <div className="h-2 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
                <div className="h-full rounded-full" style={{ width: `${(value / stats.total) * 100}%`, background: color }} />
              </div>
            </div>
          ))}
        </div>
      )}

      {stats.topAuthors.length > 0 && (
        <div className="mx-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Auteurs favoris</h3>
          {stats.topAuthors.map(([name, count], i) => (
            <div key={name} className="flex items-center gap-3 py-2">
              <span className="font-bold text-sm w-4 text-center" style={{ color: i === 0 ? "var(--accent)" : "var(--txt3)" }}>{i + 1}</span>
              <span className="flex-1 text-sm" style={{ color: "var(--txt2)" }}>{name}</span>
              <span className="text-xs font-semibold px-2 py-0.5 rounded-full" style={{ background: "var(--accent-l)", color: "var(--accent)" }}>
                {count} livre{count > 1 ? "s" : ""}
              </span>
            </div>
          ))}
        </div>
      )}

      <BottomNav />
    </div>
  );
}
