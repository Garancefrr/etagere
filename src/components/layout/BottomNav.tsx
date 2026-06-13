"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { BookOpen, Layers, ScanLine, BarChart2, User } from "lucide-react";

const items = [
  { href: "/library", icon: BookOpen, label: "Biblio" },
  { href: "/collections", icon: Layers, label: "Collections" },
  { href: "/scan", icon: ScanLine, label: "Scanner", primary: true },
  { href: "/stats", icon: BarChart2, label: "Stats" },
  { href: "/settings", icon: User, label: "Compte" },
];

export default function BottomNav() {
  const pathname = usePathname();
  return (
    <nav className="fixed bottom-0 left-0 right-0 pb-safe z-40"
      style={{ background: "var(--nav-bg)", borderTop: "1px solid var(--border)", boxShadow: "0 -4px 20px rgba(59,91,255,0.06)" }}>
      <div className="flex items-center justify-around h-16 px-2">
        {items.map(({ href, icon: Icon, label, primary }) => {
          const active = pathname === href;
          if (primary) {
            return (
              <Link key={href} href={href} className="flex flex-col items-center gap-1 -mt-5">
                <div className="w-12 h-12 rounded-2xl flex items-center justify-center transition-transform active:scale-90"
                  style={{ background: "var(--accent)", boxShadow: "0 0 0 3px var(--bg), 0 4px 16px rgba(59,91,255,0.4)" }}>
                  <Icon className="w-5 h-5 text-white" />
                </div>
                <span className="text-xs font-medium" style={{ color: "var(--txt2)", fontSize: 10 }}>{label}</span>
              </Link>
            );
          }
          return (
            <Link key={href} href={href}
              className="flex flex-col items-center gap-1 px-3 py-2 rounded-xl transition-all">
              <Icon className="w-5 h-5 transition-all"
                style={{ color: active ? "var(--accent)" : "var(--txt3)", strokeWidth: active ? 2.5 : 1.5 }} />
              <span className="font-medium" style={{ fontSize: 10, color: active ? "var(--accent)" : "var(--txt3)" }}>
                {label}
              </span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
