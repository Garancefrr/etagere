import { NextRequest, NextResponse } from "next/server";
import { getProfileId } from "@/lib/auth";
import { getSharedWithMe } from "@/lib/db";

export async function GET(req: NextRequest) {
  const email = req.nextUrl.searchParams.get("email");
  if (!email) return NextResponse.json([]);
  const profile_id = await getProfileId(email);
  if (!profile_id) return NextResponse.json([]);
  return NextResponse.json(await getSharedWithMe(profile_id));
}

