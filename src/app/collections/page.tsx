"use client";
import { useState, useEffect } from "react";
import { Collection, BookType } from "@/types";
import { useLibrary } from "@/hooks/useLibrary";
import CollectionCard from "@/components/collection/CollectionCard";
import BottomNav from "@/components/layout/BottomNav";
import { Button } from "@/components/ui/Button";
import { Search, Plus, X, Share2, Check, MessageCircle } from "lucide-react";

function CreateModal({ onClose, onCreate }: { onClose: () => void; onCreate: (c: Partial<Collection>) => void }) {
  const [name, setName]     = useState("");
  const [type, setType]     = useState<BookType>("livre");
  const [author, setAuthor] = useState("");
  const [total, setTotal]   = useState("");
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-5">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Nouvelle collection</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}><X className="w-4 h-4" style={{ color: "var(--txt2)" }} /></button>
        </div>
        <div className="space-y-4">
          {[
            { label: "Nom", el: <input type="text" value={name} onChange={e => setName(e.target.value)} placeholder="Ex: Astérix, Saga Dune..." className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} /> },
            { label: "Auteur (optionnel)", el: <input type="text" value={author} onChange={e => setAuthor(e.target.value)} placeholder="Ex: Goscinny..." className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} /> },
            { label: "Nombre de tomes (optionnel)", el: <input type="number" value={total} onChange={e => setTotal(e.target.value)} placeholder="Ex: 40" className="w-full px-4 py-3 rounded-2xl outline-none" style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} /> },
          ].map(({ label, el }) => (
            <div key={label}>
              <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>{label}</label>
              {el}
            </div>
          ))}
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
          <Button onClick={() => { if (name.trim()) { onCreate({ name: name.trim(), book_type: type, author: author.trim() || undefined, total_volumes: total ? parseInt(total) : undefined, owned_volumes: [] }); onClose(); }}} className="w-full py-4 rounded-2xl" style={{ fontSize: 15 }}>
            Créer
          </Button>
        </div>
      </div>
    </div>
  );
}

