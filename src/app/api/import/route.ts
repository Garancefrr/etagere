import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { insertBook, resolveCollection, getBooks } from "@/lib/db";
import { searchCoverByTitle } from "@/lib/cover-utils";
import { createServerClient } from "@/lib/supabase";
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
  // Normalize line endings
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

async function ensureJobsTable(db: any): Promise<boolean> {
  try {
    const { error } = await db.from("import_jobs").select("id").limit(1);
    if (error?.code === "42P01") {
      // Table doesn't exist — create it
      await db.rpc("exec_sql", {
        sql: `CREATE TABLE IF NOT EXISTS import_jobs (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          library_id UUID,
          email TEXT,
          total INTEGER DEFAULT 0,
          progress INTEGER DEFAULT 0,
          imported INTEGER DEFAULT 0,
          errors INTEGER DEFAULT 0,
          skipped INTEGER DEFAULT 0,
          status TEXT DEFAULT 'running',
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        );`
      });
      return true;
    }
    return true;
  } catch { return false; }
}

async function runImport(jobId: string | null, rows: BabelioRow[], libraryId: string, email: string) {
  const db = createServerClient();
  const profileId = await getProfileId(email).catch(() => null);

  // Load existing books for dedup
  const existingBooks = await getBooks(libraryId).catch(() => []);
  const existingIsbns = new Set(existingBooks.map(b => b.isbn).filter(Boolean));
  const existingTitles = new Set(existingBooks.map(b => b.title.toLowerCase().trim()));

  let imported = 0, skipped = 0, errors = 0;
  const total = rows.length;

  const updateJob = async (i: number) => {
    if (!jobId) return;
    try {
      const progress = Math.round(((i + 1) / total) * 100);
      await db.from("import_jobs").update({
        progress, imported, errors, skipped,
        status: i >= total - 1 ? "done" : "running",
        updated_at: new Date().toISOString(),
      }).eq("id", jobId);
    } catch { /* ignore job update errors */ }
  };

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const rawTitle = (row.Titre ?? "").trim();
    if (!rawTitle) { skipped++; continue; }

    const { clean: title, seriesName, seriesIndex } = extractSeries(rawTitle);
    const isbn = (row.ISBN ?? "").replace(/[^0-9X]/gi, "") || undefined;

    // Skip duplicates
    if (isbn && existingIsbns.has(isbn)) { skipped++; continue; }
    if (existingTitles.has(title.toLowerCase().trim())) { skipped++; continue; }

    const authors = row.Auteur?.trim() ? [row.Auteur.trim()] : [];
    const publisher = row.Editeur?.trim() || undefined;
    const bookType = detectType(rawTitle, publisher ?? "");
    const status = mapStatus(row.Statut ?? "");
    const note = row.Note ? parseFloat(row.Note) : 0;
    const rating = note > 0 ? Math.min(5, Math.round(note / 4)) : undefined;

    try {
      const cover = await searchCoverByTitle(title, seriesName).catch(() => null);

      await insertBook({
        library_id: libraryId, isbn, title, authors,
        cover_url: cover ?? undefined, publisher,
        published_year: row["Date de publication"]
          ? parseInt((row["Date de publication"] ?? "").slice(0, 4)) || undefined
          : undefined,
        book_type: bookType, status,
        series_name: seriesName || undefined,
        series_index: seriesIndex || undefined,
        rating, added_by: profileId ?? undefined,
      } as any);

      existingTitles.add(title.toLowerCase().trim());
      if (isbn) existingIsbns.add(isbn);

      if (seriesName && seriesIndex && (bookType === "bd" || bookType === "manga")) {
        await resolveCollection(libraryId, seriesName, seriesIndex, {
          cover_url: cover ?? undefined, author: authors[0], book_type: bookType
        }).catch(() => null);
      }
      imported++;
    } catch (e) {
      console.error("Import row error:", e);
      errors++;
    }

    if (i % 5 === 0 || i === total - 1) await updateJob(i);
    await new Promise(r => setTimeout(r, 100));
  }
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

    // Try both encodings
    const buffer = await file.arrayBuffer();
    let text = "";
    try {
      text = new TextDecoder("iso-8859-1").decode(buffer);
      // If it looks like UTF-8 (has typical UTF-8 BOM or french chars encoded correctly), use UTF-8
      const utf8 = new TextDecoder("utf-8").decode(buffer);
      if (!utf8.includes("\uFFFD")) text = utf8; // no replacement chars = valid UTF-8
    } catch {
      text = new TextDecoder("utf-8").decode(buffer);
    }

    const rows = parseCSV(text);
    if (rows.length === 0) {
      return NextResponse.json({ error: "Fichier vide ou format non reconnu" }, { status: 400 });
    }

    const db = createServerClient();

    // Try to create job — if table doesn't exist, run import synchronously
    let jobId: string | null = null;
    try {
      const { data: job, error } = await db.from("import_jobs").insert({
        library_id, email, total: rows.length,
        progress: 0, imported: 0, errors: 0, skipped: 0,
        status: "running",
      }).select().single();

      if (!error && job) jobId = job.id;
    } catch { /* table might not exist — continue without job tracking */ }

    // Fire and forget
    runImport(jobId, rows, library_id, email).catch(console.error);

    return NextResponse.json({ job_id: jobId, total: rows.length });
  } catch (e: any) {
    console.error("Import POST error:", e);
    return NextResponse.json({ error: e.message ?? "Erreur serveur" }, { status: 500 });
  }
}
