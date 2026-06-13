"use client";
import BottomNav from "@/components/layout/BottomNav";
import { useTheme } from "@/components/layout/ThemeProvider";
import { Home, UserPlus, Moon, Bell, Download, LogOut, ChevronRight } from "lucide-react";

export default function SettingsPage() {
  const { theme, toggle } = useTheme();

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-10 pb-4">
        <p className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--accent)" }}>Compte</p>
        <h1 className="text-2xl font-bold" style={{ color: "var(--txt1)" }}>Réglages</h1>
      </div>

      {/* Profile card */}
      <div className="mx-4 mb-4 p-4 rounded-2xl flex items-center gap-3"
        style={{ background: "var(--accent)" }}>
        <div className="w-12 h-12 rounded-2xl flex items-center justify-center font-bold text-lg flex-shrink-0"
          style={{ background: "rgba(255,255,255,0.2)", color: "#fff" }}>G</div>
        <div>
          <p className="font-bold text-white">Garance</p>
          <p className="text-xs" style={{ color: "rgba(255,255,255,0.65)" }}>garancefrr@gmail.com</p>
        </div>
      </div>

      {/* Library */}
      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5 flex items-center gap-2" style={{ borderBottom: "1px solid var(--border)" }}>
          <span className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--accent)" }}>Bibliothèque</span>
        </div>
        {[
          { icon: Home,    label: "Notre Bibliothèque",  sub: "2 membres · Propriétaire", action: true },
          { icon: UserPlus, label: "Inviter un membre",  sub: "Partager par lien ou email", action: true },
        ].map(({ icon: Icon, label, sub, action }) => (
          <div key={label} className="flex items-center gap-3 px-4 py-3.5" style={{ borderTop: "1px solid var(--border)" }}>
            <Icon className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
            <div className="flex-1">
              <p className="text-sm font-medium" style={{ color: "var(--txt1)" }}>{label}</p>
              {sub && <p className="text-xs mt-0.5" style={{ color: "var(--txt2)" }}>{sub}</p>}
            </div>
            {action && <ChevronRight className="w-4 h-4" style={{ color: "var(--txt3)" }} />}
          </div>
        ))}
      </div>

      {/* Preferences */}
      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5" style={{ borderBottom: "1px solid var(--border)" }}>
          <span className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--accent)" }}>Préférences</span>
        </div>
        {/* Dark mode row with real toggle */}
        <div className="flex items-center gap-3 px-4 py-3.5" style={{ borderTop: "1px solid var(--border)" }}>
          <Moon className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          <div className="flex-1">
            <p className="text-sm font-medium" style={{ color: "var(--txt1)" }}>Mode sombre</p>
            <p className="text-xs mt-0.5" style={{ color: "var(--txt2)" }}>{"Thème de l'interface"}</p>
          </div>
          <button onClick={toggle}
            className="relative flex-shrink-0"
            style={{ width: 44, height: 24, borderRadius: 12, background: theme === "dark" ? "var(--accent)" : "var(--border)", border: "none", cursor: "pointer", transition: "background 0.2s" }}
            aria-label="Basculer mode sombre">
            <div style={{
              position: "absolute", top: 2, left: 2, width: 20, height: 20, borderRadius: 10,
              background: "#fff", transition: "transform 0.2s",
              transform: theme === "dark" ? "translateX(20px)" : "translateX(0)",
            }} />
          </button>
        </div>
        {[
          { icon: Bell,     label: "Notifications",          sub: "Nouveautés des collections", right: "Activées" },
          { icon: Download, label: "Exporter ma bibliothèque", sub: "Format CSV ou JSON", action: true },
        ].map(({ icon: Icon, label, sub, right, action }) => (
          <div key={label} className="flex items-center gap-3 px-4 py-3.5" style={{ borderTop: "1px solid var(--border)" }}>
            <Icon className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
            <div className="flex-1">
              <p className="text-sm font-medium" style={{ color: "var(--txt1)" }}>{label}</p>
              {sub && <p className="text-xs mt-0.5" style={{ color: "var(--txt2)" }}>{sub}</p>}
            </div>
            {right && <span className="text-xs" style={{ color: "var(--txt3)" }}>{right}</span>}
            {action && <ChevronRight className="w-4 h-4" style={{ color: "var(--txt3)" }} />}
          </div>
        ))}
      </div>

      {/* Sign out */}
      <button className="mx-4 w-[calc(100%-2rem)] py-3.5 rounded-2xl flex items-center justify-center gap-2"
        style={{ background: "var(--miss-bg)", border: "1px solid var(--miss-b)" }}>
        <LogOut className="w-4 h-4" style={{ color: "var(--miss-t)" }} />
        <span className="font-bold text-sm" style={{ color: "var(--miss-t)" }}>Se déconnecter</span>
      </button>

      <p className="text-center text-xs mt-4 pb-4" style={{ color: "var(--txt3)", opacity: 0.5 }}>
        Étagère · v1.0.0
      </p>

      <BottomNav />
    </div>
  );
}
