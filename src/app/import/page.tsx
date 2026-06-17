"use client";
import { useState, useRef } from "react";
import { useLibrary } from "@/hooks/useLibrary";
import { useData } from "@/contexts/DataContext";
import BottomNav from "@/components/layout/BottomNav";
import { useImportJob } from "@/components/import/ImportBanner";
import { Upload, FileText, ArrowLeft } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";

export default function ImportPage() {
  const { library_id, email } = useLibrary();
  const { refreshAll } = useData();
  const { startJob } = useImportJob();
  const router = useRouter();
  const [dragOver, setDragOver] = useState(false);
  const [loading,  setLoading]  = useState(false);
  const [error,    setError]    = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  const doImport = async (file: File) => {
    if (!library_id || !email || loading) return;
    if (!file.name.endsWith(".csv")) { setError("Merci de fournir un fichier .csv exporté depuis Babelio."); return; }
    setLoading(true); setError("");

    try {
      const formData = new FormData();
      formData.append("file", file);
      formData.append("library_id", library_id);
      formData.append("email", email);

      const res = await fetch("/api/import", { method: "POST", body: formData });
      if (!res.ok) throw new Error("Erreur serveur");
      const { job_id, total } = await res.json();

      // Register job for background banner
      startJob(job_id, total);

      // Go back to library — import continues in background
      router.push("/library");
    } catch (e: any) {
      setError(e.message ?? "Erreur lors du lancement de l'import");
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-12 pb-4">
        <Link href="/settings" className="flex items-center gap-2 mb-4" style={{ color: "var(--txt3)", fontSize: 14 }}>
          <ArrowLeft className="w-4 h-4" /> Retour
        </Link>
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Import</p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Babelio</h1>
      </div>

      <div className="px-4 flex flex-col gap-4">
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

        {error && (
          <div className="p-3 rounded-2xl" style={{ background: "var(--miss-bg)", border: "1px solid var(--miss-b)" }}>
            <p style={{ fontSize: 13, color: "var(--miss-t)" }}>{error}</p>
          </div>
        )}

        <div
          onDragOver={e => { e.preventDefault(); setDragOver(true); }}
          onDragLeave={() => setDragOver(false)}
          onDrop={e => { e.preventDefault(); setDragOver(false); const f = e.dataTransfer.files[0]; if (f) doImport(f); }}
          onClick={() => !loading && inputRef.current?.click()}
          className="flex flex-col items-center justify-center gap-3 p-8 rounded-3xl cursor-pointer"
          style={{
            background: dragOver ? "var(--accent-l)" : "var(--surface)",
            border: `2px dashed ${dragOver ? "var(--accent)" : "var(--border)"}`,
            minHeight: 200, opacity: loading ? 0.6 : 1,
          }}>
          {loading ? (
            <>
              <div className="w-14 h-14 rounded-2xl flex items-center justify-center" style={{ background: "var(--accent-l)" }}>
                <div className="w-7 h-7 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
              </div>
              <div className="text-center">
                <p className="font-bold" style={{ fontSize: 16, color: "var(--txt1)" }}>Démarrage de l&apos;import…</p>
                <p style={{ fontSize: 13, color: "var(--txt3)", marginTop: 4 }}>Tu peux naviguer librement ensuite</p>
              </div>
            </>
          ) : (
            <>
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
            </>
          )}
          <input ref={inputRef} type="file" accept=".csv" className="hidden"
            onChange={e => { const f = e.target.files?.[0]; if (f) doImport(f); }} />
        </div>

        <p className="text-center" style={{ fontSize: 13, color: "var(--txt3)" }}>
          L&apos;import tourne en arrière-plan — tu peux continuer à utiliser l&apos;app
        </p>
      </div>
      <BottomNav />
    </div>
  );
}
