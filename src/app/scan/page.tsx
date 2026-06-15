"use client";
import { useState, useCallback } from "react";
import { ScanResult, ReadStatus, BookType } from "@/types";
import BottomNav from "@/components/layout/BottomNav";
import Scanner from "@/components/scanner/Scanner";
import { ToastStack } from "@/components/ui/Toast";
import { useToast } from "@/hooks/useToast";
import { useFirstUse } from "@/hooks/useFirstUse";
import { ScanLine, Zap, Settings2 } from "lucide-react";

export default function ScanPage() {
  const [scanning,  setScanning]  = useState(false);
  const [rapidMode, setRapidMode] = useState(false);
  const isFirstUse = useFirstUse("folio_scan_seen");
  const { toasts, push, dismiss } = useToast();

  const handleSuccess = useCallback((result: ScanResult) => {
    if (rapidMode) {
      push(result.book.title, result.isNewCollection ? `Collection « ${result.collection?.name} » créée` : undefined);
    } else {
      setScanning(false);
      push("Ajouté !", result.book.title);
    }
  }, [rapidMode, push]);

  // Avoid hydration flash from localStorage
  if (isFirstUse === null) return null;

  return (
    <>
      <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>
        <div className="px-4 pt-12 pb-4">
          <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>
            Ajouter
          </p>
          <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Scanner</h1>
        </div>

        {/* Mode toggle */}
        <div className="mx-4 mb-6 flex p-1 rounded-2xl" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          {MODES.map(({ key, icon: Icon, label, sub }) => (
            <button
              key={String(key)}
              onClick={() => setRapidMode(key)}
              className="flex-1 flex items-center gap-3 px-3 py-3 rounded-xl transition-all"
              style={{ background: rapidMode === key ? "var(--accent)" : "transparent" }}
            >
              <Icon className="w-5 h-5 flex-shrink-0" style={{ color: rapidMode === key ? "#fff" : "var(--txt3)" }} />
              <div className="text-left">
                <p className="font-bold" style={{ fontSize: 13, color: rapidMode === key ? "#fff" : "var(--txt1)" }}>{label}</p>
                <p style={{ fontSize: 11, color: rapidMode === key ? "rgba(255,255,255,0.7)" : "var(--txt3)" }}>{sub}</p>
              </div>
            </button>
          ))}
        </div>

        {/* CTA */}
        {isFirstUse ? <FirstUseInstructions onStart={() => setScanning(true)} /> : <ScanButton rapidMode={rapidMode} onStart={() => setScanning(true)} />}
      </div>

      {scanning && (
        <Scanner rapidMode={rapidMode} onSuccess={handleSuccess} onClose={() => setScanning(false)} />
      )}

      <ToastStack toasts={toasts} onDismiss={dismiss} />
      <BottomNav />
    </>
  );
}

// ── Static data ───────────────────────────────────────────────────────────────

const MODES = [
  { key: false, icon: Settings2, label: "Mode classique", sub: "Confirmation avant ajout" },
  { key: true,  icon: Zap,       label: "Mode rapide",    sub: "Ajout instantané en série" },
] as const;

// ── Sub-components ────────────────────────────────────────────────────────────

function ScanButton({ rapidMode, onStart }: { rapidMode: boolean; onStart: () => void }) {
  return (
    <div className="flex flex-col items-center gap-4 px-5">
      <button onClick={onStart}
        className="w-full py-5 rounded-3xl flex items-center justify-center gap-3 active:scale-95"
        style={{ background: "var(--accent)", boxShadow: "0 8px 32px rgba(59,91,255,0.35)" }}>
        <ScanLine className="w-7 h-7 text-white" />
        <span className="font-bold text-white" style={{ fontSize: 17 }}>
          {rapidMode ? "Lancer le mode rapide" : "Ouvrir le scanner"}
        </span>
      </button>
      <p className="text-center" style={{ fontSize: 13, color: "var(--txt3)" }}>
        {rapidMode ? "Chaque scan est ajouté immédiatement" : "ISBN détecté automatiquement par la caméra"}
      </p>
    </div>
  );
}

function FirstUseInstructions({ onStart }: { onStart: () => void }) {
  const STEPS = [
    "Pointez la caméra vers le code-barres",
    "La détection est automatique",
    "Les BD créent leur collection automatiquement",
  ];
  return (
    <div className="flex flex-col items-center gap-6 px-5">
      <button onClick={onStart}
        className="w-32 h-32 rounded-3xl flex flex-col items-center justify-center gap-2 active:scale-95"
        style={{ background: "var(--accent)", boxShadow: "0 8px 32px rgba(59,91,255,0.35)" }}>
        <ScanLine className="w-12 h-12 text-white" />
        <span className="font-bold text-white text-sm">Scanner</span>
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
              style={{ background: "var(--accent)", fontSize: 13 }}>
              {i + 1}
            </span>
            <span style={{ fontSize: 14, color: "var(--txt2)" }}>{text}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
