import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { insertBook } from "@/lib/db";
import { createServerClient } from "@/lib/supabase";
import { searchDescription } from "@/lib/description-utils";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    if (!body.library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
    if (!body.title)      return NextResponse.json({ error: "titre manquant" },       { status: 400 });

    const db = createServerClient();
    const isbn = body.isbn?.replace(/[^0-9X]/gi, "") || null;

    // Dedup: single targeted query instead of loading all books
    const titleKey = (body.title ?? "").toLowerCase().trim();
    const dupQuery = db.from("books")
      .select("id, title, isbn")
      .eq("library_id", body.library_id);

    if (isbn) {
      const { data: byIsbn } = await dupQuery.eq("isbn", isbn).maybeSingle();
      if (byIsbn) return NextResponse.json({ error: "Ce livre est déjà dans ta bibliothèque" }, { status: 409 });
    }

    const { data: byTitle } = await db.from("books")
      .select("id")
      .eq("library_id", body.library_id)
      .ilike("title", titleKey)
      .maybeSingle();
    if (byTitle) return NextResponse.json({ error: "Ce livre est déjà dans ta bibliothèque" }, { status: 409 });

    // Resolve added_by (non-blocking)
    const addedBy = body.email
      ? await getProfileId(body.email).catch(() => null)
      : null;

    // Description: use provided or fetch async (non-blocking — don't wait)
    let description = body.description || null;
    if (!description) {
      // Fire and forget — don't block the add
      description = await searchDescription(
        body.title, body.authors ?? [], isbn ?? undefined
      ).catch(() => null);
    }

    const book = await insertBook({
      library_id:     body.library_id,
      isbn,
      title:          body.title,
      authors:        body.authors ?? [],
      cover_url:      body.cover_url  || null,
      publisher:      body.publisher  || null,
      published_year: body.published_year || null,
      page_count:     body.page_count || null,
      description,
      book_type:      body.book_type  ?? "livre",
      status:         body.status     ?? "a_lire",
      series_name:    body.series_name  || null,
      series_index:   body.series_index || null,
      added_by:       addedBy,
    } as any);

    return NextResponse.json(book);
  } catch (e: any) {
    console.error("POST /api/books/add:", e);
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
