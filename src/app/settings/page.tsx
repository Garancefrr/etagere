"use client";
import { useState, useEffect } from "react";
import { useSession, signOut } from "next-auth/react";
import { useLibrary } from "@/hooks/useLibrary";
import BottomNav from "@/components/layout/BottomNav";
import { useTheme } from "@/components/layout/ThemeProvider";
import { Toggle } from "@/components/ui/Toggle";
import { Cover } from "@/components/ui/Cover";
import { SharedWithMe } from "@/lib/db";
import { Moon, LogOut, ChevronRight, Gift, BookOpen, Upload } from "lucide-react";
import Link from "next/link";

export default function SettingsPage() {
  const { data: session }         = useSession();
  const { email }                 = useLibrary();
  const { theme, toggle }         = useTheme();
  const [shared, setShared]       = useState<SharedWithMe[]>([]);

  useEffect(() => {
    if (!email) return;
    fetch(`/api/shared-with-me?email=${encodeURIComponent(email)}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setShared(d) : [])
      .catch(console.error);
  }, [email]);

  const userName = session?.user?.name ?? "Utilisateur";

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-12 pb-4">
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Compte</p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Réglages</h1>
      </div>

      <div className="mx-4 mb-4 p-4 rounded-2xl flex items-center gap-3" style={{ background: "var(--accent)" }}>
        {session?.user?.image
          ? <img src={session.user.image} alt="" className="w-14 h-14 rounded-2xl flex-shrink-0 object-cover" />
          : <div className="w-14 h-14 rounded-2xl flex items-center justify-center font-bold flex-shrink-0" style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>{userName[0]}</div>}
        <div className="min-w-0">
          <p className="font-bold text-white truncate" style={{ fontSize: 17 }}>{userName}</p>
          <p className="truncate" style={{ color: "rgba(255,255,255,0.65)", fontSize: 13 }}>{session?.user?.email}</p>
        </div>
      </div>

      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5 flex items-center gap-2" style={{ borderBottom: "1px solid var(--border)" }}>
          <Gift className="w-4 h-4" style={{ color: "var(--accent)" }} />
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Bibliothèques partagées</span>
        </div>
        {shared.length === 0 ? (
          <div className="px-4 py-6 flex flex-col items-center gap-2">
            <BookOpen className="w-8 h-8" style={{ color: "var(--txt3)", opacity: 0.3 }} />
            <p className="text-center" style={{ fontSize: 14, color: "var(--txt3)" }}>Personne n&apos;a encore partagé de collection avec toi</p>
          </div>
        ) : shared.map(lib => (
          <a key={lib.token} href={`/share/${lib.token}`} className="flex items-center gap-3 px-4 py-3.5 active:opacity-70"
            style={{ borderTop: "1px solid var(--border)", textDecoration: "none" }}>
            <Cover src={lib.cover_url} alt={lib.collection_name} width={44} height={60} className="rounded-xl flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="font-semibold truncate" style={{ fontSize: 15, color: "var(--txt1)" }}>{lib.collection_name} <span style={{ fontWeight: 400, opacity: 0.5 }}>de {lib.owner_name}</span></p>
              <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{lib.owned_volumes.length}{lib.total_volumes ? `/${lib.total_volumes}` : ""} tomes</p>
            </div>
            <ChevronRight className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          </a>
        ))}
      </div>

      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5" style={{ borderBottom: "1px solid var(--border)" }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Préférences</span>
        </div>
        <div className="flex items-center gap-3 px-4 py-4">
          <Moon className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          <div className="flex-1">
            <p style={{ fontSize: 15, fontWeight: 500, color: "var(--txt1)" }}>Mode sombre</p>
            <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{"Thème de l'interface"}</p>
          </div>
          <Toggle checked={theme === "dark"} onChange={() => toggle()} label="Basculer mode sombre" />
        </div>
      </div>

      {/* Import */}
      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5" style={{ borderBottom: "1px solid var(--border)" }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Données</span>
        </div>
        <Link href="/import" className="flex items-center gap-3 px-4 py-4 active:opacity-70">
          <Upload className="w-5 h-5 flex-shrink-0" style={{ color: "var(--accent)" }} />
          <div className="flex-1">
            <p style={{ fontSize: 15, fontWeight: 500, color: "var(--txt1)" }}>Importer depuis Babelio</p>
            <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>Importe ton export CSV Babelio</p>
          </div>
          <ChevronRight className="w-4 h-4" style={{ color: "var(--txt3)" }} />
        </Link>
      </div>

      <button onClick={() => signOut({ callbackUrl: "/login" })}
        className="mx-4 py-4 rounded-2xl flex items-center justify-center gap-2 active:scale-95"
        style={{ width: "calc(100% - 2rem)", background: "var(--miss-bg)", border: "1px solid var(--miss-b)" }}>
        <LogOut className="w-5 h-5" style={{ color: "var(--miss-t)" }} />
        <span style={{ fontSize: 15, fontWeight: 700, color: "var(--miss-t)" }}>Se déconnecter</span>
      </button>

      <p className="text-center mt-4" style={{ fontSize: 12, color: "var(--txt3)", opacity: 0.4 }}>Folio · v1.0.0</p>
      <BottomNav />
    </div>
  );
}
