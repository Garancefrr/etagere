import { NextRequest, NextResponse } from "next/server";
import { getBooks } from "@/lib/db";
import { createServerClient } from "@/lib/supabase";
import { BookType, ReadStatus } from "@/types";

interface BabelioRow {
  ISBN: string; Titre: string; Auteur: string; Editeur: string;
  "Date de publication": string; "Date d`entrée dans Babelio": string; Statut: string; Note: string;
}

function mapStatus(s: string): ReadStatus {
  const lower = (s ?? "").toLowerCase().trim();
  if (lower === "lu") return "lu";
  if (lower === "en cours") return "en_cours";
  return "a_lire";
}

function detectType(title: string, publisher: string): BookType {
  const t = ((title ?? "") + " " + (publisher ?? "")).toLowerCase();
  if (/manga|manhwa|shonen|shojo|seinen/.test(t)) return "manga";
  if (/dargaud|dupuis|lombard|casterman|schtroumpf|ast\u00e9rix|tintin/.test(t)) return "bd";
  return "livre";
}

function extractSeries(title: string): { clean: string; seriesName?: string; seriesIndex?: number } {
  const patterns = [
    /^(.+?)[,\s]+tome\s+(\d+)\s*[:-]\s*(.+)$/i,
    /^(.+?)\s*[-\u2013\u2014]\s*tome\s+(\d+)\s*[:-]?\s*(.*)$/i,
    /^(.+?)\s*:\s*tome\s+(\d+)\s*[:-]?\s*(.*)$/i,
    /^(.+?)\s*[,]\s*tome\s+(\d+)$/i,
    /^(.+?)\s*[-\u2013\u2014]\s*tome\s+(\d+)$/i,
  ];
  for (const re of patterns) {
    const m = title.match(re);
    if (m && parseInt(m[2]) <= 200) {
      const clean = (m[3]?.trim()) || m[1].trim();
      return { clean, seriesName: m[1].trim(), seriesIndex: parseInt(m[2]) };
    }
  }
  const colonPattern = title.match(/^(.+?)\s*:\s*(.+)$/);
  if (colonPattern) return { clean: colonPattern[2].trim(), seriesName: colonPattern[1].trim() };
  return { clean: title };
}

function parseCSV(text: string): BabelioRow[] {
  const normalized = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  const lines = normalized.split("\n").filter(l => l.trim());
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
    if (row.Titre?.trim()) rows.push(row as BabelioRow);
  }
  return rows;
}

export async function POST(req: NextRequest) {
  try {
    const formData = await req.formData();
    const file = formData.get("file") as File | null;
    const library_id = formData.get("library_id") as string | null;
    const email = formData.get("email") as string | null;
    if (!file) return NextResponse.json({ error: "Fichier manquant" }, { status: 400 });
    if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
    if (!email) return NextResponse.json({ error: "email manquant" }, { status: 400 });

    // Auto-detect encoding
    const buffer = await file.arrayBuffer();
    let text = new TextDecoder("iso-8859-1").decode(buffer);
    try {
      const utf8 = new TextDecoder("utf-8").decode(buffer);
      if (!utf8.includes("\uFFFD")) text = utf8;
    } catch { /* keep iso */ }

    const rows = parseCSV(text);
    if (rows.length === 0) return NextResponse.json({ error: "Fichier vide ou format non reconnu" }, { status: 400 });

    // Dedup: load existing books
    const existingBooks = await getBooks(library_id).catch(() => []);
    const existingIsbns = new Set(existingBooks.map(b => b.isbn).filter(Boolean));
    const existingTitles = new Set(existingBooks.map(b => b.title.toLowerCase().trim()));

    // Prepare rows — filter duplicates and transform
    const prepared: any[] = [];
    const seenTitles = new Set<string>();
    for (const row of rows) {
      const rawTitle = (row.Titre ?? "").trim();
      if (!rawTitle) continue;
      const { clean: title, seriesName, seriesIndex } = extractSeries(rawTitle);
      const isbn = (row.ISBN ?? "").replace(/[^0-9X]/gi, "") || undefined;
      const titleKey = title.toLowerCase().trim();
      if (isbn && existingIsbns.has(isbn)) continue;
      if (existingTitles.has(titleKey)) continue;
      if (seenTitles.has(titleKey)) continue;
      seenTitles.add(titleKey);

      const authors = row.Auteur?.trim() ? [row.Auteur.trim()] : [];
      const publisher = row.Editeur?.trim() || undefined;
      const note = row.Note ? parseFloat(row.Note) : 0;

      const status = mapStatus(row.Statut ?? "");
      // Use Babelio date as finished_at for "lu" books
      const babelioDate = row["Date d`entrée dans Babelio"] ?? null;
      let finished_at: string | null = null;
      if (status === "lu" && babelioDate) {
        try {
          // Babelio format: "DD/MM/YYYY" or "YYYY-MM-DD"
          const parts = babelioDate.includes("/") ? babelioDate.split("/") : null;
          const d = parts ? new Date(parseInt(parts[2]), parseInt(parts[1]) - 1, parseInt(parts[0])) : new Date(babelioDate);
          if (!isNaN(d.getTime())) finished_at = d.toISOString();
        } catch { /* ignore */ }
      }

      prepared.push({
        isbn, title, authors, publisher,
        book_type: detectType(rawTitle, publisher ?? ""),
        status,
        series_name: seriesName || null,
        series_index: seriesIndex || null,
        rating: note > 0 ? Math.min(5, Math.round(note / 4)) : null,
        published_year: row["Date de publication"] ? parseInt((row["Date de publication"]).slice(0, 4)) || null : null,
        finished_at,
      });
    }

    // Store in DB for chunked processing
    const db = createServerClient();
    const { data: job, error } = await db.from("import_jobs").insert({
      library_id, email, total: prepared.length,
      progress: 0, imported: 0, errors: 0, skipped: rows.length - prepared.length,
      status: "running",
      rows_data: JSON.stringify(prepared),
    }).select().single();

    if (error || !job) return NextResponse.json({ error: "Impossible de creer le job: " + (error?.message ?? "") }, { status: 500 });

    return NextResponse.json({ job_id: job.id, total: prepared.length });
  } catch (e: any) {
    console.error("Import POST error:", e);
    return NextResponse.json({ error: e.message ?? "Erreur serveur" }, { status: 500 });
  }
}
