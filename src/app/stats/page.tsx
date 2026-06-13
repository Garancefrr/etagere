"use client";
import BottomNav from "@/components/layout/BottomNav";
import { BookOpen, TrendingUp, FileText, Star } from "lucide-react";

const STATS = { total: 38, lu: 24, en_cours: 3, a_lire: 11, pages: 8429, annee: 12, moyenne: 4.3 };
const REPARTITION = [
  { label: "📖 Livres", value: 22, total: 38, color: "var(--accent)" },
  { label: "🎨 BD",     value: 11, total: 38, color: "#FB923C" },
  { label: "⛩️ Manga",  value: 5,  total: 38, color: "#22C55E" },
];
const AUTHORS = ["J.R.R. Tolkien", "Albert Camus", "René Goscinny"];
const AUTHOR_COUNTS = [4, 3, 2];

const KPIs = [
  { icon: BookOpen,   label: "Lus au total",  value: STATS.lu,         sub: `sur ${STATS.total} ouvrages`, color: "var(--accent)" },
  { icon: TrendingUp, label: "Cette année",   value: STATS.annee,      sub: "livres terminés",             color: "#22C55E" },
  { icon: FileText,   label: "Pages lues",    value: STATS.pages.toLocaleString("fr"), sub: "toutes éditions", color: "#FB923C" },
  { icon: Star,       label: "Note moyenne",  value: STATS.moyenne,    sub: "sur 5 étoiles",               color: "#FBBF24" },
];

export default function StatsPage() {
  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-10 pb-4">
        <p className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--accent)" }}>Vos stats</p>
        <h1 className="text-2xl font-bold" style={{ color: "var(--txt1)" }}>Tableau de bord</h1>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-3 px-4 mb-4">
        {KPIs.map(({ icon: Icon, label, value, sub, color }) => (
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

      {/* Avancement */}
      <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Avancement</h3>
        <div className="flex gap-3">
          {[
            { label: "Lus",      n: STATS.lu,        emoji: "✅", bg: "var(--have-bg)", color: "var(--have-t)" },
            { label: "En cours", n: STATS.en_cours,  emoji: "📖", bg: "#FEF9C3",        color: "#A16207" },
            { label: "À lire",   n: STATS.a_lire,    emoji: "📌", bg: "var(--accent-l)", color: "var(--accent)" },
          ].map(s => (
            <div key={s.label} className="flex-1 flex flex-col items-center p-3 rounded-xl"
              style={{ background: s.bg }}>
              <span className="text-xl">{s.emoji}</span>
              <span className="text-xl font-bold mt-1" style={{ color: s.color }}>{s.n}</span>
              <span className="text-xs mt-0.5" style={{ color: s.color, opacity: 0.8 }}>{s.label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Répartition */}
      <div className="mx-4 mb-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Répartition par type</h3>
        <div className="flex flex-col gap-3">
          {REPARTITION.map(({ label, value, total, color }) => (
            <div key={label}>
              <div className="flex justify-between mb-1.5">
                <span className="text-sm" style={{ color: "var(--txt2)" }}>{label}</span>
                <span className="text-sm font-bold" style={{ color }}>{value}</span>
              </div>
              <div className="h-2 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
                <div className="h-full rounded-full" style={{ width: `${(value / total) * 100}%`, background: color }} />
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Top auteurs */}
      <div className="mx-4 p-4 rounded-2xl" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <h3 className="font-bold text-sm mb-3" style={{ color: "var(--txt1)" }}>Auteurs favoris</h3>
        {AUTHORS.map((a, i) => (
          <div key={a} className="flex items-center gap-3 py-2">
            <span className="font-bold text-sm w-4" style={{ color: i === 0 ? "var(--accent)" : "var(--txt3)" }}>{i + 1}</span>
            <span className="flex-1 text-sm" style={{ color: "var(--txt2)" }}>{a}</span>
            <span className="text-xs font-semibold px-2 py-0.5 rounded-full"
              style={{ background: "var(--accent-l)", color: "var(--accent)" }}>
              {AUTHOR_COUNTS[i]} livre{AUTHOR_COUNTS[i] > 1 ? "s" : ""}
            </span>
          </div>
        ))}
      </div>

      <BottomNav />
    </div>
  );
}
