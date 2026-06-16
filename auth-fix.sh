#!/bin/bash
set -e
echo "🔧 Fix auth — email cohérent partout..."
cd "$(git rev-parse --show-toplevel)"
cat > "src/app/api/library/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const email = req.nextUrl.searchParams.get("email");
  if (!email) return NextResponse.json({ error: "email manquant" }, { status: 400 });

  const db = createServerClient();

  // Find or create profile
  let { data: profile } = await db
    .from("profiles").select("id").eq("email", email).maybeSingle();

  if (!profile) {
    const { data: newProfile } = await db
      .from("profiles")
      .insert({ id: crypto.randomUUID(), email, name: email.split("@")[0] })
      .select("id").single();
    profile = newProfile;
  }

  if (!profile) return NextResponse.json({ error: "Profil introuvable" }, { status: 404 });

  // Find or create library
  let { data: library } = await db
    .from("libraries").select("id").eq("owner_id", profile.id).maybeSingle();

  if (!library) {
    const { data: newLib } = await db
      .from("libraries")
      .insert({ owner_id: profile.id, name: "Ma Bibliothèque" })
      .select("id").single();
    library = newLib;
  }

  if (!library) return NextResponse.json({ error: "Bibliothèque introuvable" }, { status: 404 });

  // Return both library_id and profile_id
  return NextResponse.json({ id: library.id, profile_id: profile.id });
}
FILEOF
cat > "src/app/api/collections/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getCollections, insertCollection } from "@/lib/db";
import { Collection } from "@/types";

