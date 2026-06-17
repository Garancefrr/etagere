import { NextRequest, NextResponse } from "next/server";
import { getBooks, patchBook } from "@/lib/db";
import { searchCoverByTitle } from "@/lib/cover-utils";

export async function POST(req: NextRequest) {
  const { library_id } = await req.json();
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });

  try {
    const books = await getBooks(library_id);
    const withoutCover = books.filter(b => !b.cover_url);

    let updated = 0;
    const results: { title: string; found: boolean }[] = [];

    for (const book of withoutCover) {
      try {
        const cover = await searchCoverByTitle(book.title, book.series_name ?? undefined);
        if (cover) {
          await patchBook(book.id, { cover_url: cover });
          updated++;
          results.push({ title: book.title, found: true });
        } else {
          results.push({ title: book.title, found: false });
        }
        await new Promise(r => setTimeout(r, 300));
      } catch {
        results.push({ title: book.title, found: false });
      }
    }

    return NextResponse.json({ total: withoutCover.length, updated, results });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
