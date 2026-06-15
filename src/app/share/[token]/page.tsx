"use client";
import { useEffect, useState } from "react";
import { useSession } from "next-auth/react";
import { useParams, useRouter } from "next/navigation";
import { Collection } from "@/types";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";
import { BookOpen, Check, LogIn } from "lucide-react";

interface ShareData {
  id: string;
  collection: Collection;
  owner_name: string;
}

export default function SharedCollectionPage() {
  const { token }        = useParams<{ token: string }>();
  const { data: session, status } = useSession();
  const router           = useRouter();
  const [data,    setData]    = useState<ShareData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error,   setError]   = useState<string | null>(null);
  const [added,   setAdded]   = useState(false);

  useEffect(() => {
    if (status === "loading") return;
    const viewer_id = session?.user?.id ?? "";
    fetch(`/api/share?token=${token}&viewer_id=${viewer_id}`)
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

  if (error) return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4 px-6" style={{ background: "var(--bg)" }}>
      <p className="font-bold text-lg" style={{ color: "var(--txt1)" }}>Lien invalide ou expiré</p>
      <p style={{ color: "var(--txt2)", textAlign: "center" }}>{error}</p>
      <Button onClick={() => router.push("/library")}>Aller à ma bibliothèque</Button>
    </div>
  );

  if (!data) return null;
  const { collection, owner_name } = data;
  const total   = collection.total_volumes ?? 0;
  const owned   = collection.owned_volumes ?? [];
  const missing = total > 0
    ? Array.from({ length: total }, (_, i) => i + 1).filter(n => !owned.includes(n))
    : [];
  const pct = total > 0 ? Math.round((owned.length / total) * 100) : 0;

  return (
    <div className="min-h-screen pb-10" style={{ background: "var(--bg)" }}>
      {/* Header */}
      <div className="px-5 pt-14 pb-6" style={{ background: "var(--accent)" }}>
        <p style={{ color: "rgba(255,255,255,0.65)", fontSize: 13 }}>Collection de</p>
        <h1 className="text-3xl font-bold text-white mt-1">{owner_name}</h1>
        <p style={{ color: "rgba(255,255,255,0.75)", fontSize: 14, marginTop: 4 }}>{collection.name}</p>
      </div>

      {/* Not logged in — prompt to sign in */}
      {!session && (
        <div className="mx-4 -mt-4 mb-6 p-4 rounded-2xl shadow-sm"
          style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          <div className="flex items-start gap-3">
            <div className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
              style={{ background: "var(--accent-l)" }}>
              <LogIn className="w-5 h-5" style={{ color: "var(--accent)" }} />
            </div>
            <div className="flex-1">
              <p className="font-semibold" style={{ fontSize: 14, color: "var(--txt1)" }}>
                Connecte-toi pour sauvegarder
              </p>
              <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 3, lineHeight: 1.5 }}>
                Crée un compte Folio gratuit pour retrouver cette collection dans ton espace.
              </p>
              <Button
                onClick={() => router.push(`/login?callbackUrl=/share/${token}`)}
                className="mt-3 px-4 py-2 rounded-xl"
                size="sm"
              >
                Se connecter avec Google
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* Logged in — add to my libraries notification */}
      {session && !added && (
        <div className="mx-4 -mt-4 mb-6 p-4 rounded-2xl shadow-sm"
          style={{ background: "var(--have-bg)", border: "1px solid var(--have-b)" }}>
          <div className="flex items-center gap-3">
            <Check className="w-5 h-5 flex-shrink-0" style={{ color: "var(--have-t)" }} />
            <p style={{ fontSize: 14, color: "var(--have-t)", fontWeight: 600 }}>
              Collection ajoutée à vos bibliothèques partagées !
            </p>
          </div>
        </div>
      )}

      {/* Collection card */}
      <div className="mx-4 mb-4 rounded-2xl overflow-hidden"
        style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
        <div className="flex gap-3 p-4">
          <Cover src={collection.cover_url} alt={collection.name} width={56} height={78} className="rounded-xl flex-shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="font-bold" style={{ fontSize: 16, color: "var(--txt1)" }}>{collection.name}</p>
            {collection.author && <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{collection.author}</p>}
            <div className="flex items-center gap-2 mt-3">
              <div className="flex-1 h-2 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
                <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
              </div>
              <span className="font-bold" style={{ fontSize: 13, color: "var(--accent)" }}>
                {owned.length}{total ? `/${total}` : ""} tomes
              </span>
            </div>
          </div>
        </div>

        {/* Volume chips */}
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
            {total > 30 && (
              <div className="flex items-center justify-center font-bold"
                style={{ width: 30, height: 30, borderRadius: 8, fontSize: 11, background: "var(--accent-l)", color: "var(--accent)" }}>
                +{total - 30}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Missing volumes */}
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
