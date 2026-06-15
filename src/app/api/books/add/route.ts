import { NextRequest, NextResponse } from "next/server";
import { insertBook } from "@/lib/db";
import { Book } from "@/types";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as Omit<Book, "id" | "added_at" | "updated_at">;
    const book = await insertBook(body);
    return NextResponse.json(book);
  } catch (e) {
    console.error("Insert book error:", e);
    return NextResponse.json({ error: "Erreur lors de l'ajout" }, { status: 500 });
  }
}
