import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const job_id = req.nextUrl.searchParams.get("job_id");
  if (!job_id) return NextResponse.json({ error: "job_id manquant" }, { status: 400 });

  const db = createServerClient();
  const { data } = await db
    .from("import_jobs")
    .select("*")
    .eq("id", job_id)
    .maybeSingle();

  if (!data) return NextResponse.json({ error: "Job introuvable" }, { status: 404 });
  return NextResponse.json(data);
}