function ShareModal({ collection, profileId, onClose }: { collection: Collection; profileId: string; onClose: () => void }) {
  const [link, setLink]     = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    fetch("/api/share", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ collection_id: collection.id, profile_id: profileId }) })
      .then(r => r.json()).then(d => setLink(`${window.location.origin}/share/${d.token}`));
  }, [collection.id, profileId]);
  const copy = () => { if (!link) return; navigator.clipboard.writeText(link); setCopied(true); setTimeout(() => setCopied(false), 2000); };
  const shareVia = (m: "whatsapp"|"sms") => { if (!link) return; const t = `👀 Regarde ma collection "${collection.name}" sur Folio : ${link}`; window.open(m === "whatsapp" ? `https://wa.me/?text=${encodeURIComponent(t)}` : `sms:?body=${encodeURIComponent(t)}`); };
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Partager</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}><X className="w-4 h-4" style={{ color: "var(--txt2)" }} /></button>
        </div>
        {!link ? <div className="flex justify-center py-6"><div className="w-6 h-6 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} /></div> : (
          <div className="flex flex-col gap-3">
            <div className="px-3 py-2 rounded-xl truncate" style={{ background: "var(--surface2)", border: "1px solid var(--border)", fontSize: 12, color: "var(--txt3)" }}>{link}</div>
            <button onClick={() => shareVia("whatsapp")} className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3" style={{ background: "#25D366", color: "#fff", fontSize: 15 }}><MessageCircle className="w-5 h-5" /> WhatsApp</button>
            <button onClick={() => shareVia("sms")} className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3" style={{ background: "var(--surface2)", color: "var(--txt1)", fontSize: 15, border: "1px solid var(--border)" }}><MessageCircle className="w-5 h-5" /> SMS / iMessage</button>
            <button onClick={copy} className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3" style={{ background: copied ? "var(--have-bg)" : "var(--accent-l)", color: copied ? "var(--have-t)" : "var(--accent)", fontSize: 15 }}>
              {copied ? <Check className="w-5 h-5" /> : <Share2 className="w-5 h-5" />}{copied ? "Copié !" : "Copier le lien"}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

type Filter = "all" | "bd" | "manga" | "livre";

export default function CollectionsPage() {
  const { library_id, profile_id, loading: libLoading } = useLibrary();
  const [collections,     setCollections]    = useState<Collection[]>([]);
  const [colLoading,      setColLoading]     = useState(false);
  const [search,          setSearch]         = useState("");
  const [filter,          setFilter]         = useState<Filter>("all");
  const [showCreate,      setShowCreate]     = useState(false);
  const [shareCol,        setShareCol]       = useState<Collection | null>(null);
  const [editCol,         setEditCol]        = useState<Collection | null>(null);
  const [deleteId,        setDeleteId]       = useState<string | null>(null);

  useEffect(() => {
    if (!library_id) return;
    setColLoading(true);
    fetch(`/api/collections?library_id=${library_id}`)
      .then(r => r.json())
      .then(d => Array.isArray(d) ? setCollections(d) : [])
      .catch(console.error)
      .finally(() => setColLoading(false));
  }, [library_id]);

  const handleCreate = async (data: Partial<Collection>) => {
    if (!library_id) return;
    const res = await fetch("/api/collections", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...data, library_id, owned_volumes: data.owned_volumes ?? [] }) });
    if (res.ok) { const col = await res.json(); setCollections(prev => [col, ...prev]); }
  };

  const handleEdit = async (id: string, updates: Partial<Collection>) => {
    await fetch("/api/collections", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id, ...updates }) });
    setCollections(prev => prev.map(c => c.id === id ? { ...c, ...updates } : c));
    setEditCol(null);
  };

  const handleDelete = async (id: string) => {
    await fetch("/api/collections", { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id }) });
    setCollections(prev => prev.filter(c => c.id !== id));
    setDeleteId(null);
  };

  const filtered = collections.filter(c =>
    (filter === "all" || c.book_type === filter) &&
    (!search || c.name.toLowerCase().includes(search.toLowerCase()) || c.author?.toLowerCase().includes(search.toLowerCase()))
  );

  const loading = libLoading || colLoading;

  return (
    <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>
      <div className="sticky top-0 z-30 px-4 pt-12 pb-3" style={{ background: "var(--bg)" }}>
        <div className="flex items-center justify-between mb-4">
          <div>
            <p style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", textTransform: "uppercase", letterSpacing: "0.14em" }}>Collections</p>
            <h1 className="font-bold" style={{ fontSize: 26, color: "var(--txt1)" }}>{collections.length} <span style={{ fontSize: 16, fontWeight: 400, opacity: 0.35 }}>séries</span></h1>
          </div>
          <button onClick={() => setShowCreate(true)} className="w-11 h-11 rounded-2xl flex items-center justify-center active:scale-95" style={{ background: "var(--accent)" }}><Plus className="w-5 h-5 text-white" /></button>
        </div>
        <div className="flex items-center gap-2 px-4 py-3 rounded-2xl mb-3" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          <Search className="w-5 h-5" style={{ color: "var(--txt3)" }} />
          <input type="text" value={search} onChange={e => setSearch(e.target.value)} placeholder="Rechercher..." className="flex-1 outline-none bg-transparent" style={{ color: "var(--txt1)", fontSize: 15 }} />
        </div>
        <div className="flex gap-2 overflow-x-auto pb-1" style={{ scrollbarWidth: "none" }}>
          {(["all","livre","bd","manga"] as Filter[]).map(f => (
            <button key={f} onClick={() => setFilter(f)} className="flex-shrink-0 px-4 py-2 rounded-full font-semibold"
              style={{ fontSize: 13, background: filter === f ? "var(--accent)" : "var(--surface)", color: filter === f ? "#fff" : "var(--txt2)", border: `1px solid ${filter === f ? "var(--accent)" : "var(--border)"}` }}>
              {f === "all" ? "Toutes" : f === "livre" ? "📖 Livres" : f === "bd" ? "🎨 BD" : "⛩️ Manga"}
            </button>
          ))}
        </div>
      </div>

      <div className="px-4 flex flex-col gap-4">
        {loading ? (
          <div className="flex justify-center py-20"><div className="w-8 h-8 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} /></div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center py-20 gap-4">
            <p className="font-semibold" style={{ fontSize: 17, color: "var(--txt1)" }}>Aucune collection</p>
            <Button onClick={() => setShowCreate(true)}>+ Créer une collection</Button>
          </div>
        ) : filtered.map(c => (
          <div key={c.id}>
            <CollectionCard
              collection={c}
              onEdit={() => setEditCol(c)}
              onDelete={() => setDeleteId(c.id)}
            />
            {deleteId === c.id && (
              <div className="flex gap-2 mt-2">
                <button onClick={() => handleDelete(c.id)}
                  className="flex-1 py-3 rounded-2xl font-semibold"
                  style={{ background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px solid var(--miss-b)", fontSize: 13 }}>
                  Confirmer la suppression
                </button>
                <button onClick={() => setDeleteId(null)}
                  className="px-4 py-3 rounded-2xl font-semibold"
                  style={{ background: "var(--surface)", color: "var(--txt2)", border: "1px solid var(--border)", fontSize: 13 }}>
                  Annuler
                </button>
              </div>
            )}
            <button onClick={() => setShareCol(c)} className="w-full mt-2 py-3 rounded-2xl font-semibold flex items-center justify-center gap-2 active:scale-95"
              style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt2)", fontSize: 13 }}>
              <Share2 className="w-4 h-4" style={{ color: "var(--accent)" }} /> Partager cette collection
            </button>
          </div>
        ))}
      </div>

      {showCreate && <CreateModal onClose={() => setShowCreate(false)} onCreate={handleCreate} />}
      {editCol && <EditModal collection={editCol} onClose={() => setEditCol(null)} onSave={handleEdit} />}
      {shareCol && profile_id && <ShareModal collection={shareCol} profileId={profile_id} onClose={() => setShareCol(null)} />}
      <BottomNav />
    </div>
  );
}

function EditModal({ collection, onClose, onSave }: {
  collection: Collection;
  onClose: () => void;
  onSave: (id: string, updates: Partial<Collection>) => void;
}) {
  const [name,   setName]   = useState(collection.name);
  const [author, setAuthor] = useState(collection.author ?? "");
  const [total,  setTotal]  = useState(collection.total_volumes?.toString() ?? "");
  const [type,   setType]   = useState<BookType>(collection.book_type);

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4"><div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} /></div>
        <div className="flex items-center justify-between mb-5">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Modifier la collection</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}>
            <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
          </button>
        </div>
        <div className="space-y-4">
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Nom</label>
            <input type="text" value={name} onChange={e => setName(e.target.value)}
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Auteur</label>
            <input type="text" value={author} onChange={e => setAuthor(e.target.value)}
              className="w-full px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", display: "block", marginBottom: 6 }}>Nombre total de tomes</label>
            <input type="number" value={total} onChange={e => setTotal(e.target.value)}
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
          <Button onClick={() => {
            if (name.trim()) {
              onSave(collection.id, {
                name: name.trim(),
                author: author.trim() || undefined,
                total_volumes: total ? parseInt(total) : undefined,
                book_type: type,
              });
            }
          }} className="w-full py-4 rounded-2xl" style={{ fontSize: 15 }}>
            Enregistrer
          </Button>
        </div>
      </div>
    </div>
  );
}
