import { NextRequest, NextResponse } from "next/server";
import { addBook } from "@/lib/data";
import { Book } from "@/types";

export async function POST(req: NextRequest) {
  const body = await req.json() as Omit<Book, "id" | "added_at" | "updated_at">;
  const book = addBook({ ...body, library_id: body.library_id ?? "lib1", added_by: body.added_by ?? "u1" });
  return NextResponse.json(book);
}
