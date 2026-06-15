"use client";
import BottomNav from "@/components/layout/BottomNav";
import { useTheme } from "@/components/layout/ThemeProvider";
import { Toggle } from "@/components/ui/Toggle";
import { Cover } from "@/components/ui/Cover";
import { SharedLibrary } from "@/types";
import { Home, UserPlus, Bell, Download, LogOut, ChevronRight, Gift, BookOpen } from "lucide-react";

// ─── Demo data (replace with Supabase query) ─────────────────────────────────
const SHARED: SharedLibrary[] = [
  {
    wishlist_id: "wl_demo", collection_name: "Astérix", owner_name: "Amaury",
    shared_at: "2026-06-10T10:00:00Z", missing_count: 7, claimed_count: 1,
    cover_url: "https://covers.openlibrary.org/b/isbn/9782205055375-M.jpg",
  },
];

export default function SettingsPage() {
  const { theme, toggle } = useTheme();

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-12 pb-4">
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>
          Compte
        </p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Réglages</h1>
      </div>

      {/* Profile */}
      <div className="mx-4 mb-4 p-4 rounded-2xl flex items-center gap-3" style={{ background: "var(--accent)" }}>
        <div className="w-14 h-14 rounded-2xl flex items-center justify-center font-bold flex-shrink-0"
          style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>
          G
        </div>
        <div>
          <p className="font-bold text-white" style={{ fontSize: 17 }}>Garance</p>
          <p style={{ color: "rgba(255,255,255,0.65)", fontSize: 13 }}>garancefrr@gmail.com</p>
        </div>
      </div>

      {/* Shared libraries */}
      <SettingGroup icon={Gift} label="Bibliothèques partagées">
        {SHARED.length === 0 ? (
          <div className="px-4 py-6 flex flex-col items-center gap-2">
            <BookOpen className="w-8 h-8" style={{ color: "var(--txt3)", opacity: 0.3 }} />
            <p className="text-center" style={{ fontSize: 14, color: "var(--txt3)" }}>
              Personne n&apos;a encore partagé de wishlist avec toi
            </p>
          </div>
        ) : SHARED.map(lib => (
          <a key={lib.wishlist_id} href={`/wishlist/${lib.wishlist_id}`}
            className="flex items-center gap-3 px-4 py-3.5 active:opacity-70"
            style={{ borderTop: "1px solid var(--border)", textDecoration: "none" }}>
            <Cover src={lib.cover_url} alt={lib.collection_name} width={44} height={60} className="rounded-xl flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="font-semibold" style={{ fontSize: 15, color: "var(--txt1)" }}>
                {lib.collection_name} <span style={{ fontWeight: 400, opacity: 0.5 }}>de {lib.owner_name}</span>
              </p>
              <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>
                {lib.missing_count} souhaité{lib.missing_count > 1 ? "s" : ""}
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
      </SettingGroup>

      {/* My library */}
      <SettingGroup icon={Home} label="Ma bibliothèque">
        <SettingRow icon={Home} label="Folio — Bibliothèque" sub="1 membre · Propriétaire"><ChevronRight className="w-4 h-4" style={{ color: "var(--txt3)" }} /></SettingRow>
        <SettingRow icon={UserPlus} label="Inviter un membre" sub="Partager par lien ou email"><ChevronRight className="w-4 h-4" style={{ color: "var(--txt3)" }} /></SettingRow>
      </SettingGroup>

      {/* Preferences */}
      <SettingGroup icon={Bell} label="Préférences">
        <SettingRow icon={Bell} label="Mode sombre" sub={"Thème de l'interface"}>
          <Toggle checked={theme === "dark"} onChange={() => toggle()} label="Basculer mode sombre" />
        </SettingRow>
        <SettingRow icon={Bell} label="Notifications" sub="Nouvelles wishlists partagées">
          <span style={{ fontSize: 13, color: "var(--txt3)" }}>Activées</span>
        </SettingRow>
        <SettingRow icon={Download} label="Exporter ma bibliothèque" sub="Format CSV ou JSON">
          <ChevronRight className="w-4 h-4" style={{ color: "var(--txt3)" }} />
        </SettingRow>
      </SettingGroup>

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

// ── Internal helpers ──────────────────────────────────────────────────────────

function SettingGroup({ icon: _Icon, label, children }: {
  icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>;
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
      <div className="px-4 py-2.5" style={{ borderBottom: "1px solid var(--border)" }}>
        <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>
          {label}
        </span>
      </div>
      {children}
    </div>
  );
}

function SettingRow({ icon: Icon, label, sub, children }: {
  icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>;
  label: string;
  sub?: string;
  children?: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-3 px-4 py-4" style={{ borderTop: "1px solid var(--border)" }}>
      <Icon className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
      <div className="flex-1">
        <p style={{ fontSize: 15, fontWeight: 500, color: "var(--txt1)" }}>{label}</p>
        {sub && <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{sub}</p>}
      </div>
      {children}
    </div>
  );
}
