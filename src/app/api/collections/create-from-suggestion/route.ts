import { NextRequest, NextResponse } from "next/server";
import { insertCollection, patchBook, findCollection } from "@/lib/db";
import { BookType } from "@/types";

export async function POST(req: NextRequest) {
  try {
    const { library_id, name, author, book_type, cover_url, books } = await req.json();
    if (!library_id || !name) return NextResponse.json({ error: "Paramètres manquants" }, { status: 400 });

    // Get volume count for series
    let ownedVolumes: number[] = [];
    books.forEach((b: any) => {
      if (b.series_index) ownedVolumes.push(b.series_index);
    });
    if (ownedVolumes.length === 0) {
      // Author collection: use sequential numbers
      ownedVolumes = books.map((_: any, i: number) => i + 1);
    }

    // Create the collection
    const collection = await insertCollection({
      library_id,
      name,
      author: author || null,
      book_type: (book_type as BookType) || "livre",
      cover_url: cover_url || null,
      owned_volumes: ownedVolumes,
    });

    // Link books to collection and set series_name
    await Promise.all(
      books.map((b: any, i: number) =>
        patchBook(b.id, {
          series_name: name,
          series_index: b.series_index || (i + 1),
        })
      )
    );

    return NextResponse.json({ collection, books_updated: books.length });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
