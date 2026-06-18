import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@/lib/supabase";
import { insertBook, resolveCollection } from "@/lib/db";
import { getProfileId } from "@/lib/auth";

const BATCH_SIZE = 20;

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
        return NextResponse.json({ ...job, status: "done", progress: 100, rows_data: undefined });
      }

      const profileId = await getProfileId(job.email).catch(() => null);
      let imported = job.imported ?? 0;
      let errors = job.errors ?? 0;
      let lastError = "";

      for (const row of batch) {
        try {
          await insertBook({
            library_id: job.library_id, isbn: row.isbn, title: row.title,
            authors: row.authors ?? [], cover_url: undefined,
            publisher: row.publisher, published_year: row.published_year,
            book_type: row.book_type ?? "livre", status: row.status ?? "a_lire",
            series_name: row.series_name, series_index: row.series_index,
            rating: row.rating, description: undefined,
            added_by: profileId ?? null,
          } as any);

          if (row.series_name && row.series_index && (row.book_type === "bd" || row.book_type === "manga")) {
            await resolveCollection(job.library_id, row.series_name, row.series_index, {
              author: row.authors?.[0], book_type: row.book_type
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
      return NextResponse.json({ ...job, rows_data: undefined });
    }
  }

  return NextResponse.json({
    status: job.status, progress: job.progress ?? 0,
    imported: job.imported ?? 0, errors: job.errors ?? 0,
    skipped: job.skipped ?? 0, total: job.total ?? 0,
  });
}
