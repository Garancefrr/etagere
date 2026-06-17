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
