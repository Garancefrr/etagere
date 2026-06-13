"use client";
import { useState } from "react";
import dynamic from "next/dynamic";
import { ScanResult, ReadStatus, BookType } from "@/types";
import BottomNav from "@/components/layout/BottomNav";
import { ScanLine, CheckCircle } from "lucide-react";

const Scanner = dynamic(() => import("@/components/scanner/Scanner"), { ssr: false });

export default function ScanPage() {
  const [scanning, setScanning] = useState(false);
  const [lastAdded, setLastAdded] = useState<{ title: string; isNewCollection: boolean; collectionName?: string } | null>(null);

  const handleSuccess = async (result: ScanResult, status: ReadStatus, bookType: BookType) => {
    // Save book
    await fetch("/api/books/add", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        isbn: result.book.isbn,
        title: result.book.title,
        authors: result.book.authors,
        cover_url: result.book.cover_url,
        publisher: result.book.publisher,
        published_year: result.book.published_year,
        page_count: result.book.page_count,
        description: result.book.description,
        book_type: bookType,
        status,
        series_name: result.book.series_name,
        series_index: result.book.series_index,
        collection_id: result.collection?.id,
        library_id: "lib1",
        added_by: "user1",
      }),
    });

    if (result.isNewCollection && result.collection) {
      sessionStorage.setItem("new_collection", result.collection.name);
    }

    setScanning(false);
    setLastAdded({
      title: result.book.title,
      isNewCollection: result.isNewCollection,
      collectionName: result.collection?.name,
    });
    setTimeout(() => setLastAdded(null), 4000);
  };

  return (
    <>
      <div className="min-h-screen flex flex-col items-center justify-center px-5 pb-24" style={{ background: "var(--bg)" }}>
        <div className="absolute top-0 left-0 right-0 px-4 pt-10 pb-3">
          <p className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--accent)" }}>Ajouter un ouvrage</p>
          <h1 className="text-2xl font-bold" style={{ color: "var(--txt1)" }}>Scanner</h1>
        </div>

        {!lastAdded ? (
          <div className="flex flex-col items-center gap-8 mt-16">
            <button onClick={() => setScanning(true)}
              className="w-36 h-36 rounded-3xl flex flex-col items-center justify-center gap-3 transition-all active:scale-90"
              style={{ background: "var(--accent)", boxShadow: "0 8px 32px rgba(59,91,255,0.35)" }}>
              <ScanLine className="w-12 h-12 text-white" />
              <span className="text-sm font-bold text-white">Scanner</span>
            </button>
            <div className="text-center">
              <p className="font-semibold" style={{ color: "var(--txt1)" }}>Scannez le code-barres</p>
              <p className="text-sm mt-1" style={{ color: "var(--txt3)" }}>ISBN au dos du livre ou de la BD</p>
            </div>
            <div className="w-full max-w-xs space-y-2">
              {[
                { step: "1", text: "Pointez la caméra vers le code-barres" },
                { step: "2", text: "La détection est automatique" },
                { step: "3", text: "Si c'est une BD, la collection se crée seule" },
              ].map(s => (
                <div key={s.step} className="flex items-center gap-3 p-3 rounded-xl"
                  style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
                  <span className="w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0 text-white"
                    style={{ background: "var(--accent)" }}>{s.step}</span>
                  <span className="text-sm" style={{ color: "var(--txt2)" }}>{s.text}</span>
                </div>
              ))}
            </div>
          </div>
        ) : (
          <div className="flex flex-col items-center gap-6 mt-16">
            <div className="w-20 h-20 rounded-3xl flex items-center justify-center" style={{ background: "var(--have-bg)" }}>
              <CheckCircle className="w-10 h-10" style={{ color: "var(--have-t)" }} />
            </div>
            <div className="text-center">
              <p className="text-xl font-bold" style={{ color: "var(--txt1)" }}>Ajouté !</p>
              <p className="text-sm mt-1 italic" style={{ color: "var(--txt2)" }}>{lastAdded.title}</p>
              {lastAdded.isNewCollection && lastAdded.collectionName && (
                <p className="text-sm mt-2 font-semibold" style={{ color: "var(--accent)" }}>
                  + Collection « {lastAdded.collectionName} » créée
                </p>
              )}
            </div>
            <button onClick={() => setScanning(true)}
              className="px-6 py-3 rounded-2xl font-bold text-sm text-white"
              style={{ background: "var(--accent)" }}>
              Scanner un autre livre
            </button>
          </div>
        )}
      </div>

      {scanning && (
        <Scanner onSuccess={handleSuccess} onClose={() => setScanning(false)} />
      )}
      <BottomNav />
    </>
  );
}
