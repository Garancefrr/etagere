import { NextRequest, NextResponse } from "next/server";
import { getBooks, getBook, patchBook, removeBook, resolveCollection, findCollection, removeVolumeFromCollection } from "@/lib/db";
import { BookType } from "@/types";

export async function GET(req: NextRequest) {
  const library_id = req.nextUrl.searchParams.get("library_id");
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
  try {
    return NextResponse.json(await getBooks(library_id));
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function PATCH(req: NextRequest) {
  try {
    const { id, library_id, ...updates } = await req.json();
    if (!id) return NextResponse.json({ error: "id manquant" }, { status: 400 });

    // If series_name and series_index are being updated, sync the collection
    if (library_id && updates.series_name && updates.series_index) {
      try {
        const bookType = (updates.book_type ?? "bd") as BookType;
        if (bookType === "bd" || bookType === "manga") {
          await resolveCollection(
            library_id,
            updates.series_name,
            updates.series_index,
            { book_type: bookType }
          );
        }
      } catch (e) {
        console.error("Collection sync error:", e);
      }
    }

    await patchBook(id, updates);
    return NextResponse.json({ ok: true });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function DELETE(req: NextRequest) {
  try {
    const { id } = await req.json();
    if (!id) return NextResponse.json({ error: "id manquant" }, { status: 400 });

    // Get book details before deleting to sync collection
    const book = await getBook(id);
    if (book?.series_name && book.series_index && book.library_id) {
      const collection = await findCollection(book.library_id, book.series_name);
      if (collection) {
        await removeVolumeFromCollection(collection.id, collection.owned_volumes, book.series_index);
      }
    }

    await removeBook(id);
    return NextResponse.json({ ok: true });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
