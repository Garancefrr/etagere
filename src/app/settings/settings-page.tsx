"use client";
import BottomNav from "@/components/layout/BottomNav";
import { useTheme } from "@/components/layout/ThemeProvider";
import { Home, UserPlus, Moon, Bell, Download, LogOut, ChevronRight, Gift, BookOpen, Check } from "lucide-react";
import { SharedLibrary } from "@/types";

const SHARED_LIBRARIES: SharedLibrary[] = [
  {
    wishlist_id: "wl_demo",
    collection_name: "Astérix",
    owner_name: "Amaury",
    shared_at: "2026-06-10T10:00:00Z",
    missing_count: 7,
    claimed_count: 1,
    cover_url: "https://covers.openlibrary.org/b/isbn/9782205055375-M.jpg",
  },
];

export default function SettingsPage() {
  const { theme, toggle } = useTheme();

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      {/* Header */}
      <div className="px-4 pt-12 pb-4">
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Compte</p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Réglages</h1>
      </div>

      {/* Profile card */}
      <div className="mx-4 mb-4 p-4 rounded-2xl flex items-center gap-3"
        style={{ background: "var(--accent)" }}>
        <div className="w-14 h-14 rounded-2xl flex items-center justify-center font-bold flex-shrink-0"
          style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>G</div>
        <div>
          <p className="font-bold text-white" style={{ fontSize: 17 }}>Garance</p>
          <p style={{ color: "rgba(255,255,255,0.65)", fontSize: 13, marginTop: 2 }}>garancefrr@gmail.com</p>
        </div>
      </div>

      {/* Shared libraries — wishlists received */}
      <div className="mx-4 mb-4 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-3 flex items-center gap-2" style={{ borderBottom: "1px solid var(--border)" }}>
          <Gift className="w-4 h-4" style={{ color: "var(--accent)" }} />
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>
            Bibliothèques partagées
          </span>
        </div>

        {SHARED_LIBRARIES.length === 0 ? (
          <div className="px-4 py-6 flex flex-col items-center gap-2">
            <BookOpen className="w-8 h-8" style={{ color: "var(--txt3)", opacity: 0.3 }} />
            <p style={{ fontSize: 14, color: "var(--txt3)", textAlign: "center" }}>
              Personne n&apos;a encore partagé de wishlist avec toi
            </p>
          </div>
        ) : SHARED_LIBRARIES.map(lib => (
          <a key={lib.wishlist_id} href={`/wishlist/${lib.wishlist_id}`}
            className="flex items-center gap-3 px-4 py-3.5 active:opacity-70"
            style={{ borderTop: "1px solid var(--border)", textDecoration: "none" }}>
            {/* Cover */}
            <div className="rounded-xl overflow-hidden flex-shrink-0 flex items-center justify-center"
              style={{ width: 44, height: 60, background: "var(--placeholder)" }}>
              {lib.cover_url
                ? <img src={lib.cover_url} alt="" className="w-full h-full object-cover" />
                : <BookOpen className="w-5 h-5" style={{ color: "var(--txt3)" }} />}
            </div>
            {/* Info */}
            <div className="flex-1 min-w-0">
              <p className="font-semibold" style={{ fontSize: 15, color: "var(--txt1)" }}>
                {lib.collection_name} <span style={{ fontWeight: 400, opacity: 0.5 }}>de {lib.owner_name}</span>
              </p>
              <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>
                {lib.missing_count} livre{lib.missing_count > 1 ? "s" : ""} souhaité{lib.missing_count > 1 ? "s" : ""}
                {lib.claimed_count > 0 && (
                  <span style={{ color: "var(--have-t)", marginLeft: 6 }}>
                    · {lib.claimed_count} réservé{lib.claimed_count > 1 ? "s" : ""}
                  </span>
                )}
              </p>
            </div>
            <ChevronRight className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          </a>
        ))}
      </div>

      {/* My library */}
      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5 flex items-center gap-2" style={{ borderBottom: "1px solid var(--border)" }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Ma bibliothèque</span>
        </div>
        {[
          { icon: Home,     label: "Folio — Bibliothèque", sub: "1 membre · Propriétaire" },
          { icon: UserPlus, label: "Inviter un membre",    sub: "Partager par lien ou email" },
        ].map(({ icon: Icon, label, sub }) => (
          <div key={label} className="flex items-center gap-3 px-4 py-4" style={{ borderTop: "1px solid var(--border)" }}>
            <Icon className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
            <div className="flex-1">
              <p style={{ fontSize: 15, fontWeight: 500, color: "var(--txt1)" }}>{label}</p>
              <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{sub}</p>
            </div>
            <ChevronRight className="w-4 h-4" style={{ color: "var(--txt3)" }} />
          </div>
        ))}
      </div>

      {/* Preferences */}
      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5" style={{ borderBottom: "1px solid var(--border)" }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Préférences</span>
        </div>

        {/* Dark mode */}
        <div className="flex items-center gap-3 px-4 py-4" style={{ borderTop: "1px solid var(--border)" }}>
          <Moon className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          <div className="flex-1">
            <p style={{ fontSize: 15, fontWeight: 500, color: "var(--txt1)" }}>Mode sombre</p>
            <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{"Thème de l'interface"}</p>
          </div>
          <button onClick={toggle} aria-label="Basculer thème"
            style={{
              width: 48, height: 28, borderRadius: 14,
              background: theme === "dark" ? "var(--accent)" : "var(--border)",
              border: "none", cursor: "pointer", position: "relative", transition: "background 0.2s",
              flexShrink: 0,
            }}>
            <div style={{
              position: "absolute", top: 3, left: 3, width: 22, height: 22,
              borderRadius: 11, background: "#fff",
              transition: "transform 0.2s",
              transform: theme === "dark" ? "translateX(20px)" : "translateX(0)",
            }} />
          </button>
        </div>

        <div className="flex items-center gap-3 px-4 py-4" style={{ borderTop: "1px solid var(--border)" }}>
          <Bell className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          <div className="flex-1">
            <p style={{ fontSize: 15, fontWeight: 500, color: "var(--txt1)" }}>Notifications</p>
            <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>Nouvelles wishlists partagées</p>
          </div>
          <span style={{ fontSize: 13, color: "var(--txt3)" }}>Activées</span>
        </div>

        <div className="flex items-center gap-3 px-4 py-4" style={{ borderTop: "1px solid var(--border)" }}>
          <Download className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          <div className="flex-1">
            <p style={{ fontSize: 15, fontWeight: 500, color: "var(--txt1)" }}>Exporter ma bibliothèque</p>
            <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>Format CSV ou JSON</p>
          </div>
          <ChevronRight className="w-4 h-4" style={{ color: "var(--txt3)" }} />
        </div>
      </div>

      {/* Sign out */}
      <button className="mx-4 py-4 rounded-2xl flex items-center justify-center gap-2 active:scale-95"
        style={{ width: "calc(100% - 2rem)", background: "var(--miss-bg)", border: "1px solid var(--miss-b)" }}>
        <LogOut className="w-5 h-5" style={{ color: "var(--miss-t)" }} />
        <span style={{ fontSize: 15, fontWeight: 700, color: "var(--miss-t)" }}>Se déconnecter</span>
      </button>

      <p className="text-center mt-4" style={{ fontSize: 12, color: "var(--txt3)", opacity: 0.4 }}>Folio · v1.0.0</p>

      <BottomNav />
    </div>
  );
}
