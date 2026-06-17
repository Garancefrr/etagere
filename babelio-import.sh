#!/bin/bash
set -e
echo "📥 Import Babelio CSV..."
cd "$(git rev-parse --show-toplevel)"
mkdir -p src/app/api/import src/app/import
cat > "src/app/api/import/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { insertBook, findCollection, resolveCollection, patchCollection } from "@/lib/db";
import { searchCoverByTitle } from "@/lib/cover-utils";
import { BookType, ReadStatus } from "@/types";

interface BabelioRow {
  ISBN: string;
  Titre: string;
  Auteur: string;
  Editeur: string;
  "Date de publication": string;
  "Date d`entrée dans Babelio": string;
  Statut: string;
  Note: string;
}

// Map Babelio status to Folio status
function mapStatus(s: string): ReadStatus {
  const lower = s.toLowerCase().trim();
  if (lower === "lu") return "lu";
  if (lower === "en cours") return "en_cours";
  return "a_lire";
}

// Detect book type from title/publisher
function detectType(title: string, publisher: string): BookType {
  const t = (title + " " + publisher).toLowerCase();
  if (/manga|manhwa|shonen|shojo|seinen/.test(t)) return "manga";
  if (/dargaud|dupuis|lombard|casterman|bd|comics|schtroumpf|ast[eé]rix|tintin/.test(t)) return "bd";
  return "livre";
}

// Extract series from title like "Cycle de Fondation : Tome 1 - Titre"
function extractSeries(title: string): { clean: string; seriesName?: string; seriesIndex?: number } {
  // Pattern: "Series, tome X" or "Series : Sous-titre" or "Series - tome X - Titre"
  const patterns = [
    /^(.+?)[,\s]+tome\s+(\d+)\s*[:-]\s*(.+)$/i,
    /^(.+?)\s*[-–—]\s*tome\s+(\d+)\s*[:-]?\s*(.*)$/i,
    /^(.+?)\s*:\s*tome\s+(\d+)\s*[:-]?\s*(.*)$/i,
    /^(.+?)\s*,\s*tome\s+(\d+)$/i,
    /^(.+?)\s*[-–—]\s*tome\s+(\d+)$/i,
  ];
  for (const re of patterns) {
    const m = title.match(re);
    if (m) {
      const seriesName = m[1].trim();
      const seriesIndex = parseInt(m[2]);
      const subtitle = m[3]?.trim() || "";
      // Use subtitle as book title if present, otherwise use series name
      const clean = subtitle || seriesName;
      return { clean, seriesName, seriesIndex };
    }
  }
  // Pattern: "Series : Subtitle" without tome number — just clean
  const colonPattern = title.match(/^(.+?)\s*:\s*(.+)$/);
  if (colonPattern) {
    return { clean: colonPattern[2].trim(), seriesName: colonPattern[1].trim() };
  }
  return { clean: title };
}

// Parse CSV (semicolon-separated, ISO-8859, quoted fields)
function parseCSV(text: string): BabelioRow[] {
  const lines = text.split(/?
/).filter(l => l.trim());
  if (lines.length < 2) return [];
  const headers = lines[0].split(";").map(h => h.replace(/^"|"$/g, "").trim());
  const rows: BabelioRow[] = [];
  for (let i = 1; i < lines.length; i++) {
    const values: string[] = [];
    let current = "";
    let inQuotes = false;
    for (const ch of lines[i]) {
      if (ch === '"') { inQuotes = !inQuotes; }
      else if (ch === ";" && !inQuotes) { values.push(current.trim()); current = ""; }
      else { current += ch; }
    }
    values.push(current.trim());
    const row: any = {};
    headers.forEach((h, idx) => { row[h] = values[idx] ?? ""; });
    rows.push(row as BabelioRow);
  }
  return rows;
}

export async function POST(req: NextRequest) {
  try {
    const formData = await req.formData();
    const file = formData.get("file") as File | null;
    const library_id = formData.get("library_id") as string;
    const email = formData.get("email") as string;

    if (!file || !library_id || !email) {
      return NextResponse.json({ error: "Paramètres manquants" }, { status: 400 });
    }

    // Decode ISO-8859-1 CSV
    const buffer = await file.arrayBuffer();
    const decoder = new TextDecoder("iso-8859-1");
    const text = decoder.decode(buffer);
    const rows = parseCSV(text);

    const profileId = await getProfileId(email);
    let imported = 0, skipped = 0, errors = 0;
    const results: { title: string; status: "ok" | "skip" | "error"; reason?: string }[] = [];

    for (const row of rows) {
      const isbn = row.ISBN?.replace(/[^0-9X]/gi, "");
      const rawTitle = row.Titre?.trim();
      if (!rawTitle) { skipped++; continue; }

      const { clean: title, seriesName, seriesIndex } = extractSeries(rawTitle);
      const authors = row.Auteur ? [row.Auteur.trim()] : [];
      const publisher = row.Editeur?.trim() || undefined;
      const bookType = detectType(rawTitle, publisher ?? "");
      const status = mapStatus(row.Statut ?? "");
      const note = row.Note ? parseFloat(row.Note) : 0;
      const rating = note > 0 ? Math.round(note / 4) : undefined; // Babelio /20 → Folio /5

      // Get cover
      const cover = await searchCoverByTitle(title, seriesName);

      try {
        const book = await insertBook({
          library_id,
          isbn: isbn || undefined,
          title,
          authors,
          cover_url: cover ?? undefined,
          publisher,
          published_year: row["Date de publication"] ? parseInt(row["Date de publication"].slice(0,4)) : undefined,
          book_type: bookType,
          status,
          series_name: seriesName || undefined,
          series_index: seriesIndex || undefined,
          rating,
          added_by: profileId ?? undefined,
        } as any);

        // Create collection for series
        if (seriesName && seriesIndex && (bookType === "bd" || bookType === "manga")) {
          try {
            const existing = await findCollection(library_id, seriesName);
            await resolveCollection(library_id, seriesName, seriesIndex, {
              cover_url: cover ?? undefined, author: authors[0], book_type: bookType
            });
          } catch { /* ignore collection errors */ }
        }

        imported++;
        results.push({ title: rawTitle, status: "ok" });
      } catch (e: any) {
        errors++;
        results.push({ title: rawTitle, status: "error", reason: e.message });
      }

      // Rate limiting
      await new Promise(r => setTimeout(r, 100));
    }

    return NextResponse.json({ total: rows.length, imported, skipped, errors, results });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
FILEOF
cat > "src/app/import/page.tsx" << 'FILEOF'
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
FILEOF
cat > "src/app/settings/page.tsx" << 'FILEOF'
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
FILEOF
git add -A
git commit -m "feat: Babelio CSV import — 214 books, series detection, cover search"
git push
echo "🎉 Déployé !"
