#!/bin/bash
set -e
echo "🔧 Fix scan + réglages..."
cd "$(git rev-parse --show-toplevel)"
cat > "src/app/scan/page.tsx" << 'FILEOF'
"use client";
import { useState, useCallback, useEffect } from "react";
import { useSession } from "next-auth/react";
import { ScanResult, ReadStatus, BookType } from "@/types";
import BottomNav from "@/components/layout/BottomNav";
import Scanner from "@/components/scanner/Scanner";
import { ToastStack } from "@/components/ui/Toast";
import { useToast } from "@/hooks/useToast";
import { useFirstUse } from "@/hooks/useFirstUse";
import { ScanLine, Zap, Settings2 } from "lucide-react";

const MODES = [
  { key: false, icon: Settings2, label: "Mode classique", sub: "Confirmation avant ajout" },
  { key: true,  icon: Zap,       label: "Mode rapide",    sub: "Ajout instantané en série" },
] as const;

export default function ScanPage() {
  const { data: session }               = useSession();
  const [scanning,   setScanning]       = useState(false);
  const [rapidMode,  setRapidMode]      = useState(false);
  const [libraryId,  setLibraryId]      = useState<string | null>(null);
  const [libLoading, setLibLoading]     = useState(true);
  const isFirstUse                      = useFirstUse("folio_scan_seen");
  const { toasts, push, dismiss }       = useToast();

  useEffect(() => {
    if (!session?.user?.id) return;
    fetch(`/api/library?user_id=${session.user.id}`)
      .then(r => r.json())
      .then(d => { if (d.id) setLibraryId(d.id); })
      .catch(() => {})
      .finally(() => setLibLoading(false));
  }, [session]);

  const handleSuccess = useCallback((result: ScanResult) => {
    if (rapidMode) {
      push(result.book.title, result.isNewCollection
        ? `Collection « ${result.collection?.name} » créée`
        : result.isNewVolume ? `Ajouté à ${result.collection?.name}` : undefined);
    } else {
      setScanning(false);
      push("Ajouté !", result.book.title);
    }
  }, [rapidMode, push]);

  const handleOpen = () => {
    if (libraryId) setScanning(true);
  };

  if (isFirstUse === null) return null;

  const ready = !!libraryId && !libLoading;

  return (
    <>
      <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>
        <div className="px-4 pt-12 pb-4">
          <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Ajouter</p>
          <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Scanner</h1>
        </div>

        {/* Mode toggle */}
        <div className="mx-4 mb-6 flex p-1 rounded-2xl" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          {MODES.map(({ key, icon: Icon, label, sub }) => (
            <button key={String(key)} onClick={() => setRapidMode(key)}
              className="flex-1 flex items-center gap-3 px-3 py-3 rounded-xl transition-all"
              style={{ background: rapidMode === key ? "var(--accent)" : "transparent" }}>
              <Icon className="w-5 h-5 flex-shrink-0" style={{ color: rapidMode === key ? "#fff" : "var(--txt3)" }} />
              <div className="text-left">
                <p className="font-bold" style={{ fontSize: 13, color: rapidMode === key ? "#fff" : "var(--txt1)" }}>{label}</p>
                <p style={{ fontSize: 11, color: rapidMode === key ? "rgba(255,255,255,0.7)" : "var(--txt3)" }}>{sub}</p>
              </div>
            </button>
          ))}
        </div>

        {isFirstUse
          ? <FirstUseInstructions onStart={handleOpen} ready={ready} />
          : <ScanButton rapidMode={rapidMode} onStart={handleOpen} ready={ready} />
        }
      </div>

      {scanning && libraryId && (
        <Scanner
          rapidMode={rapidMode}
          libraryId={libraryId}
          userId={session?.user?.id ?? ""}
          onSuccess={handleSuccess}
          onClose={() => setScanning(false)}
        />
      )}

      <ToastStack toasts={toasts} onDismiss={dismiss} />
      <BottomNav />
    </>
  );
}

function ScanButton({ rapidMode, onStart, ready }: { rapidMode: boolean; onStart: () => void; ready: boolean }) {
  return (
    <div className="flex flex-col items-center gap-4 px-5">
      <button
        onClick={onStart}
        disabled={!ready}
        className="w-full py-5 rounded-3xl flex items-center justify-center gap-3 active:scale-95 transition-all"
        style={{
          background: ready ? "var(--accent)" : "var(--surface)",
          boxShadow: ready ? "0 8px 32px rgba(59,91,255,0.35)" : "none",
          opacity: ready ? 1 : 0.6,
          cursor: ready ? "pointer" : "default",
        }}>
        {ready
          ? <ScanLine className="w-7 h-7 text-white" />
          : <div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "#fff", borderTopColor: "transparent" }} />}
        <span className="font-bold text-white" style={{ fontSize: 17 }}>
          {!ready ? "Chargement…" : rapidMode ? "Lancer le mode rapide" : "Ouvrir le scanner"}
        </span>
      </button>
      {ready && (
        <p className="text-center" style={{ fontSize: 13, color: "var(--txt3)" }}>
          {rapidMode ? "Chaque scan est ajouté immédiatement" : "ISBN détecté automatiquement"}
        </p>
      )}
    </div>
  );
}

