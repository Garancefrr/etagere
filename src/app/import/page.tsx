"use client";
import { useState, useRef } from "react";
import { useLibrary } from "@/hooks/useLibrary";
import { useData } from "@/contexts/DataContext";
import BottomNav from "@/components/layout/BottomNav";
import { Upload, CheckCircle, XCircle, AlertCircle, ArrowLeft, FileText } from "lucide-react";
import Link from "next/link";

type ImportStatus = "idle" | "uploading" | "done" | "error";

interface ImportResult {
  total: number;
  imported: number;
  skipped: number;
  errors: number;
  results: { title: string; status: "ok" | "skip" | "error"; reason?: string }[];
}

export default function ImportPage() {
  const { library_id, email } = useLibrary();
  const { refreshAll } = useData();
  const [status,    setStatus]    = useState<ImportStatus>("idle");
  const [result,    setResult]    = useState<ImportResult | null>(null);
  const [progress,  setProgress]  = useState(0);
  const [dragOver,  setDragOver]  = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const doImport = async (file: File) => {
    if (!library_id || !email) return;
    setStatus("uploading");
    setProgress(0);

    // Simulate progress while uploading
    const timer = setInterval(() => setProgress(p => Math.min(p + 2, 90)), 500);

    try {
      const formData = new FormData();
      formData.append("file", file);
      formData.append("library_id", library_id);
      formData.append("email", email);

      const res = await fetch("/api/import", { method: "POST", body: formData });
      clearInterval(timer);
      setProgress(100);

      if (!res.ok) throw new Error("Erreur serveur");
      const data = await res.json();
      setResult(data);
      setStatus("done");
      refreshAll();
    } catch {
      clearInterval(timer);
      setStatus("error");
    }
  };

  const handleFile = (file: File) => {
    if (!file.name.endsWith(".csv")) {
      alert("Merci de fournir un fichier .csv exporté depuis Babelio.");
      return;
    }
    doImport(file);
  };

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      {/* Header */}
      <div className="px-4 pt-12 pb-4">
        <Link href="/library" className="flex items-center gap-2 mb-4" style={{ color: "var(--txt3)", fontSize: 14 }}>
          <ArrowLeft className="w-4 h-4" /> Retour à la biblio
        </Link>
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Import</p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Babelio</h1>
      </div>

      <div className="px-4 flex flex-col gap-4">
        {/* How-to */}
        {status === "idle" && (
          <div className="p-4 rounded-2xl" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <p className="font-bold mb-3" style={{ fontSize: 15, color: "var(--txt1)" }}>Comment exporter depuis Babelio ?</p>
            {[
              "Va sur babelio.com et connecte-toi",
              'Clique sur ton profil → "Mes livres"',
              'En bas de page, clique sur "Exporter ma bibliothèque"',
              "Télécharge le fichier CSV",
              "Importe-le ici 👇",
            ].map((step, i) => (
              <div key={i} className="flex items-start gap-3 mb-2">
                <span className="w-5 h-5 rounded-full flex items-center justify-center text-white font-bold flex-shrink-0"
                  style={{ background: "var(--accent)", fontSize: 11, marginTop: 1 }}>{i + 1}</span>
                <span style={{ fontSize: 13, color: "var(--txt2)" }}>{step}</span>
              </div>
            ))}
          </div>
        )}

        {/* Drop zone */}
        {status === "idle" && (
          <div
            onDragOver={e => { e.preventDefault(); setDragOver(true); }}
            onDragLeave={() => setDragOver(false)}
            onDrop={e => { e.preventDefault(); setDragOver(false); const f = e.dataTransfer.files[0]; if (f) handleFile(f); }}
            onClick={() => inputRef.current?.click()}
            className="flex flex-col items-center justify-center gap-3 p-8 rounded-3xl cursor-pointer active:scale-98"
            style={{
              background: dragOver ? "var(--accent-l)" : "var(--surface)",
              border: `2px dashed ${dragOver ? "var(--accent)" : "var(--border)"}`,
              minHeight: 180,
            }}>
            <div className="w-14 h-14 rounded-2xl flex items-center justify-center"
              style={{ background: dragOver ? "var(--accent)" : "var(--surface2)" }}>
              <Upload className="w-7 h-7" style={{ color: dragOver ? "#fff" : "var(--accent)" }} />
            </div>
            <div className="text-center">
              <p className="font-bold" style={{ fontSize: 16, color: "var(--txt1)" }}>Glisse ton fichier ici</p>
              <p style={{ fontSize: 13, color: "var(--txt3)", marginTop: 4 }}>ou clique pour choisir un fichier .csv</p>
            </div>
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-full"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
              <FileText className="w-3.5 h-3.5" style={{ color: "var(--txt3)" }} />
              <span style={{ fontSize: 11, color: "var(--txt3)" }}>Biblio_export*.csv</span>
            </div>
            <input ref={inputRef} type="file" accept=".csv" className="hidden"
              onChange={e => { const f = e.target.files?.[0]; if (f) handleFile(f); }} />
          </div>
        )}

        {/* Loading */}
        {status === "uploading" && (
          <div className="p-6 rounded-3xl flex flex-col items-center gap-4"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <div className="w-16 h-16 rounded-2xl flex items-center justify-center"
              style={{ background: "var(--accent-l)" }}>
              <Upload className="w-8 h-8" style={{ color: "var(--accent)" }} />
            </div>
            <div className="text-center">
              <p className="font-bold" style={{ fontSize: 16, color: "var(--txt1)" }}>Import en cours…</p>
              <p style={{ fontSize: 13, color: "var(--txt3)", marginTop: 4 }}>Recherche des couvertures — patience 😊</p>
            </div>
            <div className="w-full h-3 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
              <div className="h-full rounded-full" style={{ width: `${progress}%`, background: "var(--accent)", transition: "width 0.5s" }} />
            </div>
            <p className="font-bold" style={{ fontSize: 14, color: "var(--accent)" }}>{progress}%</p>
          </div>
        )}

        {/* Error */}
        {status === "error" && (
          <div className="p-6 rounded-3xl flex flex-col items-center gap-3"
            style={{ background: "var(--miss-bg)", border: "1px solid var(--miss-b)" }}>
            <XCircle className="w-12 h-12" style={{ color: "var(--miss-t)" }} />
            <p className="font-bold text-center" style={{ fontSize: 16, color: "var(--miss-t)" }}>
              Erreur lors de l&apos;import
            </p>
            <button onClick={() => setStatus("idle")} className="px-6 py-3 rounded-2xl font-semibold"
              style={{ background: "var(--surface)", color: "var(--txt1)", border: "1px solid var(--border)" }}>
              Réessayer
            </button>
          </div>
        )}

        {/* Results */}
        {status === "done" && result && (
          <>
            {/* Summary */}
            <div className="p-5 rounded-3xl" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
              <div className="flex items-center gap-3 mb-4">
                <CheckCircle className="w-8 h-8 flex-shrink-0" style={{ color: "#22C55E" }} />
                <div>
                  <p className="font-bold" style={{ fontSize: 16, color: "var(--txt1)" }}>Import terminé !</p>
                  <p style={{ fontSize: 13, color: "var(--txt3)" }}>{result.total} livres traités</p>
                </div>
              </div>
              <div className="grid grid-cols-3 gap-3">
                {[
                  { label: "Importés", value: result.imported, color: "#22C55E", bg: "var(--have-bg)" },
                  { label: "Ignorés",  value: result.skipped,  color: "var(--txt3)", bg: "var(--surface2)" },
                  { label: "Erreurs",  value: result.errors,   color: "var(--miss-t)", bg: "var(--miss-bg)" },
                ].map(({ label, value, color, bg }) => (
                  <div key={label} className="flex flex-col items-center p-3 rounded-2xl" style={{ background: bg }}>
                    <span className="text-2xl font-bold" style={{ color }}>{value}</span>
                    <span className="text-xs mt-0.5" style={{ color }}>{label}</span>
                  </div>
                ))}
              </div>
            </div>

            {/* Errors detail */}
            {result.results.filter(r => r.status === "error").length > 0 && (
              <div className="p-4 rounded-2xl" style={{ background: "var(--miss-bg)", border: "1px solid var(--miss-b)" }}>
                <p className="font-bold mb-2" style={{ fontSize: 13, color: "var(--miss-t)" }}>Livres non importés :</p>
                {result.results.filter(r => r.status === "error").map((r, i) => (
                  <div key={i} className="flex items-start gap-2 py-1">
                    <AlertCircle className="w-3.5 h-3.5 flex-shrink-0 mt-0.5" style={{ color: "var(--miss-t)" }} />
                    <p style={{ fontSize: 12, color: "var(--miss-t)" }}>{r.title}</p>
                  </div>
                ))}
              </div>
            )}

            <Link href="/library"
              className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-2 text-center"
              style={{ background: "var(--accent)", color: "#fff", fontSize: 15 }}>
              Voir ma bibliothèque →
            </Link>
          </>
        )}
      </div>
      <BottomNav />
    </div>
  );
}
