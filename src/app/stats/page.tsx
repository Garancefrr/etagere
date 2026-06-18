"use client";
import { useMemo } from "react";
import { useData } from "@/contexts/DataContext";
import BottomNav from "@/components/layout/BottomNav";
import { BookOpen, TrendingUp, FileText, Star } from "lucide-react";

const p = (n: number, word: string) => `${n} ${word}${n > 1 ? "s" : ""}`;
const monthName = (m: number) => ["Jan","Fév","Mar","Avr","Mai","Juin","Juil","Aoû","Sep","Oct","Nov","Déc"][m];

export default function StatsPage() {
  const { books, loading } = useData();
  const thisYear = new Date().getFullYear();

  const stats = useMemo(() => {
    const lu      = books.filter(b => b.status === "lu");
    const pages   = lu.reduce((s, b) => s + (b.page_count ?? 0), 0);
    const ratings = lu.filter(b => b.rating).map(b => b.rating!);
    const avg     = ratings.length ? (ratings.reduce((a, b) => a + b, 0) / ratings.length).toFixed(1) : null;
    const finishedThisYear = lu.filter(b => {
      const d = b.finished_at ?? b.updated_at;
      return d && new Date(d).getFullYear() === thisYear;
    });
    const addedThisYear = books.filter(b => new Date(b.added_at).getFullYear() === thisYear);
    const byMonth: number[] = Array(12).fill(0);
    lu.forEach(b => {
      const d = b.finished_at ?? b.updated_at;
      if (d && new Date(d).getFullYear() === thisYear) byMonth[new Date(d).getMonth()]++;
    });
    const bestMonthIdx = byMonth.indexOf(Math.max(...byMonth));
    const bestMonth = byMonth[bestMonthIdx] > 0 ? { name: monthName(bestMonthIdx), count: byMonth[bestMonthIdx] } : null;
    const livres = books.filter(b => b.book_type === "livre").length;
    const bds    = books.filter(b => b.book_type === "bd").length;
    const mangas = books.filter(b => b.book_type === "manga").length;
    const typeMax = Math.max(livres, bds, mangas);
    const favType = typeMax === 0 ? null : livres === typeMax ? "📖 Livres" : bds === typeMax ? "🎨 BD" : "⛩️ Manga";
    const authorCount: Record<string, number> = {};
    books.forEach(b => b.authors.forEach(a => { authorCount[a] = (authorCount[a] ?? 0) + 1; }));
    const topAuthors = Object.entries(authorCount).sort((a, b) => b[1] - a[1]).slice(0, 5);
    const colCount: Record<string, number> = {};
    books.filter(b => b.series_name).forEach(b => { colCount[b.series_name!] = (colCount[b.series_name!] ?? 0) + 1; });
    const topCollection = Object.entries(colCount).sort((a, b) => b[1] - a[1])[0] ?? null;
    const monthsElapsed = new Date().getMonth() + 1;
    const pace = finishedThisYear.length > 0 ? (finishedThisYear.length / monthsElapsed).toFixed(1) : null;
    return {
      total: books.length, lu: lu.length,
      en_cours: books.filter(b => b.status === "en_cours").length,
      a_lire: books.filter(b => b.status === "a_lire").length,
      pages, avg, livres, bds, mangas, favType, topAuthors, topCollection,
      finishedThisYear: finishedThisYear.length, addedThisYear: addedThisYear.length,
      byMonth, bestMonth, pace,
    };
  }, [books, thisYear]);

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center" style={{ background: "var(--bg)" }}>
      <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
      <BottomNav />
    </div>
  );

  if (stats.total === 0) return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4 pb-24" style={{ background: "var(--bg)" }}>
      <BookOpen className="w-12 h-12" style={{ color: "var(--txt3)", opacity: 0.3 }} />
      <p className="font-bold" style={{ fontSize: 17, color: "var(--txt1)" }}>Pas encore de stats</p>
      <p className="text-center px-8" style={{ fontSize: 14, color: "var(--txt3)" }}>Scanne tes premiers livres !</p>
      <BottomNav />
    </div>
  );

  const maxMonth = Math.max(...stats.byMonth, 1);

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-3 pt-10 pb-3">
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Statistiques</p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Tableau de bord</h1>
      </div>

      <div className="grid grid-cols-2 gap-3 px-3 mb-4">
        {[
          { icon: BookOpen,   label: "Lus au total",         value: stats.lu,                                          sub: `sur ${stats.total}`,               color: "var(--accent)" },
          { icon: TrendingUp, label: `Lus en ${thisYear}`,   value: stats.finishedThisYear,                            sub: `${stats.addedThisYear} ajoutés`,   color: "#22C55E" },
          { icon: FileText,   label: "Pages lues",           value: stats.pages > 0 ? stats.pages.toLocaleString("fr") : "—", sub: "au total",                  color: "#FB923C" },
          { icon: Star,       label: "Note moyenne",         value: stats.avg ?? "—",                                  sub: "sur 5",                            color: "#FBBF24" },
        ].map(({ icon: Icon, label, value, sub, color }) => (
          <div key={label} className="p-3 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
            <div className="w-6 h-6 rounded-lg flex items-center justify-center mb-2" style={{ background: `${color}18` }}>
              <Icon style={{ width: 13, height: 13, color }} />
            </div>
            <p className="text-xl font-bold" style={{ color: "var(--txt1)" }}>{value}</p>
            <p className="text-xs font-bold mt-0.5" style={{ color }}>{label}</p>
            <p className="text-xs" style={{ color: "var(--txt3)" }}>{sub}</p>
          </div>
        ))}
      </div>

      {stats.finishedThisYear > 0 && (
        <div className="mx-3 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <div className="flex items-center justify-between mb-3">
            <h3 className="font-bold text-sm" style={{ color: "var(--txt1)" }}>Lectures {thisYear}</h3>
            {stats.bestMonth && (
              <span className="text-xs px-2 py-1 rounded-full font-semibold" style={{ background: "var(--accent-l)", color: "var(--accent)" }}>
                {stats.bestMonth.name} : {p(stats.bestMonth.count, "livre")}
              </span>
            )}
          </div>
          <div className="flex items-end gap-1.5" style={{ height: 80 }}>
            {stats.byMonth.map((count, i) => (
              <div key={i} className="flex-1 flex flex-col items-center gap-1">
                <div className="w-full rounded-t-md"
                  style={{ height: count > 0 ? Math.max(6, (count / maxMonth) * 64) : 4,
                    background: count > 0 ? "var(--accent)" : "var(--border)",
                    opacity: i > new Date().getMonth() ? 0.3 : 1 }} />
                <span style={{ fontSize: 8, color: "var(--txt3)" }}>{monthName(i)}</span>
              </div>
            ))}
          </div>
          {stats.pace && (
            <p className="text-center mt-3" style={{ fontSize: 12, color: "var(--txt3)" }}>
              Rythme : <span style={{ color: "var(--accent)", fontWeight: 700 }}>{stats.pace}</span> livre/mois
            </p>
          )}
        </div>
      )}

      <div className="mx-3 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Avancement</h3>
        <div className="flex gap-3">
          {[
            { label: "Lus",      n: stats.lu,       emoji: "✅", bg: "var(--have-bg)", color: "var(--have-t)" },
            { label: "En cours", n: stats.en_cours, emoji: "📖", bg: "#FEF9C3",        color: "#A16207" },
            { label: "À lire",   n: stats.a_lire,   emoji: "📌", bg: "var(--accent-l)", color: "var(--accent)" },
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
        <div className="mx-3 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <div className="flex items-center justify-between mb-3">
            <h3 className="font-bold text-sm" style={{ color: "var(--txt1)" }}>Répartition</h3>
            {stats.favType && <span className="text-xs font-semibold" style={{ color: "var(--accent)" }}>Favori : {stats.favType}</span>}
          </div>
          {[
            { label: "📖 Livres", value: stats.livres, color: "var(--accent)" },
            { label: "🎨 BD",     value: stats.bds,    color: "#FB923C" },
            { label: "⛩️ Manga",  value: stats.mangas, color: "#22C55E" },
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

      {stats.topCollection && (
        <div className="mx-3 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <h3 className="font-bold text-sm mb-2" style={{ color: "var(--txt1)" }}>📚 Collection favorite</h3>
          <div className="flex items-center justify-between">
            <p style={{ fontSize: 15, fontWeight: 600, color: "var(--txt1)" }}>{stats.topCollection[0]}</p>
            <span className="px-2 py-1 rounded-full text-xs font-bold" style={{ background: "var(--accent-l)", color: "var(--accent)" }}>
              {p(stats.topCollection[1], "tome")}
            </span>
          </div>
        </div>
      )}

      {stats.topAuthors.length > 0 && (
        <div className="mx-3 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
          <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>✍️ Auteurs favoris</h3>
          {stats.topAuthors.map(([name, count], i) => (
            <div key={name} className="flex items-center gap-3 py-2">
              <span className="font-bold text-sm w-5 text-center flex-shrink-0" style={{ color: i === 0 ? "#FBBF24" : "var(--txt3)" }}>
                {i === 0 ? "🥇" : i === 1 ? "🥈" : i === 2 ? "🥉" : `${i + 1}`}
              </span>
              <span className="flex-1 text-sm truncate" style={{ color: "var(--txt2)" }}>{name}</span>
              <span className="text-xs font-semibold px-2 py-0.5 rounded-full flex-shrink-0"
                style={{ background: "var(--accent-l)", color: "var(--accent)" }}>
                {p(count, "livre")}
              </span>
            </div>
          ))}
        </div>
      )}

      <BottomNav />
    </div>
  );
}
