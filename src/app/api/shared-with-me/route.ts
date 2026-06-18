import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { getSharedWithMe } from "@/lib/db";

export async function GET(req: NextRequest) {
  const email = req.nextUrl.searchParams.get("email");
  if (!email) return NextResponse.json({ error: "email manquant" }, { status: 400 });
  try {
    const profileId = await getProfileId(email);
    if (!profileId) return NextResponse.json([]);
    return NextResponse.json(await getSharedWithMe(profileId));
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
