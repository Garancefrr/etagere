"use client";
import { useState, useEffect } from "react";
import { Wishlist } from "@/types";
import { BookOpen, Gift, Check, Share2 } from "lucide-react";

// Demo data — replace with API call
const DEMO: Wishlist = {
  id: "wl_demo",
  collection_id: "col_1",
  collection_name: "Astérix",
  owner_name: "Garance",
  owner_id: "lib1",
  missing_items: [
    { id: "wi_1", title: "Astérix le Gaulois — Tome 6", authors: ["Goscinny & Uderzo"], series_index: 6, cover_url: "https://covers.openlibrary.org/b/isbn/9782205055375-M.jpg" },
    { id: "wi_2", title: "Astérix le Gaulois — Tome 7", authors: ["Goscinny & Uderzo"], series_index: 7 },
  ],
  created_at: new Date().toISOString(),
};

export default function WishlistPage({ params }: { params: { id: string } }) {
  const [wishlist] = useState<Wishlist>(DEMO);
  const [claimed, setClaimed] = useState<Record<string, boolean>>({});
  const [claimerName, setClaimerName] = useState("");
  const [showNameInput, setShowNameInput] = useState<string | null>(null);

  const handleClaim = (itemId: string) => {
    if (!claimerName.trim()) return;
    setClaimed(prev => ({ ...prev, [itemId]: true }));
    setShowNameInput(null);
    setClaimerName("");
  };

  return (
    <div className="min-h-screen" style={{ background: "var(--bg)" }}>
      {/* Header */}
      <div className="px-5 pt-14 pb-6" style={{ background: "var(--accent)" }}>
        <p className="text-sm font-semibold" style={{ color: "rgba(255,255,255,0.65)" }}>Wishlist de</p>
        <h1 className="text-3xl font-bold text-white mt-1">{wishlist.owner_name}</h1>
        <p className="text-sm mt-1" style={{ color: "rgba(255,255,255,0.7)" }}>
          Collection {wishlist.collection_name} · {wishlist.missing_items.length} livre{wishlist.missing_items.length > 1 ? "s" : ""} souhaité{wishlist.missing_items.length > 1 ? "s" : ""}
        </p>
      </div>

      {/* Intro card */}
      <div className="mx-4 -mt-4 mb-6 p-4 rounded-2xl shadow-sm"
        style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
        <div className="flex items-start gap-3">
          <div className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
            style={{ background: "var(--accent-l)" }}>
            <Gift className="w-5 h-5" style={{ color: "var(--accent)" }} />
          </div>
          <div>
            <p className="font-semibold" style={{ fontSize: 14, color: "var(--txt1)" }}>
              Offrez un livre manquant !
            </p>
            <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 3, lineHeight: 1.5 }}>
              {"Cliquez sur \"Je l'offre !\" pour réserver un livre. Les autres verront qu'il est déjà pris."}
            </p>
          </div>
        </div>
      </div>

      {/* Items */}
      <div className="px-4 flex flex-col gap-3 pb-10">
        <p className="font-bold" style={{ fontSize: 16, color: "var(--txt1)" }}>
          Livres souhaités
        </p>

        {wishlist.missing_items.map(item => {
          const isClaimed = claimed[item.id];
          return (
            <div key={item.id} className="rounded-2xl overflow-hidden"
              style={{ background: "var(--card-bg)", border: `1px solid ${isClaimed ? "var(--have-b)" : "var(--border)"}`, opacity: isClaimed ? 0.75 : 1 }}>

              <div className="flex gap-3 p-4">
                {/* Cover */}
                <div className="rounded-xl overflow-hidden flex-shrink-0 flex items-center justify-center"
                  style={{ width: 56, height: 80, background: "var(--placeholder)" }}>
                  {item.cover_url
                    ? <img src={item.cover_url} alt="" className="w-full h-full object-cover" />
                    : <BookOpen className="w-6 h-6" style={{ color: "var(--txt3)" }} />}
                </div>

                {/* Info */}
                <div className="flex-1 min-w-0">
                  <p className="font-semibold leading-tight" style={{ fontSize: 15, color: "var(--txt1)" }}>
                    {item.title}
                  </p>
                  <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 3 }}>
                    {item.authors.join(", ")}
                  </p>
                  {item.series_index && (
                    <p style={{ fontSize: 12, color: "var(--accent)", marginTop: 3 }}>
                      Tome {item.series_index}
                    </p>
                  )}
                </div>
              </div>

              {/* Claim section */}
              <div className="px-4 pb-4">
                {isClaimed ? (
                  <div className="flex items-center gap-2 py-2.5 px-3 rounded-xl"
                    style={{ background: "var(--have-bg)" }}>
                    <Check className="w-4 h-4 flex-shrink-0" style={{ color: "var(--have-t)" }} />
                    <span style={{ fontSize: 13, fontWeight: 600, color: "var(--have-t)" }}>
                      Réservé — merci !
                    </span>
                  </div>
                ) : showNameInput === item.id ? (
                  <div className="flex gap-2">
                    <input
                      type="text"
                      placeholder="Votre prénom..."
                      value={claimerName}
                      onChange={e => setClaimerName(e.target.value)}
                      className="flex-1 px-3 py-2.5 rounded-xl outline-none"
                      style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)", fontSize: 14 }}
                      onKeyDown={e => e.key === "Enter" && handleClaim(item.id)}
                      autoFocus
                    />
                    <button onClick={() => handleClaim(item.id)}
                      className="px-4 py-2.5 rounded-xl font-bold"
                      style={{ background: "var(--accent)", color: "#fff", fontSize: 14 }}>
                      OK
                    </button>
                  </div>
                ) : (
                  <button onClick={() => setShowNameInput(item.id)}
                    className="w-full py-3 rounded-xl font-bold flex items-center justify-center gap-2 active:scale-95"
                    style={{ background: "var(--accent-l)", color: "var(--accent)", fontSize: 14, border: "1px solid var(--border)" }}>
                    <Gift className="w-4 h-4" />
                    Je l&apos;offre !
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
