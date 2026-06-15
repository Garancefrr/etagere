"use client";
import { useState } from "react";
import { Collection, BookType } from "@/types";
import CollectionCard from "@/components/collection/CollectionCard";
import BottomNav from "@/components/layout/BottomNav";
import { Search, Plus, X, BookOpen, Share2, Gift, Check, MessageCircle } from "lucide-react";

const DEMO_COLLECTIONS: Collection[] = [
  { id:"c1",library_id:"lib1",name:"Astérix",author:"Goscinny & Uderzo",cover_url:"https://covers.openlibrary.org/b/isbn/9782205055375-M.jpg",book_type:"bd",total_volumes:40,owned_volumes:[1,2,3,4,5,8,10,12],created_at:"2024-01-01T00:00:00Z",updated_at:"2024-06-01T00:00:00Z"},
  { id:"c2",library_id:"lib1",name:"Naruto",author:"Masashi Kishimoto",cover_url:"https://covers.openlibrary.org/b/isbn/9782344009888-M.jpg",book_type:"manga",total_volumes:72,owned_volumes:[1,2,3,4,5,11,12],created_at:"2024-01-01T00:00:00Z",updated_at:"2024-06-01T00:00:00Z"},
  { id:"c3",library_id:"lib1",name:"Harry Potter",author:"J.K. Rowling",cover_url:"https://covers.openlibrary.org/b/isbn/9782012101562-M.jpg",book_type:"livre",total_volumes:7,owned_volumes:[1,2,3],created_at:"2024-01-01T00:00:00Z",updated_at:"2024-06-01T00:00:00Z"},
  { id:"c4",library_id:"lib1",name:"Albert Camus",author:"Albert Camus",book_type:"livre",owned_volumes:[],created_at:"2024-01-01T00:00:00Z",updated_at:"2024-06-01T00:00:00Z"},
];

type Filter = "all" | "bd" | "manga" | "livre";

// Modal: create new collection
function CreateModal({ onClose, onCreate }: {
  onClose: () => void;
  onCreate: (c: Partial<Collection>) => void;
}) {
  const [name, setName] = useState("");
  const [type, setType] = useState<BookType>("livre");
  const [author, setAuthor] = useState("");
  const [total, setTotal] = useState("");

  const submit = () => {
    if (!name.trim()) return;
    onCreate({ name: name.trim(), book_type: type, author: author.trim() || undefined, total_volumes: total ? parseInt(total) : undefined, owned_volumes: [] });
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>
        <div className="flex items-center justify-between mb-5">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Nouvelle collection</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}>
            <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
          </button>
        </div>

        <div className="space-y-4">
          {/* Name */}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em" }}>Nom</label>
            <input type="text" value={name} onChange={e => setName(e.target.value)}
              placeholder="Ex: Livres de Camus, Saga Dune..."
              className="w-full mt-1.5 px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>

          {/* Type */}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em" }}>Type</label>
            <div className="flex gap-2 mt-1.5">
              {(["livre","bd","manga"] as BookType[]).map(t => (
                <button key={t} onClick={() => setType(t)}
                  className="flex-1 py-2.5 rounded-xl font-semibold"
                  style={{ fontSize: 13, background: type === t ? "var(--accent)" : "var(--surface2)", color: type === t ? "#fff" : "var(--txt2)", border: `1px solid ${type === t ? "var(--accent)" : "var(--border)"}` }}>
                  {t === "livre" ? "📖 Livre" : t === "bd" ? "🎨 BD" : "⛩️ Manga"}
                </button>
              ))}
            </div>
          </div>

          {/* Author / organizer */}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em" }}>
              {type === "livre" ? "Auteur (optionnel)" : "Auteur / Éditeur"}
            </label>
            <input type="text" value={author} onChange={e => setAuthor(e.target.value)}
              placeholder="Ex: Albert Camus, Frank Herbert..."
              className="w-full mt-1.5 px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>

          {/* Total volumes (optional) */}
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em" }}>Nombre de tomes total (optionnel)</label>
            <input type="number" value={total} onChange={e => setTotal(e.target.value)}
              placeholder="Ex: 7"
              className="w-full mt-1.5 px-4 py-3 rounded-2xl outline-none"
              style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 15 }} />
          </div>

          <button onClick={submit}
            className="w-full py-4 rounded-2xl font-bold active:scale-95"
            style={{ background: "var(--accent)", color: "#fff", fontSize: 15 }}>
            Créer la collection
          </button>
        </div>
      </div>
    </div>
  );
}

