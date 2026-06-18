import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@/lib/supabase";
import { insertBook, resolveCollection } from "@/lib/db";
import { getProfileId } from "@/lib/auth";
import { validateCoverUrl } from "@/lib/cover-utils";

const BATCH_SIZE = 5;

async function quickCover(title: string, isbn?: string | null): Promise<string | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const q = isbn ? `isbn:${isbn}` : `intitle:${encodeURIComponent(title)}`;

  // Try with API key, then without on quota error
  for (const key of [apiKey ? `&key=${apiKey}` : "", ""]) {
    try {
      const res = await fetch(
        `https://www.googleapis.com/books/v1/volumes?q=${q}&maxResults=1${key}`,
        { signal: AbortSignal.timeout(2500) }
      );
      if (res.status === 403 || res.status === 429) continue; // quota, try without key
      if (!res.ok) return null;
      const data = await res.json();
      const links = data.items?.[0]?.volumeInfo?.imageLinks;
      if (!links) return null;
      const url = links.large ?? links.medium ?? links.thumbnail;
      return validateCoverUrl(url);
    } catch { continue; }
  }
  return null;
}

export async function GET(req: NextRequest) {
  const job_id = req.nextUrl.searchParams.get("job_id");
  if (!job_id) return NextResponse.json({ error: "job_id manquant" }, { status: 400 });

  const db = createServerClient();
  const { data: job } = await db.from("import_jobs").select("*").eq("id", job_id).maybeSingle();
  if (!job) return NextResponse.json({ error: "Job introuvable" }, { status: 404 });

  if (job.status === "running" && job.rows_data) {
    try {
      const rows: any[] = JSON.parse(job.rows_data);
      const cursor = (job.imported ?? 0) + (job.errors ?? 0);
      const batch = rows.slice(cursor, cursor + BATCH_SIZE);

      if (batch.length === 0) {
        await db.from("import_jobs").update({
          status: "done", progress: 100, rows_data: null,
          updated_at: new Date().toISOString(),
        }).eq("id", job_id);
        return NextResponse.json({ ...job, status: "done", progress: 100 });
      }

      // Verify library exists
      const { data: lib } = await db.from("libraries").select("id").eq("id", job.library_id).maybeSingle();
      if (!lib) {
        await db.from("import_jobs").update({ status: "error", updated_at: new Date().toISOString() }).eq("id", job_id);
        return NextResponse.json({ status: "error", error: "Bibliothèque introuvable — reconnectez-vous et relancez l'import", progress: 0, imported: 0, errors: 0, skipped: 0, total: job.total ?? 0 });
      }

      const profileId = await getProfileId(job.email).catch(() => null);
      let imported = job.imported ?? 0;
      let errors = job.errors ?? 0;
      let lastError = "";

      for (const row of batch) {
        try {
          // Fetch cover with short timeout — don't block if slow
          const cover = await quickCover(row.title, row.isbn).catch(() => null);

          await insertBook({
            library_id:     job.library_id,
            isbn:           row.isbn ?? null,
            title:          row.title,
            authors:        row.authors ?? [],
            cover_url:      cover,
            publisher:      row.publisher ?? null,
            published_year: row.published_year ?? null,
            book_type:      row.book_type ?? "livre",
            status:         row.status ?? "a_lire",
            series_name:    row.series_name ?? null,
            series_index:   row.series_index ?? null,
            rating:         row.rating ?? null,
            description:    null,
            added_by:       profileId ?? null,
          } as any);

          if (row.series_name && row.series_index && (row.book_type === "bd" || row.book_type === "manga")) {
            await resolveCollection(job.library_id, row.series_name, row.series_index, {
              cover_url: cover ?? undefined, author: row.authors?.[0], book_type: row.book_type
            }).catch(() => null);
          }
          imported++;
        } catch (e: any) {
          lastError = e?.message ?? String(e);
          console.error("Import book error:", lastError, "book:", row.title);
          errors++;
        }
      }

      const total = rows.length;
      const processed = imported + errors;
      const progress = Math.round((processed / total) * 100);
      const isDone = processed >= total;

      await db.from("import_jobs").update({
        imported, errors, progress,
        status: isDone ? "done" : "running",
        rows_data: isDone ? null : job.rows_data,
        updated_at: new Date().toISOString(),
      }).eq("id", job_id);

      return NextResponse.json({
        status: isDone ? "done" : "running",
        progress, imported, errors,
        skipped: job.skipped ?? 0, total,
        lastError: lastError || undefined,
      });
    } catch (e: any) {
      console.error("Import batch error:", e);
      return NextResponse.json({ status: "error", error: e.message });
    }
  }

  return NextResponse.json({
    status: job.status, progress: job.progress ?? 0,
    imported: job.imported ?? 0, errors: job.errors ?? 0,
    skipped: job.skipped ?? 0, total: job.total ?? 0,
  });
}
