import { NextRequest, NextResponse } from "next/server";
import { getBooks, patchBook } from "@/lib/db";
import { searchDescription } from "@/lib/description-utils";

export async function POST(req: NextRequest) {
  const body = await req.json();
  const library_id = body.library_id;
  const limit = body.limit ?? 999; // default: all
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });

  try {
    const books = await getBooks(library_id);
    const withoutDesc = books.filter(b => !b.description).slice(0, limit);
    let updated = 0;

    for (const book of withoutDesc) {
      try {
        const desc = await searchDescription(book.title, book.authors, book.isbn);
        if (desc) {
          await patchBook(book.id, { description: desc } as any, library_id);
          updated++;
        }
        await new Promise(r => setTimeout(r, 200));
      } catch { /* skip */ }
    }

    return NextResponse.json({ total: withoutDesc.length, updated });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
