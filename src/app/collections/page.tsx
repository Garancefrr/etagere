"use client";
import { useState, useEffect } from "react";
import { useSession } from "next-auth/react";
import { Collection, BookType } from "@/types";
import CollectionCard from "@/components/collection/CollectionCard";
import BottomNav from "@/components/layout/BottomNav";
import { Button } from "@/components/ui/Button";
import { Search, Plus, X, Share2, Check, MessageCircle } from "lucide-react";

// ── Create modal ──────────────────────────────────────────────────────────────
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
          <Field label="Nom">
            <input type="text" value={name} onChange={e => setName(e.target.value)} placeholder="Ex: Saga Dune, Livres de Camus..."
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </Field>
          <Field label="Type">
            <div className="flex gap-2">
              {(["livre","bd","manga"] as BookType[]).map(t => (
                <button key={t} onClick={() => setType(t)} className="flex-1 py-2.5 rounded-xl font-semibold"
                  style={{ fontSize: 13, background: type === t ? "var(--accent)" : "var(--surface2)", color: type === t ? "#fff" : "var(--txt2)", border: `1px solid ${type === t ? "var(--accent)" : "var(--border)"}` }}>
                  {t === "livre" ? "📖 Livre" : t === "bd" ? "🎨 BD" : "⛩️ Manga"}
                </button>
              ))}
            </div>
          </Field>
          <Field label="Auteur (optionnel)">
            <input type="text" value={author} onChange={e => setAuthor(e.target.value)} placeholder="Ex: Frank Herbert..."
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </Field>
          <Field label="Nombre de tomes (optionnel)">
            <input type="number" value={total} onChange={e => setTotal(e.target.value)} placeholder="Ex: 7"
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </Field>
          <Button onClick={() => { if (name.trim()) { onCreate({ name: name.trim(), book_type: type, author: author.trim() || undefined, total_volumes: total ? parseInt(total) : undefined, owned_volumes: [] }); onClose(); }}}
            className="w-full py-4 rounded-2xl" style={{ fontSize: 15 }}>
            Créer la collection
          </Button>
        </div>
      </div>
    </div>
  );
}

// ── Share modal ───────────────────────────────────────────────────────────────
function ShareModal({ collection, ownerId, onClose }: {
  collection: Collection;
  ownerId: string;
  onClose: () => void;
}) {
  const [link,   setLink]   = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/share", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ collection_id: collection.id, owner_id: ownerId }),
    })
      .then(r => r.json())
      .then(d => setLink(`${window.location.origin}/share/${d.token}`))
      .finally(() => setLoading(false));
  }, [collection.id, ownerId]);

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
        <div className="flex items-center justify-between mb-2">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Partager la collection</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}>
            <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
          </button>
        </div>
        <p style={{ fontSize: 13, color: "var(--txt2)", marginBottom: 20 }}>
          La personne pourra <strong style={{ color: "var(--txt1)" }}>consulter</strong> ta collection en lecture seule après s&apos;être connectée.
        </p>

        {loading ? (
          <div className="flex justify-center py-6">
            <div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {/* Link preview */}
            <div className="px-3 py-2.5 rounded-xl truncate" style={{ background: "var(--surface2)", border: "1px solid var(--border)", fontSize: 12, color: "var(--txt3)" }}>
              {link}
            </div>
            <button onClick={() => shareVia("whatsapp")}
              className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3 active:scale-95"
              style={{ background: "#25D366", color: "#fff", fontSize: 15 }}>
              <MessageCircle className="w-5 h-5" /> Partager sur WhatsApp
            </button>
            <button onClick={() => shareVia("sms")}
              className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3 active:scale-95"
              style={{ background: "var(--surface2)", color: "var(--txt1)", fontSize: 15, border: "1px solid var(--border)" }}>
              <MessageCircle className="w-5 h-5" /> Envoyer par SMS / iMessage
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

// ── Page ──────────────────────────────────────────────────────────────────────
type Filter = "all" | "bd" | "manga" | "livre";

export default function CollectionsPage() {
  const { data: session } = useSession();
  const [collections,      setCollections]      = useState<Collection[]>([]);
  const [loading,          setLoading]          = useState(true);
  const [search,           setSearch]           = useState("");
  const [filter,           setFilter]           = useState<Filter>("all");
  const [showCreate,       setShowCreate]       = useState(false);
  const [shareCollection,  setShareCollection]  = useState<Collection | null>(null);

  useEffect(() => {
    if (!session?.user?.id) return;
    fetch(`/api/library?user_id=${session.user.id}`)
      .then(r => r.json())
      .then(({ id }) => fetch(`/api/collections?library_id=${id}`))
      .then(r => r.json())
      .then(setCollections)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [session]);

  const handleCreate = (data: Partial<Collection>) => {
    // Optimistic UI — real save would go through API
    setCollections(prev => [{
      id: `c_${Date.now()}`, library_id: "lib1",
      name: data.name!, book_type: data.book_type ?? "livre",
      author: data.author, total_volumes: data.total_volumes,
      owned_volumes: [], created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    }, ...prev]);
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
            placeholder="Rechercher une collection..."
            className="flex-1 outline-none bg-transparent"
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
            {/* Share button */}
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
      {shareCollection && session?.user?.id && (
        <ShareModal collection={shareCollection} ownerId={session.user.id} onClose={() => setShareCollection(null)} />
      )}
      <BottomNav />
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>{label}</label>
      {children}
    </div>
  );
}
