import { NextRequest, NextResponse } from "next/server";
import { insertBook } from "@/lib/db";
import { Book } from "@/types";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as Omit<Book, "id" | "added_at" | "updated_at">;
    // added_by must be a UUID — if it looks like an email, fetch the profile_id
    if (body.added_by && body.added_by.includes("@")) {
      const { createServerClient } = await import("@/lib/supabase");
      const db = createServerClient();
      const { data } = await db.from("profiles").select("id").eq("email", body.added_by).maybeSingle();
      if (data) body.added_by = data.id;
      else body.added_by = body.library_id; // fallback
    }
    const book = await insertBook(body);
    return NextResponse.json(book);
  } catch (e: any) {
    console.error("Insert book error:", e);
    return NextResponse.json({ error: e.message ?? "Erreur lors de l'ajout" }, { status: 500 });
  }
}