function FirstUseInstructions({ onStart, ready }: { onStart: () => void; ready: boolean }) {
  const STEPS = [
    "Pointez la caméra vers le code-barres",
    "La détection est automatique",
    "Les BD créent leur collection automatiquement",
  ];
  return (
    <div className="flex flex-col items-center gap-6 px-5">
      <button
        onClick={onStart}
        disabled={!ready}
        className="w-32 h-32 rounded-3xl flex flex-col items-center justify-center gap-2 active:scale-95 transition-all"
        style={{
          background: ready ? "var(--accent)" : "var(--surface)",
          boxShadow: ready ? "0 8px 32px rgba(59,91,255,0.35)" : "none",
          opacity: ready ? 1 : 0.6,
          cursor: ready ? "pointer" : "default",
        }}>
        {ready
          ? <ScanLine className="w-12 h-12 text-white" />
          : <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />}
        <span className="font-bold text-white text-sm">{ready ? "Scanner" : "..."}</span>
      </button>

      <div className="text-center">
        <p className="font-bold" style={{ fontSize: 17, color: "var(--txt1)" }}>Scannez le code-barres</p>
        <p style={{ fontSize: 14, color: "var(--txt3)", marginTop: 4 }}>ISBN au dos du livre ou de la BD</p>
      </div>

      <div className="w-full space-y-2">
        {STEPS.map((text, i) => (
          <div key={i} className="flex items-center gap-3 p-4 rounded-2xl"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <span className="w-7 h-7 rounded-full flex items-center justify-center font-bold text-white flex-shrink-0"
              style={{ background: "var(--accent)", fontSize: 13 }}>{i + 1}</span>
            <span style={{ fontSize: 14, color: "var(--txt2)" }}>{text}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
FILEOF
cat > "src/app/settings/page.tsx" << 'FILEOF'
"use client";
import { useState, useEffect } from "react";
import { useSession, signOut } from "next-auth/react";
import BottomNav from "@/components/layout/BottomNav";
import { useTheme } from "@/components/layout/ThemeProvider";
import { Toggle } from "@/components/ui/Toggle";
import { Cover } from "@/components/ui/Cover";
import { SharedWithMe } from "@/lib/db";
import { Moon, LogOut, ChevronRight, Gift, BookOpen } from "lucide-react";

export default function SettingsPage() {
  const { data: session } = useSession();
  const { theme, toggle } = useTheme();
  const [shared, setShared] = useState<SharedWithMe[]>([]);

  useEffect(() => {
    if (!session?.user?.id) return;
    fetch(`/api/shared-with-me?viewer_id=${session.user.id}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setShared(d) : [])
      .catch(() => {});
  }, [session]);

  const userName = session?.user?.name ?? "Utilisateur";

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-12 pb-4">
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Compte</p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Réglages</h1>
      </div>

      {/* Profile */}
      <div className="mx-4 mb-4 p-4 rounded-2xl flex items-center gap-3" style={{ background: "var(--accent)" }}>
        {session?.user?.image
          ? <img src={session.user.image} alt="" className="w-14 h-14 rounded-2xl flex-shrink-0 object-cover" />
          : <div className="w-14 h-14 rounded-2xl flex items-center justify-center font-bold flex-shrink-0"
              style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>
              {userName[0]}
            </div>}
        <div className="min-w-0">
          <p className="font-bold text-white truncate" style={{ fontSize: 17 }}>{userName}</p>
          <p className="truncate" style={{ color: "rgba(255,255,255,0.65)", fontSize: 13 }}>{session?.user?.email}</p>
        </div>
      </div>

      {/* Bibliothèques partagées */}
      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5 flex items-center gap-2" style={{ borderBottom: "1px solid var(--border)" }}>
          <Gift className="w-4 h-4" style={{ color: "var(--accent)" }} />
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>
            Bibliothèques partagées
          </span>
        </div>
        {shared.length === 0 ? (
          <div className="px-4 py-6 flex flex-col items-center gap-2">
            <BookOpen className="w-8 h-8" style={{ color: "var(--txt3)", opacity: 0.3 }} />
            <p className="text-center" style={{ fontSize: 14, color: "var(--txt3)" }}>
              Personne n&apos;a encore partagé de collection avec toi
            </p>
          </div>
        ) : shared.map(lib => (
          <a key={lib.token} href={`/share/${lib.token}`}
            className="flex items-center gap-3 px-4 py-3.5 active:opacity-70"
            style={{ borderTop: "1px solid var(--border)", textDecoration: "none" }}>
            <Cover src={lib.cover_url} alt={lib.collection_name} width={44} height={60} className="rounded-xl flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="font-semibold truncate" style={{ fontSize: 15, color: "var(--txt1)" }}>
                {lib.collection_name}{" "}
                <span style={{ fontWeight: 400, opacity: 0.5 }}>de {lib.owner_name}</span>
              </p>
              <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>
                {lib.owned_volumes.length}{lib.total_volumes ? `/${lib.total_volumes}` : ""} tomes
              </p>
            </div>
            <ChevronRight className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          </a>
        ))}
      </div>

      {/* Préférences */}
      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5" style={{ borderBottom: "1px solid var(--border)" }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>
            Préférences
          </span>
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

      {/* Déconnexion */}
      <button
        onClick={() => signOut({ callbackUrl: "/login" })}
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
FILEOF
git add -A
git commit -m "fix: scan button waits for library, clean settings page"
git push
echo "🎉 Déployé !"
