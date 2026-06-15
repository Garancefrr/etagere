"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { BookOpen, Layers, ScanLine, BarChart2, User } from "lucide-react";

const NAV_ITEMS = [
  { href: "/library",     icon: BookOpen,  label: "Biblio" },
  { href: "/collections", icon: Layers,    label: "Collections" },
  { href: "/scan",        icon: ScanLine,  label: "Scanner", primary: true },
  { href: "/stats",       icon: BarChart2, label: "Stats" },
  { href: "/settings",    icon: User,      label: "Compte" },
];

export default function BottomNav() {
  const pathname = usePathname();

  return (
    <nav
      className="fixed bottom-0 left-0 right-0 z-40"
      style={{
        background: "var(--nav-bg)",
        borderTop: "1px solid var(--border)",
        paddingBottom: "env(safe-area-inset-bottom, 0px)",
      }}
    >
      <div className="flex items-center justify-around" style={{ height: 68 }}>
        {NAV_ITEMS.map(({ href, icon: Icon, label, primary }) => {
          const active = pathname === href;

          if (primary) {
            return (
              <Link key={href} href={href} className="flex flex-col items-center gap-1" style={{ marginTop: -22 }}>
                <div style={{
                  width: 54, height: 54, borderRadius: 17,
                  background: "var(--accent)",
                  display: "flex", alignItems: "center", justifyContent: "center",
                  boxShadow: "0 0 0 4px var(--bg), 0 4px 18px rgba(59,91,255,0.4)",
                }}>
                  <Icon style={{ width: 24, height: 24, color: "#fff" }} />
                </div>
                <span style={{ fontSize: 11, fontWeight: 600, color: "var(--txt2)" }}>{label}</span>
              </Link>
            );
          }

          return (
            <Link
              key={href}
              href={href}
              className="flex flex-col items-center gap-1"
              style={{ padding: "8px 12px" }}
            >
              <Icon style={{
                width: 24, height: 24,
                color: active ? "var(--accent)" : "var(--txt3)",
                strokeWidth: active ? 2.5 : 1.5,
              }} />
              <span style={{ fontSize: 11, fontWeight: 600, color: active ? "var(--accent)" : "var(--txt3)" }}>
                {label}
              </span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