// Modal: share wishlist
function ShareModal({ collection, onClose }: { collection: Collection; onClose: () => void }) {
  const [shared, setShared] = useState(false);
  const wishlistUrl = `${typeof window !== "undefined" ? window.location.origin : ""}/wishlist/wl_demo`;

  const missing = collection.total_volumes
    ? Array.from({ length: collection.total_volumes }, (_, i) => i + 1).filter(n => !collection.owned_volumes.includes(n))
    : [];

  const shareVia = (method: "whatsapp" | "sms" | "copy") => {
    const text = `🎁 Voici ma wishlist pour la collection "${collection.name}" — si tu veux m'offrir un tome manquant : ${wishlistUrl}`;
    if (method === "whatsapp") {
      window.open(`https://wa.me/?text=${encodeURIComponent(text)}`);
    } else if (method === "sms") {
      window.open(`sms:?body=${encodeURIComponent(text)}`);
    } else {
      navigator.clipboard.writeText(wishlistUrl);
      setShared(true);
      setTimeout(() => setShared(false), 2000);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full max-w-md rounded-t-3xl p-6" style={{ background: "var(--surface)" }}>
        <div className="flex justify-center mb-4">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>
        <div className="flex items-center justify-between mb-2">
          <h2 className="font-bold" style={{ fontSize: 18, color: "var(--txt1)" }}>Partager ma wishlist</h2>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--surface2)" }}>
            <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
          </button>
        </div>
        <p style={{ fontSize: 14, color: "var(--txt2)", marginBottom: 20 }}>
          Collection <strong style={{ color: "var(--txt1)" }}>{collection.name}</strong> · {missing.length} tome{missing.length > 1 ? "s" : ""} manquant{missing.length > 1 ? "s" : ""}
        </p>

        {/* Missing items preview */}
        {missing.length > 0 && (
          <div className="rounded-2xl p-3 mb-5" style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
            <p style={{ fontSize: 12, fontWeight: 700, color: "var(--txt3)", textTransform: "uppercase", letterSpacing: "0.1em", marginBottom: 8 }}>
              Ce que tu partages
            </p>
            <div className="flex flex-wrap gap-1.5">
              {missing.slice(0, 12).map(n => (
                <div key={n} className="rounded-lg flex items-center justify-center font-bold"
                  style={{ width: 32, height: 32, background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px dashed var(--miss-b)", fontSize: 12 }}>
                  {n}
                </div>
              ))}
              {missing.length > 12 && (
                <div className="rounded-lg flex items-center justify-center font-bold"
                  style={{ width: 32, height: 32, background: "var(--accent-l)", color: "var(--accent)", fontSize: 11 }}>
                  +{missing.length - 12}
                </div>
              )}
            </div>
          </div>
        )}

        {/* Share buttons */}
        <div className="flex flex-col gap-3">
          <button onClick={() => shareVia("whatsapp")}
            className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3 active:scale-95"
            style={{ background: "#25D366", color: "#fff", fontSize: 15 }}>
            <MessageCircle className="w-5 h-5" />
            Partager sur WhatsApp
          </button>
          <button onClick={() => shareVia("sms")}
            className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3 active:scale-95"
            style={{ background: "var(--surface2)", color: "var(--txt1)", fontSize: 15, border: "1px solid var(--border)" }}>
            <MessageCircle className="w-5 h-5" />
            Envoyer par SMS / iMessage
          </button>
          <button onClick={() => shareVia("copy")}
            className="w-full py-4 rounded-2xl font-bold flex items-center justify-center gap-3 active:scale-95"
            style={{ background: shared ? "var(--have-bg)" : "var(--accent-l)", color: shared ? "var(--have-t)" : "var(--accent)", fontSize: 15, border: `1px solid ${shared ? "var(--have-b)" : "var(--border)"}` }}>
            {shared ? <Check className="w-5 h-5" /> : <Share2 className="w-5 h-5" />}
            {shared ? "Lien copié !" : "Copier le lien"}
          </button>
        </div>
      </div>
    </div>
  );
}

export default function CollectionsPage() {
  const [collections, setCollections] = useState<Collection[]>(DEMO_COLLECTIONS);
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<Filter>("all");
  const [showCreate, setShowCreate] = useState(false);
  const [shareCollection, setShareCollection] = useState<Collection | null>(null);

  const filtered = collections.filter(c => {
    const s = !search || c.name.toLowerCase().includes(search.toLowerCase()) || c.author?.toLowerCase().includes(search.toLowerCase());
    const f = filter === "all" || c.book_type === filter;
    return s && f;
  });

  const handleCreate = (data: Partial<Collection>) => {
    const newCol: Collection = {
      id: `c_${Date.now()}`,
      library_id: "lib1",
      name: data.name!,
      author: data.author,
      book_type: data.book_type ?? "livre",
      total_volumes: data.total_volumes,
      owned_volumes: [],
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    setCollections(prev => [newCol, ...prev]);
  };

  return (
    <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>

      {/* Header */}
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

      {/* Collections list */}
      <div className="px-4 flex flex-col gap-3">
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center py-20 gap-4">
            <BookOpen className="w-12 h-12" style={{ color: "var(--txt3)", opacity: 0.3 }} />
            <p className="font-semibold" style={{ fontSize: 17, color: "var(--txt1)" }}>Aucune collection</p>
            <button onClick={() => setShowCreate(true)}
              className="px-5 py-3 rounded-2xl font-bold active:scale-95"
              style={{ background: "var(--accent)", color: "#fff", fontSize: 14 }}>
              + Créer une collection
            </button>
          </div>
        ) : filtered.map(c => (
          <div key={c.id}>
            <CollectionCard collection={c} />
            {/* Share wishlist button — only if there are missing items */}
            {(c.total_volumes && c.owned_volumes.length < c.total_volumes) && (
              <button onClick={() => setShareCollection(c)}
                className="w-full mt-2 py-3 rounded-2xl font-semibold flex items-center justify-center gap-2 active:scale-95"
                style={{ background: "var(--surface)", border: "1px solid var(--border)", color: "var(--txt2)", fontSize: 13 }}>
                <Gift className="w-4 h-4" style={{ color: "var(--accent)" }} />
                Partager ma wishlist
              </button>
            )}
          </div>
        ))}
      </div>

      {/* Modals */}
      {showCreate && <CreateModal onClose={() => setShowCreate(false)} onCreate={handleCreate} />}
      {shareCollection && <ShareModal collection={shareCollection} onClose={() => setShareCollection(null)} />}

      <BottomNav />
    </div>
  );
}
