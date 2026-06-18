import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { insertBook, findCollection, resolveCollection, getBooks } from "@/lib/db";
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
  const lower = s.toLowerCase().trim();
  if (lower === "lu") return "lu";
  if (lower === "en cours") return "en_cours";
  return "a_lire";
}

function detectType(title: string, publisher: string): BookType {
  const t = (title + " " + publisher).toLowerCase();
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
    rows.push(row as BabelioRow);
  }
  return rows;
}

async function runImport(jobId: string, rows: BabelioRow[], libraryId: string, email: string) {
  const db = createServerClient();
  const profileId = await getProfileId(email);

  // Load existing books to check for duplicates
  const existingBooks = await getBooks(libraryId);
  const existingIsbns = new Set(existingBooks.map(b => b.isbn).filter(Boolean));
  const existingTitles = new Set(
    existingBooks.map(b => b.title.toLowerCase().trim())
  );

  let imported = 0, skipped = 0, errors = 0;
  const total = rows.length;

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const rawTitle = row.Titre?.trim();
    if (!rawTitle) { skipped++; continue; }

    const { clean: title, seriesName, seriesIndex } = extractSeries(rawTitle);
    const isbn = row.ISBN?.replace(/[^0-9X]/gi, "") || undefined;

    // Skip if already exists (by ISBN or title)
    if (isbn && existingIsbns.has(isbn)) { skipped++; continue; }
    if (existingTitles.has(title.toLowerCase().trim())) { skipped++; continue; }

    const authors = row.Auteur ? [row.Auteur.trim()] : [];
    const publisher = row.Editeur?.trim() || undefined;
    const bookType = detectType(rawTitle, publisher ?? "");
    const status = mapStatus(row.Statut ?? "");
    const note = row.Note ? parseFloat(row.Note) : 0;
    const rating = note > 0 ? Math.round(note / 4) : undefined;

    try {
      const cover = await searchCoverByTitle(title, seriesName);
      await insertBook({
        library_id: libraryId, isbn, title, authors,
        cover_url: cover ?? undefined, publisher,
        published_year: row["Date de publication"] ? parseInt(row["Date de publication"].slice(0, 4)) : undefined,
        book_type: bookType, status,
        series_name: seriesName || undefined,
        series_index: seriesIndex || undefined,
        rating, added_by: profileId ?? undefined,
      } as any);

      // Track to avoid importing same title twice in same batch
      existingTitles.add(title.toLowerCase().trim());
      if (isbn) existingIsbns.add(isbn);

      if (seriesName && seriesIndex && (bookType === "bd" || bookType === "manga")) {
        try {
          await resolveCollection(libraryId, seriesName, seriesIndex, {
            cover_url: cover ?? undefined, author: authors[0], book_type: bookType
          });
        } catch { /* ignore */ }
      }
      imported++;
    } catch { errors++; }

    if (i % 5 === 0 || i === total - 1) {
      const progress = Math.round(((i + 1) / total) * 100);
      await db.from("import_jobs").update({
        progress, imported, errors, skipped,
        status: i === total - 1 ? "done" : "running",
        updated_at: new Date().toISOString(),
      }).eq("id", jobId);
    }

    await new Promise(r => setTimeout(r, 100));
  }
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

    const buffer = await file.arrayBuffer();
    const decoder = new TextDecoder("iso-8859-1");
    const text = decoder.decode(buffer);
    const rows = parseCSV(text);

    const db = createServerClient();
    const { data: job, error } = await db.from("import_jobs").insert({
      library_id, email, total: rows.length,
      progress: 0, imported: 0, errors: 0, skipped: 0,
      status: "running",
    }).select().single();

    if (error || !job) throw new Error("Impossible de créer le job");

    runImport(job.id, rows, library_id, email).catch(console.error);

    return NextResponse.json({ job_id: job.id, total: rows.length });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