export async function GET(req: NextRequest) {
  const libraryId = req.nextUrl.searchParams.get("library_id");
  if (!libraryId) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
  try {
    const collections = await getCollections(libraryId);
    return NextResponse.json(collections);
  } catch (e: any) {
    console.error("/api/collections GET:", e);
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as Omit<Collection, "id" | "created_at" | "updated_at">;
    if (!body.library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
    const collection = await insertCollection(body);
    return NextResponse.json(collection);
  } catch (e: any) {
    console.error("/api/collections POST:", e);
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
FILEOF
cat > "src/app/api/share/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@/lib/supabase";
import { createShare, getShareByToken, registerViewer } from "@/lib/db";

export async function POST(req: NextRequest) {
  const { collection_id, owner_id } = await req.json();
  if (!collection_id || !owner_id)
    return NextResponse.json({ error: "Paramètres manquants" }, { status: 400 });
  try {
    const token = await createShare(collection_id, owner_id);
    return NextResponse.json({ token });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function GET(req: NextRequest) {
  const token        = req.nextUrl.searchParams.get("token");
  const viewer_email = req.nextUrl.searchParams.get("viewer_email");
  if (!token) return NextResponse.json({ error: "Token manquant" }, { status: 400 });

  try {
    const share = await getShareByToken(token);
    if (!share) return NextResponse.json({ error: "Lien invalide ou expiré" }, { status: 404 });

    // Register viewer by email if provided
    if (viewer_email) {
      const db = createServerClient();
      const { data: profile } = await db
        .from("profiles").select("id").eq("email", viewer_email).maybeSingle();
      if (profile) await registerViewer(share.id, profile.id);
    }

    return NextResponse.json(share);
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
FILEOF
cat > "src/app/api/shared-with-me/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@/lib/supabase";
import { getSharedWithMe } from "@/lib/db";

export async function GET(req: NextRequest) {
  const email = req.nextUrl.searchParams.get("email");
  if (!email) return NextResponse.json({ error: "email manquant" }, { status: 400 });

  const db = createServerClient();
  const { data: profile } = await db
    .from("profiles").select("id").eq("email", email).maybeSingle();

  if (!profile) return NextResponse.json([]);

  const shared = await getSharedWithMe(profile.id);
  return NextResponse.json(shared);
}
FILEOF
cat > "src/app/collections/page.tsx" << 'FILEOF'
"use client";
import { useState, useEffect } from "react";
import { useSession } from "next-auth/react";
import { Collection, BookType } from "@/types";
import CollectionCard from "@/components/collection/CollectionCard";
import BottomNav from "@/components/layout/BottomNav";
import { Button } from "@/components/ui/Button";
import { Search, Plus, X, Share2, Check, MessageCircle } from "lucide-react";

function CreateModal({ onClose, onCreate }: {
  onClose: () => void;
  onCreate: (c: Partial<Collection>) => void;
}) {
  const [name,   setName]   = useState("");
  const [type,   setType]   = useState<BookType>("livre");
  const [author, setAuthor] = useState("");
  const [total,  setTotal]  = useState("");

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-5">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Nouvelle collection</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}>
            <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
          </button>
        </div>
        <div className="space-y-4">
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Nom</label>
            <input type="text" value={name} onChange={e => setName(e.target.value)} placeholder="Ex: Saga Dune, Astérix..."
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Type</label>
            <div className="flex gap-2">
              {(["livre","bd","manga"] as BookType[]).map(t => (
                <button key={t} onClick={() => setType(t)} className="flex-1 py-2.5 rounded-xl font-semibold"
                  style={{ fontSize: 13, background: type === t ? "var(--accent)" : "var(--surface2)", color: type === t ? "#fff" : "var(--txt2)", border: `1px solid ${type === t ? "var(--accent)" : "var(--border)"}` }}>
                  {t === "livre" ? "📖 Livre" : t === "bd" ? "🎨 BD" : "⛩️ Manga"}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Auteur (optionnel)</label>
            <input type="text" value={author} onChange={e => setAuthor(e.target.value)} placeholder="Ex: Frank Herbert..."
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Nombre de tomes (optionnel)</label>
            <input type="number" value={total} onChange={e => setTotal(e.target.value)} placeholder="Ex: 40"
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>
          <Button onClick={() => { if (name.trim()) { onCreate({ name: name.trim(), book_type: type, author: author.trim() || undefined, total_volumes: total ? parseInt(total) : undefined, owned_volumes: [] }); onClose(); }}}
            className="w-full py-4 rounded-2xl" style={{ fontSize: 15 }}>
            Créer la collection
          </Button>
        </div>
      </div>
    </div>
  );
}

function ShareModal({ collection, profileId, onClose }: {
  collection: Collection;
  profileId: string;
  onClose: () => void;
}) {
  const [link,    setLink]    = useState<string | null>(null);
  const [copied,  setCopied]  = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/share", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ collection_id: collection.id, owner_id: profileId }),
    })
      .then(r => r.json())
      .then(d => setLink(`${window.location.origin}/share/${d.token}`))
      .finally(() => setLoading(false));
  }, [collection.id, profileId]);

  const copy = () => {
    if (!link) return;
    navigator.clipboard.writeText(link);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const shareVia = (method: "whatsapp" | "sms") => {
    if (!link) return;
    const text = `👀 Regarde ma collection "${collection.name}" sur Folio : ${link}`;
    if (method === "whatsapp") window.open(`https://wa.me/?text=${encodeURIComponent(text)}`);
    else window.open(`sms:?body=${encodeURIComponent(text)}`);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Partager la collection</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}>
            <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
          </button>
        </div>
        {loading ? (
          <div className="flex justify-center py-6">
            <div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            <div className="px-3 py-2.5 rounded-xl truncate" style={{ background: "var(--surface2)", border: "1px solid var(--border)", fontSize: 12, color: "var(--txt3)" }}>{link}</div>
            <button onClick={() => shareVia("whatsapp")}
              className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3 active:scale-95"
              style={{ background: "#25D366", color: "#fff", fontSize: 15 }}>
              <MessageCircle className="w-5 h-5" /> WhatsApp
            </button>
            <button onClick={() => shareVia("sms")}
              className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3 active:scale-95"
              style={{ background: "var(--surface2)", color: "var(--txt1)", fontSize: 15, border: "1px solid var(--border)" }}>
              <MessageCircle className="w-5 h-5" /> SMS / iMessage
            </button>
            <button onClick={copy}
              className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3 active:scale-95"
              style={{ background: copied ? "var(--have-bg)" : "var(--accent-l)", color: copied ? "var(--have-t)" : "var(--accent)", fontSize: 15, border: `1px solid ${copied ? "var(--have-b)" : "var(--border)"}` }}>
              {copied ? <Check className="w-5 h-5" /> : <Share2 className="w-5 h-5" />}
              {copied ? "Lien copié !" : "Copier le lien"}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

type Filter = "all" | "bd" | "manga" | "livre";

export default function CollectionsPage() {
  const { data: session }                      = useSession();
  const [collections,     setCollections]      = useState<Collection[]>([]);
  const [libraryId,       setLibraryId]        = useState<string | null>(null);
  const [profileId,       setProfileId]        = useState<string | null>(null);
  const [loading,         setLoading]          = useState(true);
  const [search,          setSearch]           = useState("");
  const [filter,          setFilter]           = useState<Filter>("all");
  const [showCreate,      setShowCreate]       = useState(false);
  const [shareCollection, setShareCollection]  = useState<Collection | null>(null);

  useEffect(() => {
    if (!session?.user?.email) return;
    fetch(`/api/library?email=${session.user.email}`)
      .then(r => r.json())
      .then(({ id, profile_id }) => {
        setLibraryId(id);
        setProfileId(profile_id);
        return fetch(`/api/collections?library_id=${id}`);
      })
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setCollections(d) : [])
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [session]);

  const handleCreate = (data: Partial<Collection>) => {
    if (!libraryId) return;
    // Save to DB
    fetch("/api/collections", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...data, library_id: libraryId }),
    })
      .then(r => r.json())
      .then(c => setCollections(prev => [c, ...prev]))
      .catch(() => {});
  };

  const filtered = collections.filter(c => {
    const s = !search || c.name.toLowerCase().includes(search.toLowerCase()) || c.author?.toLowerCase().includes(search.toLowerCase());
    const f = filter === "all" || c.book_type === filter;
    return s && f;
  });

  return (
    <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="sticky top-0 z-30 px-4 pt-12 pb-3" style={{ background: "var(--bg)" }}>
        <div className="flex items-center justify-between mb-4">
          <div>
            <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Collections</p>
            <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>
              {collections.length} <span style={{ fontSize: 16, fontWeight: 400, opacity: 0.35 }}>séries</span>
            </h1>
          </div>
          <button onClick={() => setShowCreate(true)}
            className="w-11 h-11 rounded-2xl flex items-center justify-center active:scale-95"
            style={{ background: "var(--accent)" }}>
            <Plus className="w-5 h-5 text-white" />
          </button>
        </div>
        <div className="flex items-center gap-2 px-4 py-3 rounded-2xl mb-3"
          style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          <Search className="w-5 h-5" style={{ color: "var(--txt3)" }} />
          <input type="text" value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Rechercher..." className="flex-1 outline-none bg-transparent"
            style={{ color: "var(--txt1)", fontSize: 15 }} />
        </div>
        <div className="flex gap-2 overflow-x-auto pb-1" style={{ scrollbarWidth: "none" }}>
          {(["all","livre","bd","manga"] as Filter[]).map(f => (
            <button key={f} onClick={() => setFilter(f)}
              className="flex-shrink-0 px-4 py-2 rounded-full font-semibold"
              style={{ fontSize: 13, background: filter === f ? "var(--accent)" : "var(--surface)", color: filter === f ? "#fff" : "var(--txt2)", border: `1px solid ${filter === f ? "var(--accent)" : "var(--border)"}` }}>
              {f === "all" ? "Toutes" : f === "livre" ? "📖 Livres" : f === "bd" ? "🎨 BD" : "⛩️ Manga"}
            </button>
          ))}
        </div>
      </div>

      <div className="px-4 flex flex-col gap-4">
        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center py-20 gap-4">
            <p className="font-semibold" style={{ fontSize: 17, color: "var(--txt1)" }}>Aucune collection</p>
            <Button onClick={() => setShowCreate(true)}>+ Créer une collection</Button>
          </div>
        ) : filtered.map(c => (
          <div key={c.id}>
            <CollectionCard collection={c} />
            <button onClick={() => setShareCollection(c)}
              className="w-full mt-2 py-3 rounded-2xl font-semibold flex items-center justify-center gap-2 active:scale-95"
              style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt2)", fontSize: 13 }}>
              <Share2 className="w-4 h-4" style={{ color: "var(--accent)" }} />
              Partager cette collection
            </button>
          </div>
        ))}
      </div>

      {showCreate && <CreateModal onClose={() => setShowCreate(false)} onCreate={handleCreate} />}
      {shareCollection && profileId && (
        <ShareModal collection={shareCollection} profileId={profileId} onClose={() => setShareCollection(null)} />
      )}
      <BottomNav />
    </div>
  );
}
FILEOF
cat > "src/app/settings/page.tsx" << 'FILEOF'
"use client";
import { useState, useEffect } from "react";
import { useSession, signOut } from "next-auth/react";
import BottomNav from "@/components/layout/BottomNav";
import { useTheme } from "@/components/layout/ThemeProvider";
import { Toggle } from "@/components/ui/Toggle";
import { Cover } from "@/components/ui/Cover";
import { SharedWithMe } from "@/lib/db";
import { Moon, LogOut, ChevronRight, Gift, BookOpen } from "lucide-react";

export default function SettingsPage() {
  const { data: session } = useSession();
  const { theme, toggle } = useTheme();
  const [shared, setShared] = useState<SharedWithMe[]>([]);

  useEffect(() => {
    if (!session?.user?.email) return;
    fetch(`/api/shared-with-me?email=${session.user.email}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setShared(d) : [])
      .catch(() => {});
  }, [session]);

  const userName = session?.user?.name ?? "Utilisateur";

  return (
    <div className="min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="px-4 pt-12 pb-4">
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Compte</p>
        <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>Réglages</h1>
      </div>

      {/* Profile */}
      <div className="mx-4 mb-4 p-4 rounded-2xl flex items-center gap-3" style={{ background: "var(--accent)" }}>
        {session?.user?.image
          ? <img src={session.user.image} alt="" className="w-14 h-14 rounded-2xl flex-shrink-0 object-cover" />
          : <div className="w-14 h-14 rounded-2xl flex items-center justify-center font-bold flex-shrink-0"
              style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>{userName[0]}</div>}
        <div className="min-w-0">
          <p className="font-bold text-white truncate" style={{ fontSize: 17 }}>{userName}</p>
          <p className="truncate" style={{ color: "rgba(255,255,255,0.65)", fontSize: 13 }}>{session?.user?.email}</p>
        </div>
      </div>

      {/* Bibliothèques partagées */}
      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5 flex items-center gap-2" style={{ borderBottom: "1px solid var(--border)" }}>
          <Gift className="w-4 h-4" style={{ color: "var(--accent)" }} />
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>
            Bibliothèques partagées
          </span>
        </div>
        {shared.length === 0 ? (
          <div className="px-4 py-6 flex flex-col items-center gap-2">
            <BookOpen className="w-8 h-8" style={{ color: "var(--txt3)", opacity: 0.3 }} />
            <p className="text-center" style={{ fontSize: 14, color: "var(--txt3)" }}>
              Personne n&apos;a encore partagé de collection avec toi
            </p>
          </div>
        ) : shared.map(lib => (
          <a key={lib.token} href={`/share/${lib.token}`}
            className="flex items-center gap-3 px-4 py-3.5 active:opacity-70"
            style={{ borderTop: "1px solid var(--border)", textDecoration: "none" }}>
            <Cover src={lib.cover_url} alt={lib.collection_name} width={44} height={60} className="rounded-xl flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="font-semibold truncate" style={{ fontSize: 15, color: "var(--txt1)" }}>
                {lib.collection_name}{" "}
                <span style={{ fontWeight: 400, opacity: 0.5 }}>de {lib.owner_name}</span>
              </p>
              <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>
                {lib.owned_volumes.length}{lib.total_volumes ? `/${lib.total_volumes}` : ""} tomes
              </p>
            </div>
            <ChevronRight className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          </a>
        ))}
      </div>

      {/* Préférences */}
      <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="px-4 py-2.5" style={{ borderBottom: "1px solid var(--border)" }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Préférences</span>
        </div>
        <div className="flex items-center gap-3 px-4 py-4">
          <Moon className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
          <div className="flex-1">
            <p style={{ fontSize: 15, fontWeight: 500, color: "var(--txt1)" }}>Mode sombre</p>
            <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{"Thème de l'interface"}</p>
          </div>
          <Toggle checked={theme === "dark"} onChange={() => toggle()} label="Basculer mode sombre" />
        </div>
      </div>

      {/* Déconnexion */}
      <button onClick={() => signOut({ callbackUrl: "/login" })}
        className="mx-4 py-4 rounded-2xl flex items-center justify-center gap-2 active:scale-95"
        style={{ width: "calc(100% - 2rem)", background: "var(--miss-bg)", border: "1px solid var(--miss-b)" }}>
        <LogOut className="w-5 h-5" style={{ color: "var(--miss-t)" }} />
        <span style={{ fontSize: 15, fontWeight: 700, color: "var(--miss-t)" }}>Se déconnecter</span>
      </button>

      <p className="text-center mt-4" style={{ fontSize: 12, color: "var(--txt3)", opacity: 0.4 }}>Folio · v1.0.0</p>
      <BottomNav />
    </div>
  );
}
FILEOF
cat > "src/app/share/[token]/page.tsx" << 'FILEOF'
"use client";
import { useEffect, useState } from "react";
import { useSession } from "next-auth/react";
import { useParams, useRouter } from "next/navigation";
import { Collection } from "@/types";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";
import { LogIn } from "lucide-react";

interface ShareData { id: string; collection: Collection; owner_name: string; }

export default function SharedCollectionPage() {
  const { token }                         = useParams<{ token: string }>();
  const { data: session, status }         = useSession();
  const router                            = useRouter();
  const [data,    setData]                = useState<ShareData | null>(null);
  const [loading, setLoading]             = useState(true);
  const [error,   setError]               = useState<string | null>(null);

  useEffect(() => {
    if (status === "loading") return;
    const viewer_email = session?.user?.email ?? "";
    fetch(`/api/share?token=${token}&viewer_email=${viewer_email}`)
      .then(r => r.json())
      .then(d => { if (d.error) setError(d.error); else setData(d); })
      .catch(() => setError("Erreur de connexion"))
      .finally(() => setLoading(false));
  }, [token, session, status]);

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center" style={{ background: "var(--bg)" }}>
      <div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
    </div>
  );

  if (error || !data) return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4 px-6" style={{ background: "var(--bg)" }}>
      <p className="font-bold text-lg" style={{ color: "var(--txt1)" }}>Lien invalide ou expiré</p>
      <Button onClick={() => router.push("/library")}>Aller à ma bibliothèque</Button>
    </div>
  );

  const { collection, owner_name } = data;
  const owned   = collection.owned_volumes ?? [];
  const total   = collection.total_volumes ?? 0;
  const missing = total > 0 ? Array.from({ length: total }, (_, i) => i + 1).filter(n => !owned.includes(n)) : [];
  const pct     = total > 0 ? Math.round((owned.length / total) * 100) : 0;

  return (
    <div className="min-h-screen pb-10" style={{ background: "var(--bg)" }}>
      <div className="px-5 pt-14 pb-6" style={{ background: "var(--accent)" }}>
        <p style={{ color: "rgba(255,255,255,0.65)", fontSize: 13 }}>Collection de</p>
        <h1 className="text-3xl font-bold text-white mt-1">{owner_name}</h1>
        <p style={{ color: "rgba(255,255,255,0.75)", fontSize: 14, marginTop: 4 }}>{collection.name}</p>
      </div>

      {!session && (
        <div className="mx-4 -mt-4 mb-6 p-4 rounded-2xl shadow-sm"
          style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          <div className="flex items-start gap-3">
            <div className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0" style={{ background: "var(--accent-l)" }}>
              <LogIn className="w-5 h-5" style={{ color: "var(--accent)" }} />
            </div>
            <div className="flex-1">
              <p className="font-semibold" style={{ fontSize: 14, color: "var(--txt1)" }}>Connecte-toi pour sauvegarder</p>
              <Button onClick={() => router.push(`/login?callbackUrl=/share/${token}`)} className="mt-3 px-4 py-2 rounded-xl" size="sm">
                Se connecter avec Google
              </Button>
            </div>
          </div>
        </div>
      )}

      {session && (
        <div className="mx-4 -mt-4 mb-6 p-3 rounded-2xl"
          style={{ background: "var(--have-bg)", border: "1px solid var(--have-b)" }}>
          <p style={{ fontSize: 14, color: "var(--have-t)", fontWeight: 600 }}>✅ Ajoutée à vos bibliothèques partagées</p>
        </div>
      )}

      {/* Collection */}
      <div className="mx-4 mb-4 rounded-2xl overflow-hidden" style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="flex gap-3 p-4">
          <Cover src={collection.cover_url} alt={collection.name} width={56} height={78} className="rounded-xl flex-shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="font-bold" style={{ fontSize: 16, color: "var(--txt1)" }}>{collection.name}</p>
            {collection.author && <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{collection.author}</p>}
            <div className="flex items-center gap-2 mt-3">
              <div className="flex-1 h-2 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
                <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
              </div>
              <span className="font-bold" style={{ fontSize: 13, color: "var(--accent)" }}>{owned.length}{total ? `/${total}` : ""}</span>
            </div>
          </div>
        </div>
        {total > 0 && (
          <div className="flex flex-wrap gap-1.5 px-4 pb-4">
            {Array.from({ length: Math.min(total, 30) }, (_, i) => i + 1).map(n => (
              <div key={n} className="flex items-center justify-center font-bold"
                style={{ width: 30, height: 30, borderRadius: 8, fontSize: 11,
                  background: owned.includes(n) ? "var(--have-bg)" : "var(--miss-bg)",
                  color:      owned.includes(n) ? "var(--have-t)"  : "var(--miss-t)",
                  border:     owned.includes(n) ? "1px solid var(--have-b)" : "1px dashed var(--miss-b)" }}>
                {n}
              </div>
            ))}
          </div>
        )}
      </div>

      {missing.length > 0 && (
        <div className="mx-4">
          <p className="font-bold mb-3" style={{ fontSize: 15, color: "var(--txt1)" }}>
            {missing.length} tome{missing.length > 1 ? "s" : ""} manquant{missing.length > 1 ? "s" : ""}
          </p>
          <div className="flex flex-wrap gap-2">
            {missing.map(n => (
              <div key={n} className="px-3 py-1.5 rounded-xl font-semibold"
                style={{ background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px dashed var(--miss-b)", fontSize: 13 }}>
                Tome {n}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
FILEOF
git add -A
git commit -m "fix: use email consistently across all pages and API routes"
git push
echo "🎉 Déployé !"
