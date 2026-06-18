import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { insertBook } from "@/lib/db";
import { createServerClient } from "@/lib/supabase";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    if (!body.library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
    if (!body.title)      return NextResponse.json({ error: "titre manquant" },       { status: 400 });

    const db = createServerClient();
    const isbn = body.isbn?.replace(/[^0-9X]/gi, "") || null;

    // Dedup by ISBN
    if (isbn) {
      const { data: dup } = await db.from("books")
        .select("id").eq("library_id", body.library_id).eq("isbn", isbn)
        .maybeSingle();
      if (dup) return NextResponse.json({ error: "Ce livre est déjà dans ta bibliothèque" }, { status: 409 });
    }

    // Dedup by title
    const { data: dupTitle } = await db.from("books")
      .select("id").eq("library_id", body.library_id)
      .ilike("title", body.title.trim())
      .maybeSingle();
    if (dupTitle) return NextResponse.json({ error: "Ce livre est déjà dans ta bibliothèque" }, { status: 409 });

    // added_by
    const addedBy = body.email
      ? await getProfileId(body.email).catch(() => null)
      : null;

    const book = await insertBook({
      library_id:     body.library_id,
      isbn,
      title:          body.title,
      authors:        body.authors ?? [],
      cover_url:      body.cover_url      || null,
      publisher:      body.publisher      || null,
      published_year: body.published_year || null,
      page_count:     body.page_count     || null,
      description:    body.description    || null,
      book_type:      body.book_type      ?? "livre",
      status:         body.status         ?? "a_lire",
      series_name:    body.series_name    || null,
      series_index:   body.series_index   || null,
      added_by:       addedBy,
    } as any);

    return NextResponse.json(book);
  } catch (e: any) {
    console.error("POST /api/books/add:", e);
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
