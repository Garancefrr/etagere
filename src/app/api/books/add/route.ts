import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { insertBook, getBooks } from "@/lib/db";
import { searchDescription } from "@/lib/description-utils";
import { resolveUser } from "@/lib/auth";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    if (!body.library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
    if (!body.title) return NextResponse.json({ error: "titre manquant" }, { status: 400 });

    // Fix #5: Validate library ownership
    if (body.email) {
      const user = await resolveUser(body.email);
      if (user && user.library_id !== body.library_id) {
        return NextResponse.json({ error: "Accès non autorisé" }, { status: 403 });
      }
    }

    // Fix #3: Dedup check — reject if same ISBN or title already exists
    const existing = await getBooks(body.library_id).catch(() => []);
    const isbn = body.isbn?.replace(/[^0-9X]/gi, "");
    if (isbn && existing.some(b => b.isbn === isbn)) {
      return NextResponse.json({ error: "Ce livre est déjà dans ta bibliothèque (ISBN identique)" }, { status: 409 });
    }
    if (existing.some(b => b.title.toLowerCase().trim() === (body.title ?? "").toLowerCase().trim())) {
      return NextResponse.json({ error: "Ce livre est déjà dans ta bibliothèque (titre identique)" }, { status: 409 });
    }

    // Resolve added_by from email
    let addedBy: string | undefined;
    if (body.email) {
      addedBy = (await getProfileId(body.email)) ?? undefined;
    }

    // Auto-fetch description if not provided
    let description = body.description || null;
    if (!description) {
      description = await searchDescription(body.title, body.authors ?? [], body.isbn).catch(() => null);
    }

    const bookData: Record<string, any> = {
      library_id:     body.library_id,
      isbn:           isbn || null,
      title:          body.title,
      authors:        body.authors ?? [],
      cover_url:      body.cover_url || null,
      publisher:      body.publisher || null,
      published_year: body.published_year || null,
      page_count:     body.page_count || null,
      description:    description,
      book_type:      body.book_type ?? "livre",
      status:         body.status ?? "a_lire",
      series_name:    body.series_name || null,
      series_index:   body.series_index || null,
      added_by:       addedBy || null,
    };

    const book = await insertBook(bookData as any);
    return NextResponse.json(book);
  } catch (e: any) {
    console.error("POST /api/books/add:", e);
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
