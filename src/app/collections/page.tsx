"use client";
import { useState, useEffect } from "react";
import { Collection } from "@/types";
import CollectionCard from "@/components/collection/CollectionCard";
import BottomNav from "@/components/layout/BottomNav";
import { Search, Plus } from "lucide-react";

const DEMO_COLLECTIONS: Collection[] = [
  { id:"c1",library_id:"lib1",name:"Astérix",author:"Goscinny & Uderzo",cover_url:"https://covers.openlibrary.org/b/isbn/9782205055375-M.jpg",book_type:"bd",total_volumes:40,owned_volumes:[1,2,3,4,5,8,10,12],created_at:"2024-01-01T00:00:00Z",updated_at:"2024-06-01T00:00:00Z"},
  { id:"c2",library_id:"lib1",name:"Naruto",author:"Masashi Kishimoto",cover_url:"https://covers.openlibrary.org/b/isbn/9782344009888-M.jpg",book_type:"manga",total_volumes:72,owned_volumes:[1,2,3,4,5,11,12],created_at:"2024-01-01T00:00:00Z",updated_at:"2024-06-01T00:00:00Z"},
  { id:"c3",library_id:"lib1",name:"Harry Potter",author:"J.K. Rowling",cover_url:"https://covers.openlibrary.org/b/isbn/9782012101562-M.jpg",book_type:"livre",total_volumes:7,owned_volumes:[1,2,3],created_at:"2024-01-01T00:00:00Z",updated_at:"2024-06-01T00:00:00Z"},
];

export default function CollectionsPage() {
  const [collections, setCollections] = useState<Collection[]>(DEMO_COLLECTIONS);
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<"all"|"bd"|"manga"|"livre">("all");
  const [lastAdded, setLastAdded] = useState<string | null>(null);

  useEffect(() => {
    // Check for newly created collection from scan
    const flash = sessionStorage.getItem("new_collection");
    if (flash) { setLastAdded(flash); sessionStorage.removeItem("new_collection"); setTimeout(() => setLastAdded(null), 4000); }
  }, []);

  const filtered = collections.filter(c => {
    const s = !search || c.name.toLowerCase().includes(search.toLowerCase());
    const f = filter === "all" || c.book_type === filter;
    return s && f;
  });

  return (
    <div className="flex flex-col min-h-screen pb-20" style={{ background: "var(--bg)" }}>
      <div className="sticky top-0 z-30 px-4 pt-10 pb-3" style={{ background: "var(--bg)" }}>
        <div className="flex items-center justify-between mb-4">
          <div>
            <p className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--accent)" }}>Collections</p>
            <h1 className="text-2xl font-bold" style={{ color: "var(--txt1)" }}>{collections.length} <span style={{ fontSize: 16, fontWeight: 400, opacity: 0.35 }}>séries</span></h1>
          </div>
          <button className="w-9 h-9 rounded-xl flex items-center justify-center"
            style={{ background: "var(--accent)" }}>
            <Plus className="w-4 h-4 text-white" />
          </button>
        </div>

        <div className="flex items-center gap-2 px-3 py-2.5 rounded-xl mb-3"
          style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          <Search className="w-4 h-4" style={{ color: "var(--txt3)" }} />
          <input type="text" value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Rechercher une série..." className="flex-1 text-sm outline-none bg-transparent"
            style={{ color: "var(--txt1)" }} />
        </div>

        <div className="flex gap-2 overflow-x-auto pb-1">
          {(["all","bd","manga","livre"] as const).map(f => (
            <button key={f} onClick={() => setFilter(f)}
              className="flex-shrink-0 px-3 py-1.5 rounded-full text-xs font-semibold"
              style={{ background: filter === f ? "var(--accent)" : "var(--surface)", color: filter === f ? "#fff" : "var(--txt2)", border: `1px solid ${filter === f ? "var(--accent)" : "var(--border)"}` }}>
              {f === "all" ? "Toutes" : f === "bd" ? "🎨 BD" : f === "manga" ? "⛩️ Manga" : "📖 Saga"}
            </button>
          ))}
        </div>
      </div>

      <div className="px-4 flex flex-col gap-3">
        {/* Flash notification for new scan */}
        {lastAdded && (
          <div className="rounded-2xl p-3 flex items-center gap-3 animate-pulse"
            style={{ background: "var(--accent-l)", border: "1px solid var(--accent)" }}>
            <Plus className="w-4 h-4 flex-shrink-0" style={{ color: "var(--accent)" }} />
            <div>
              <p className="text-sm font-bold" style={{ color: "var(--accent)" }}>Collection créée !</p>
              <p className="text-xs" style={{ color: "var(--txt2)" }}>{lastAdded} ajoutée automatiquement au scan</p>
            </div>
          </div>
        )}

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center py-16 gap-3">
            <p className="font-semibold" style={{ color: "var(--txt1)" }}>Aucune collection</p>
            <p className="text-sm text-center" style={{ color: "var(--txt3)" }}>Scannez une BD ou un manga pour créer votre première collection automatiquement</p>
          </div>
        ) : filtered.map(c => <CollectionCard key={c.id} collection={c} />)}
      </div>

      <BottomNav />
    </div>
  );
}
