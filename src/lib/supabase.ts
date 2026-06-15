import { createClient, SupabaseClient } from "@supabase/supabase-js";

const url  = process.env.NEXT_PUBLIC_SUPABASE_URL  ?? "";
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

// Client-side (uses anon key + RLS)
export const supabase: SupabaseClient = url && anon
  ? createClient(url, anon)
  : null as any;

// Server-side (uses service role key, bypasses RLS — API routes only)
export function createServerClient(): SupabaseClient {
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
  return url && serviceKey
    ? createClient(url, serviceKey, { auth: { persistSession: false } })
    : null as any;
}
