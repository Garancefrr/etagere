"use client";
import { useState } from "react";
import { ScanLine, Keyboard, Layers, ChevronRight, BookOpen } from "lucide-react";
import { Button } from "@/components/ui/Button";

const STEPS = [
  {
    icon: BookOpen, color: "#5B7AFF",
    title: "Bienvenue sur Folio 📚",
    desc: "Ta bibliothèque personnelle, toujours avec toi. Scanne tes livres, BD et mangas pour les organiser en collections.",
    visual: (
      <div className="flex gap-3 justify-center my-4">
        {["📖", "🎨", "⛩️"].map((e, i) => (
          <div key={i} className="w-16 h-16 rounded-2xl flex items-center justify-center"
            style={{ background: "var(--surface2)", border: "1px solid var(--border)", fontSize: 28 }}>{e}</div>
        ))}
      </div>
    ),
  },
  {
    icon: ScanLine, color: "#22C55E",
    title: "Le Scanner 📷",
    desc: "Pointe la caméra vers le code-barres au dos du livre. La détection est automatique !",
    visual: (
      <div className="relative mx-auto my-4 rounded-2xl overflow-hidden"
        style={{ width: 200, height: 130, background: "#111827", border: "2px solid rgba(34,197,94,0.4)" }}>
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="flex flex-col items-center gap-2">
            <div style={{ width: 120, height: 40, background: "repeating-linear-gradient(90deg, #fff 0px, #fff 2px, transparent 2px, transparent 5px)", opacity: 0.3, borderRadius: 4 }} />
            <span style={{ fontSize: 10, color: "rgba(255,255,255,0.5)" }}>CODE-BARRES</span>
          </div>
        </div>
        <div className="absolute left-1/2 -translate-x-1/2 top-0 bottom-0 w-px" style={{ background: "linear-gradient(transparent, #22C55E, transparent)" }} />
      </div>
    ),
  },
  {
    icon: Keyboard, color: "#FB923C",
    title: "L'ISBN, c'est quoi ? 🔢",
    desc: "Si le scan ne fonctionne pas, cherche l'ISBN imprimé sur le livre. Il commence par 978 ou par un chiffre (ex: 2-8001-...). Tu peux le taper manuellement via le bouton clavier.",
    visual: (
      <div className="mx-auto my-4 p-4 rounded-2xl" style={{ background: "var(--surface2)", border: "1px solid var(--border)", maxWidth: 240 }}>
        <div className="flex items-center gap-2 mb-2">
          <span style={{ fontSize: 11, color: "var(--txt3)", fontWeight: 700 }}>ISBN :</span>
        </div>
        <div className="flex gap-1">
          {["9","7","8","-","2","-","8","0","0","1"].map((c, i) => (
            <div key={i} className="w-5 h-7 rounded flex items-center justify-center"
              style={{ background: c === "-" ? "transparent" : "var(--accent-l)", fontSize: 12, fontWeight: 700, color: "var(--accent)" }}>
              {c}
            </div>
          ))}
          <span style={{ fontSize: 12, color: "var(--txt3)" }}>...</span>
        </div>
        <p style={{ fontSize: 10, color: "var(--txt3)", marginTop: 8 }}>
          📍 Au dos du livre, près du code-barres ou sur la page de copyright
        </p>
      </div>
    ),
  },
  {
    icon: Layers, color: "#A855F7",
    title: "Collections auto ✨",
    desc: "Les séries sont détectées automatiquement. Tes BD, mangas et sagas sont regroupées en collections avec suivi des tomes.",
    visual: (
      <div className="mx-auto my-4 flex flex-col gap-2" style={{ maxWidth: 240 }}>
        {[
          { name: "Les Schtroumpfs", tomes: "4/40", pct: 10 },
          { name: "Harry Potter", tomes: "7/7", pct: 100 },
        ].map(({ name, tomes, pct }) => (
          <div key={name} className="p-3 rounded-xl" style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
            <div className="flex justify-between items-center mb-1.5">
              <span style={{ fontSize: 13, fontWeight: 600, color: "var(--txt1)" }}>{name}</span>
              <span style={{ fontSize: 11, fontWeight: 700, color: "var(--accent)" }}>{tomes}</span>
            </div>
            <div className="h-1.5 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
              <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
            </div>
          </div>
        ))}
        <div className="flex gap-1.5 justify-center mt-1">
          {[1,2,3,4,5].map(n => (
            <div key={n} className="flex items-center justify-center font-bold"
              style={{ width: 24, height: 24, borderRadius: 6, fontSize: 9,
                background: n <= 2 ? "var(--have-bg)" : "var(--miss-bg)",
                color: n <= 2 ? "var(--have-t)" : "var(--miss-t)",
                border: n <= 2 ? "1px solid var(--have-b)" : "1px dashed var(--miss-b)" }}>
              {n}
            </div>
          ))}
        </div>
      </div>
    ),
  },
];

interface Props { onComplete: () => void; }

export default function Onboarding({ onComplete }: Props) {
  const [step, setStep] = useState(0);
  const current = STEPS[step];
  const isLast = step === STEPS.length - 1;
  const Icon = current.icon;

  return (
    <div className="fixed inset-0 z-[100] flex flex-col items-center justify-center px-6"
      style={{ background: "var(--bg)" }}>
      <div className="flex gap-2 mb-8">
        {STEPS.map((_, i) => (
          <div key={i} className="rounded-full transition-all"
            style={{ width: i === step ? 24 : 8, height: 8, background: i === step ? current.color : "var(--border)" }} />
        ))}
      </div>
      <div className="w-16 h-16 rounded-3xl flex items-center justify-center mb-4"
        style={{ background: `${current.color}18` }}>
        <Icon style={{ width: 28, height: 28, color: current.color }} />
      </div>
      <h2 className="text-center font-bold mb-2" style={{ fontSize: 22, color: "var(--txt1)" }}>{current.title}</h2>
      {current.visual}
      <p className="text-center mb-8 max-w-xs" style={{ fontSize: 15, color: "var(--txt2)", lineHeight: 1.6 }}>{current.desc}</p>
      <div className="w-full max-w-xs flex flex-col gap-3">
        <Button onClick={() => isLast ? onComplete() : setStep(s => s + 1)}
          className="w-full py-4 rounded-2xl" style={{ fontSize: 16 }}>
          {isLast ? "C'est parti ! 🚀" : "Suivant"} {!isLast && <ChevronRight className="w-5 h-5" />}
        </Button>
        {!isLast && (
          <button onClick={onComplete} className="w-full py-3 rounded-2xl font-semibold" style={{ fontSize: 14, color: "var(--txt3)" }}>
            Passer le tutoriel
          </button>
        )}
      </div>
    </div>
  );
}
