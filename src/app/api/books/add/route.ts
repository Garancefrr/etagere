import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { insertBook } from "@/lib/db";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();

    // Resolve added_by from email
    let addedBy: string | undefined;
    if (body.email) {
      addedBy = (await getProfileId(body.email)) ?? undefined;
    }

    // Whitelist only valid DB columns — no extra fields
    const bookData: Record<string, any> = {
      library_id:     body.library_id,
      isbn:           body.isbn,
      title:          body.title,
      authors:        body.authors ?? [],
      cover_url:      body.cover_url || null,
      publisher:      body.publisher || null,
      published_year: body.published_year || null,
      page_count:     body.page_count || null,
      description:    body.description || null,
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
