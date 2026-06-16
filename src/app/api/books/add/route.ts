import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { insertBook } from "@/lib/db";
import { Book } from "@/types";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as Omit<Book, "id" | "added_at" | "updated_at"> & { email?: string };
    const { email, ...bookData } = body;

    // Resolve added_by: email → profile UUID
    if (email) {
      const profileId = await getProfileId(email);
      if (profileId) bookData.added_by = profileId;
    }

    const book = await insertBook(bookData);
    return NextResponse.json(book);
  } catch (e: any) {
    console.error("POST /api/books/add:", e);
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

