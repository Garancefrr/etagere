import { NextRequest, NextResponse } from "next/server";
import { getWishlist } from "@/lib/db";

export async function GET(req: NextRequest) {
  const id = req.nextUrl.searchParams.get("id");
  if (!id) return NextResponse.json({ error: "id manquant" }, { status: 400 });
  const wishlist = await getWishlist(id);
  if (!wishlist) return NextResponse.json({ error: "Wishlist introuvable" }, { status: 404 });
  return NextResponse.json(wishlist);
}
