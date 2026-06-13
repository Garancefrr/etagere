import { NextRequest, NextResponse } from "next/server";
import { addBook } from "@/lib/store";
import { Book } from "@/types";

export async function POST(req: NextRequest) {
  const body = await req.json();
  const book = addBook({
    ...body,
    library_id: body.library_id ?? "lib1",
    added_by: body.added_by ?? "user1",
  } as Omit<Book, "id" | "added_at" | "updated_at">);
  return NextResponse.json(book);
}
