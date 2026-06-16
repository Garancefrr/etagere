#!/bin/bash
set -e
echo "✏️ Collections edit/delete + tag biblio + collection picker..."
cd "$(git rev-parse --show-toplevel)"
cat > "src/lib/db.ts" << 'FILEOF'
import { createServerClient } from "@/lib/supabase";
import { Book, Collection, Wishlist } from "@/types";

// ── Library ───────────────────────────────────────────────────────────────────

export async function getLibraryId(userId: string): Promise<string> {
  const db = createServerClient();
  const { data, error } = await db
    .from("libraries").select("id").eq("owner_id", userId).single();
  if (error || !data) throw new Error(`Library not found for user ${userId}`);
  return data.id;
}

// ── Books ─────────────────────────────────────────────────────────────────────

export async function getBooks(libraryId: string): Promise<Book[]> {
  const db = createServerClient();
  const { data, error } = await db
    .from("books").select("*").eq("library_id", libraryId).order("added_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Book[];
}

export async function insertBook(book: Omit<Book, "id" | "added_at" | "updated_at">): Promise<Book> {
  const db = createServerClient();
  const { data, error } = await db.from("books").insert(book).select().single();
  if (error) throw error;
  return data as Book;
}

export async function patchBook(id: string, updates: Partial<Book>): Promise<void> {
  const db = createServerClient();
  const { error } = await db.from("books")
    .update({ ...updates, updated_at: new Date().toISOString() }).eq("id", id);
  if (error) throw error;
}

export async function removeBook(id: string): Promise<void> {
  const db = createServerClient();
  const { error } = await db.from("books").delete().eq("id", id);
  if (error) throw error;
}

// ── Collections ───────────────────────────────────────────────────────────────

export async function getCollections(libraryId: string): Promise<Collection[]> {
  const db = createServerClient();
  const { data, error } = await db
    .from("collections").select("*").eq("library_id", libraryId).order("name");
  if (error) throw error;
  return (data ?? []) as Collection[];
}

export async function findCollection(libraryId: string, name: string): Promise<Collection | null> {
  const db = createServerClient();
  const { data } = await db
    .from("collections").select("*").eq("library_id", libraryId).ilike("name", name).maybeSingle();
  return data as Collection | null;
}

export async function insertCollection(col: Omit<Collection, "id" | "created_at" | "updated_at">): Promise<Collection> {
  const db = createServerClient();
  const { data, error } = await db.from("collections").insert(col).select().single();
  if (error) throw error;
  return data as Collection;
}

export async function addVolumeToCollection(id: string, currentVolumes: number[], newVolume: number): Promise<void> {
  const db = createServerClient();
  const merged  = currentVolumes.includes(newVolume) ? currentVolumes : [...currentVolumes, newVolume];
  const volumes = merged.sort((a, b) => a - b);
  const { error } = await db.from("collections")
    .update({ owned_volumes: volumes, updated_at: new Date().toISOString() }).eq("id", id);
  if (error) throw error;
}

export async function resolveCollection(
  libraryId: string, seriesName: string, seriesIndex: number,
  opts: { cover_url?: string; author?: string; book_type?: Collection["book_type"] }
): Promise<{ collection: Collection; isNew: boolean; isNewVolume: boolean }> {
  const existing = await findCollection(libraryId, seriesName);
  if (existing) {
    const isNewVolume = !existing.owned_volumes.includes(seriesIndex);
    if (isNewVolume) {
      await addVolumeToCollection(existing.id, existing.owned_volumes, seriesIndex);
      existing.owned_volumes = [...existing.owned_volumes, seriesIndex].sort((a, b) => a - b);
    }
    return { collection: existing, isNew: false, isNewVolume };
  }
  const newCol = await insertCollection({
    library_id: libraryId, name: seriesName, author: opts.author,
    cover_url: opts.cover_url, book_type: opts.book_type ?? "bd", owned_volumes: [seriesIndex],
  });
  return { collection: newCol, isNew: true, isNewVolume: true };
}

// ── Wishlists ─────────────────────────────────────────────────────────────────

export async function getWishlist(id: string): Promise<Wishlist | null> {
  const db = createServerClient();
  const { data } = await db.from("wishlists").select("*").eq("id", id).maybeSingle();
  if (!data) return null;
  return { id: data.id, collection_id: data.collection_id, collection_name: data.collection_name,
    owner_name: data.owner_name, missing_items: data.missing_items ?? [], created_at: data.created_at } as Wishlist;
}

// ── Shared collections ────────────────────────────────────────────────────────

export async function createShare(collectionId: string, ownerId: string): Promise<string> {
  const db = createServerClient();
  const { data: existing } = await db
    .from("shared_collections").select("token")
    .eq("collection_id", collectionId).eq("owner_id", ownerId).maybeSingle();
  if (existing) return existing.token;
  const { data, error } = await db
    .from("shared_collections").insert({ collection_id: collectionId, owner_id: ownerId })
    .select("token").single();
  if (error) throw error;
  return data.token;
}

export async function getShareByToken(token: string): Promise<{
  id: string; collection: Collection; owner_name: string;
} | null> {
  const db = createServerClient();
  const { data } = await db
    .from("shared_collections")
    .select(`id, owner:profiles!owner_id(name), collection:collections(*)`)
    .eq("token", token).gt("expires_at", new Date().toISOString()).maybeSingle();
  if (!data) return null;
  return { id: data.id, collection: data.collection as unknown as Collection, owner_name: (data.owner as any)?.name ?? "Quelqu'un" };
}

export async function registerViewer(shareId: string, viewerId: string): Promise<void> {
  const db = createServerClient();
  await db.from("collection_viewers")
    .upsert({ shared_id: shareId, viewer_id: viewerId, viewed_at: new Date().toISOString() },
             { onConflict: "shared_id,viewer_id" });
}

export interface SharedWithMe {
  token: string; collection_name: string; owner_name: string;
  shared_at: string; cover_url?: string; total_volumes?: number; owned_volumes: number[];
}

export async function getSharedWithMe(viewerId: string): Promise<SharedWithMe[]> {
  const db = createServerClient();
  const { data } = await db
    .from("collection_viewers")
    .select(`viewed_at, share:shared_collections(token, owner:profiles!owner_id(name), collection:collections(name, cover_url, total_volumes, owned_volumes))`)
    .eq("viewer_id", viewerId).order("viewed_at", { ascending: false });
  return (data ?? []).map((row: any) => ({
    token:           row.share.token,
    collection_name: row.share.collection.name,
    owner_name:      row.share.owner?.name ?? "Quelqu'un",
    shared_at:       row.viewed_at,
    cover_url:       row.share.collection.cover_url,
    total_volumes:   row.share.collection.total_volumes,
    owned_volumes:   row.share.collection.owned_volumes ?? [],
  }));
}

export async function patchCollection(id: string, updates: Partial<Collection>): Promise<void> {
  const db = createServerClient();
  const { error } = await db.from("collections")
    .update({ ...updates, updated_at: new Date().toISOString() }).eq("id", id);
  if (error) throw error;
}

export async function removeCollection(id: string): Promise<void> {
  const db = createServerClient();
  const { error } = await db.from("collections").delete().eq("id", id);
  if (error) throw error;
}
FILEOF
cat > "src/app/api/collections/route.ts" << 'FILEOF'
import { NextRequest, NextResponse } from "next/server";
import { getCollections, insertCollection, patchCollection, removeCollection } from "@/lib/db";
import { Collection } from "@/types";

export async function GET(req: NextRequest) {
  const library_id = req.nextUrl.searchParams.get("library_id");
  if (!library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
  try {
    return NextResponse.json(await getCollections(library_id));
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as Omit<Collection, "id" | "created_at" | "updated_at">;
    if (!body.library_id) return NextResponse.json({ error: "library_id manquant" }, { status: 400 });
    return NextResponse.json(await insertCollection(body));
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function PATCH(req: NextRequest) {
  try {
    const { id, ...updates } = await req.json();
    if (!id) return NextResponse.json({ error: "id manquant" }, { status: 400 });
    await patchCollection(id, updates);
    return NextResponse.json({ ok: true });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function DELETE(req: NextRequest) {
  try {
    const { id } = await req.json();
    if (!id) return NextResponse.json({ error: "id manquant" }, { status: 400 });
    await removeCollection(id);
    return NextResponse.json({ ok: true });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
FILEOF
cat > "src/components/book/BookCard.tsx" << 'FILEOF'
"use client";
import { Book } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Star, Layers } from "lucide-react";

interface Props {
  book: Book;
  onClick?: () => void;
}

export default function BookCard({ book, onClick }: Props) {
  const { bg, color, label } = STATUS_CONFIG[book.status];
  const { emoji } = TYPE_CONFIG[book.book_type];

  return (
    <button
      onClick={onClick}
      className="flex flex-col rounded-2xl overflow-hidden text-left w-full active:scale-95 transition-transform"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}
    >
      {/* Cover */}
      <div className="relative w-full" style={{ aspectRatio: "2/3" }}>
        <Cover src={book.cover_url} alt={book.title} className="w-full h-full" />

        <span className="absolute bottom-0 left-0 right-0 text-center"
          style={{ background: bg, color, fontSize: 10, fontWeight: 700, padding: "3px 0" }}>
          {label}
        </span>

        <span className="absolute top-1.5 right-1.5" style={{ fontSize: 11 }}>
          {emoji}
        </span>

        {/* Collection tag */}
        {book.series_name && (
          <span className="absolute top-1.5 left-1.5 flex items-center gap-0.5 px-1.5 py-0.5 rounded-md"
            style={{ background: "rgba(91,122,255,0.85)", fontSize: 8, fontWeight: 700, color: "#fff" }}>
            <Layers style={{ width: 8, height: 8 }} />
            {book.series_name.length > 10 ? book.series_name.slice(0, 10) + "…" : book.series_name}
          </span>
        )}
      </div>

      {/* Info */}
      <div style={{ padding: "8px 8px 10px" }}>
        <p className="font-semibold line-clamp-2" style={{ fontSize: 12, color: "var(--txt1)", lineHeight: 1.3 }}>
          {book.title}
        </p>
        <p className="truncate mt-1" style={{ fontSize: 11, color: "var(--txt2)" }}>
          {book.authors[0]}
        </p>
        {book.rating && (
          <div className="flex gap-0.5 mt-1.5">
            {Array.from({ length: 5 }).map((_, i) => (
              <Star key={i} style={{
                width: 9, height: 9,
                color: i < book.rating! ? "#FBBF24" : "var(--border)",
                fill:  i < book.rating! ? "#FBBF24" : "var(--border)",
              }} />
            ))}
          </div>
        )}
      </div>
    </button>
  );
}
FILEOF
cat > "src/components/book/BookDetail.tsx" << 'FILEOF'
"use client";
import { useState } from "react";
import { Book, ReadStatus, BookType, Collection } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";
import { Button } from "@/components/ui/Button";
import { X, Star, Trash2, Save, Layers, ChevronDown } from "lucide-react";

interface Props {
  book: Book;
  collections: Collection[];
  onClose: () => void;
  onUpdate: (id: string, updates: Partial<Book>) => void;
  onDelete: (id: string) => void;
}

export default function BookDetail({ book, collections, onClose, onUpdate, onDelete }: Props) {
  const [status,      setStatus]       = useState<ReadStatus>(book.status);
  const [bookType,    setBookType]     = useState<BookType>(book.book_type);
  const [rating,      setRating]       = useState(book.rating ?? 0);
  const [note,        setNote]         = useState(book.note ?? "");
  const [seriesName,  setSeriesName]   = useState(book.series_name ?? "");
  const [seriesIndex, setSeriesIndex]  = useState(book.series_index?.toString() ?? "");
  const [showDrop,    setShowDrop]     = useState(false);
  const [confirmDel,  setConfirmDel]   = useState(false);

  const handleSave = () => {
    onUpdate(book.id, {
      status, book_type: bookType,
      rating: rating || undefined,
      note: note || undefined,
      series_name: seriesName.trim() || undefined,
      series_index: seriesIndex ? parseInt(seriesIndex) : undefined,
    });
    onClose();
  };

  const handleDelete = () => { onDelete(book.id); onClose(); };

  const filteredCollections = collections.filter(c =>
    !seriesName || c.name.toLowerCase().includes(seriesName.toLowerCase())
  );

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgba(10,13,31,0.6)" }} onClick={onClose} />
      <div className="relative w-full sm:max-w-md rounded-t-3xl sm:rounded-3xl overflow-hidden"
        style={{ background: "var(--surface)", maxHeight: "92vh" }}>
        <div className="flex justify-center pt-3 sm:hidden">
          <div className="w-10 h-1 rounded-full" style={{ background: "var(--border)" }} />
        </div>
        <button onClick={onClose} className="absolute top-4 right-4 w-8 h-8 rounded-full flex items-center justify-center z-10"
          style={{ background: "var(--surface2)" }}>
          <X className="w-4 h-4" style={{ color: "var(--txt2)" }} />
        </button>

        <div className="overflow-y-auto" style={{ maxHeight: "calc(92vh - 32px)" }}>
          {/* Header */}
          <div className="flex gap-4 p-5 pt-3">
            <Cover src={book.cover_url} alt={book.title} width={80} height={112} className="rounded-xl shadow-md flex-shrink-0" />
            <div className="flex-1 min-w-0 pt-1">
              <h2 className="font-bold text-lg leading-tight" style={{ color: "var(--txt1)" }}>{book.title}</h2>
              <p className="text-sm mt-1" style={{ color: "var(--txt2)" }}>{book.authors.join(", ")}</p>
              {book.publisher && (
                <p className="text-xs mt-0.5" style={{ color: "var(--txt3)" }}>
                  {book.publisher}{book.published_year ? ` · ${book.published_year}` : ""}
                </p>
              )}
              {book.page_count && <p className="text-xs" style={{ color: "var(--txt3)" }}>{book.page_count} pages</p>}
            </div>
          </div>

          <div className="px-5 pb-6 space-y-5">
            {/* Collection */}
            <Section label="Collection">
              <div className="flex gap-2">
                <div className="flex-1 relative">
                  <div className="flex items-center gap-2 px-3 py-2.5 rounded-xl cursor-pointer"
                    onClick={() => setShowDrop(v => !v)}
                    style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                    <Layers className="w-4 h-4 flex-shrink-0" style={{ color: seriesName ? "var(--accent)" : "var(--txt3)" }} />
                    <input
                      value={seriesName}
                      onChange={e => { setSeriesName(e.target.value); setShowDrop(true); }}
                      onClick={e => { e.stopPropagation(); setShowDrop(true); }}
                      placeholder="Aucune collection"
                      className="flex-1 outline-none bg-transparent text-sm"
                      style={{ color: "var(--txt1)" }}
                    />
                    <ChevronDown className="w-4 h-4 flex-shrink-0" style={{ color: "var(--txt3)" }} />
                  </div>
                  {showDrop && (
                    <div className="absolute left-0 right-0 top-full mt-1 rounded-xl overflow-hidden z-20 max-h-36 overflow-y-auto"
                      style={{ background: "var(--surface2)", border: "1px solid var(--border)", boxShadow: "0 4px 16px rgba(0,0,0,0.3)" }}>
                      {/* Remove from collection */}
                      {seriesName && (
                        <button onClick={() => { setSeriesName(""); setSeriesIndex(""); setShowDrop(false); }}
                          className="w-full text-left px-3 py-2.5 text-sm" style={{ color: "var(--miss-t)", borderBottom: "1px solid var(--border)" }}>
                          ✕ Retirer de la collection
                        </button>
                      )}
                      {filteredCollections.map(c => (
                        <button key={c.id} onClick={() => { setSeriesName(c.name); setShowDrop(false); }}
                          className="w-full text-left px-3 py-2.5 text-sm active:opacity-70"
                          style={{ color: "var(--txt1)", borderBottom: "1px solid var(--border)" }}>
                          {c.name}
                          <span style={{ color: "var(--txt3)", marginLeft: 6, fontSize: 11 }}>{c.owned_volumes?.length ?? 0} tomes</span>
                        </button>
                      ))}
                      {seriesName.trim() && !collections.some(c => c.name.toLowerCase() === seriesName.trim().toLowerCase()) && (
                        <button onClick={() => setShowDrop(false)}
                          className="w-full text-left px-3 py-2.5 text-sm font-semibold"
                          style={{ color: "var(--accent)" }}>
                          + Créer « {seriesName.trim()} »
                        </button>
                      )}
                    </div>
                  )}
                </div>
                <input
                  value={seriesIndex}
                  onChange={e => setSeriesIndex(e.target.value)}
                  placeholder="T."
                  type="number"
                  className="w-16 px-3 py-2.5 rounded-xl outline-none text-sm text-center"
                  style={{ background: "var(--surface2)", border: "1px solid var(--border)", color: "var(--txt1)" }}
                />
              </div>
            </Section>

            {/* Type */}
            <Section label="Type">
              <SegmentedControl
                options={Object.entries(TYPE_CONFIG).map(([v, { label, emoji }]) => ({ value: v, label: `${emoji} ${label}` }))}
                value={bookType} onChange={v => setBookType(v as BookType)} />
            </Section>

            {/* Status */}
            <Section label="Statut">
              <SegmentedControl
                options={Object.entries(STATUS_CONFIG).map(([v, { emoji, label }]) => ({ value: v, label: `${emoji} ${label}` }))}
                value={status} onChange={v => setStatus(v as ReadStatus)} />
            </Section>

            {/* Rating */}
            <Section label="Note">
              <div className="flex gap-2">
                {Array.from({ length: 5 }).map((_, i) => (
                  <button key={i} onClick={() => setRating(i + 1 === rating ? 0 : i + 1)}
                    className="flex-1 py-2 rounded-xl flex items-center justify-center"
                    style={{ background: "var(--surface2)", border: "1px solid var(--border)" }}>
                    <Star style={{ width: 18, height: 18, color: i < rating ? "#FBBF24" : "var(--border)", fill: i < rating ? "#FBBF24" : "none" }} />
                  </button>
                ))}
              </div>
            </Section>

            {/* Note */}
            <Section label="Mon avis">
              <textarea value={note} onChange={e => setNote(e.target.value)} placeholder="Vos impressions..."
                rows={3} className="w-full p-3 rounded-xl text-sm resize-none outline-none"
                style={{ background: "var(--surface2)", color: "var(--txt1)", border: "1px solid var(--border)", fontFamily: "inherit" }} />
            </Section>

            {/* Description */}
            {book.description && (
              <Section label="Résumé">
                <p className="text-sm leading-relaxed line-clamp-4" style={{ color: "var(--txt2)" }}>{book.description}</p>
              </Section>
            )}

            {/* Actions */}
            <div className="flex gap-3 pt-1">
              <Button onClick={handleSave} className="flex-1 py-3.5 rounded-2xl">
                <Save className="w-4 h-4" /> Enregistrer
              </Button>
              {!confirmDel ? (
                <Button variant="ghost" onClick={() => setConfirmDel(true)} className="w-12 h-12 rounded-2xl">
                  <Trash2 className="w-4 h-4" style={{ color: "var(--miss-t)" }} />
                </Button>
              ) : (
                <Button variant="danger" onClick={handleDelete} className="px-4 rounded-2xl text-xs">Confirmer ?</Button>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs font-bold uppercase tracking-wider mb-2" style={{ color: "var(--txt3)" }}>{label}</p>
      {children}
    </div>
  );
}

function SegmentedControl({ options, value, onChange }: { options: { value: string; label: string }[]; value: string; onChange: (v: string) => void }) {
  return (
    <div className="flex gap-2">
      {options.map(o => (
        <button key={o.value} onClick={() => onChange(o.value)}
          className="flex-1 py-2.5 rounded-xl text-sm font-semibold"
          style={{ background: value === o.value ? "var(--accent)" : "var(--surface2)", color: value === o.value ? "#fff" : "var(--txt2)", border: `1px solid ${value === o.value ? "var(--accent)" : "var(--border)"}` }}>
          {o.label}
        </button>
      ))}
    </div>
  );
}
FILEOF
cat > "src/components/collection/CollectionCard.tsx" << 'FILEOF'
"use client";
import { Collection } from "@/types";
import { TYPE_CONFIG } from "@/lib/constants";
import { Cover } from "@/components/ui/Cover";

interface Props {
  collection: Collection;
  onEdit?: () => void;
  onDelete?: () => void;
}

export default function CollectionCard({ collection, onEdit, onDelete }: Props) {
  const { emoji } = TYPE_CONFIG[collection.book_type] ?? { emoji: "📖" };
  const owned = collection.owned_volumes ?? [];
  const total = collection.total_volumes ?? 0;
  const pct   = total > 0 ? Math.round((owned.length / total) * 100) : 0;

  return (
    <div className="rounded-2xl overflow-hidden"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
      <div className="flex gap-3 p-4">
        <Cover src={collection.cover_url} alt={collection.name} width={56} height={78} className="rounded-xl flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="font-bold truncate" style={{ fontSize: 16, color: "var(--txt1)" }}>{collection.name}</p>
              {collection.author && <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{collection.author}</p>}
            </div>
            <span style={{ fontSize: 14, flexShrink: 0 }}>{emoji}</span>
          </div>
          <div className="flex items-center gap-2 mt-3">
            <div className="flex-1 h-2 rounded-full overflow-hidden" style={{ background: "var(--border)" }}>
              <div className="h-full rounded-full" style={{ width: `${pct}%`, background: "var(--accent)" }} />
            </div>
            <span className="font-bold flex-shrink-0" style={{ fontSize: 13, color: "var(--accent)" }}>
              {owned.length}{total ? `/${total}` : ""}
            </span>
          </div>
        </div>
      </div>

      {/* Volume chips */}
      {total > 0 && total <= 40 && (
        <div className="flex flex-wrap gap-1.5 px-4 pb-4">
          {Array.from({ length: total }, (_, i) => i + 1).map(n => (
            <div key={n} className="flex items-center justify-center font-bold"
              style={{
                width: 28, height: 28, borderRadius: 7, fontSize: 10,
                background: owned.includes(n) ? "var(--have-bg)" : "var(--miss-bg)",
                color:      owned.includes(n) ? "var(--have-t)"  : "var(--miss-t)",
                border:     owned.includes(n) ? "1px solid var(--have-b)" : "1px dashed var(--miss-b)",
              }}>
              {n}
            </div>
          ))}
        </div>
      )}

      {/* Actions */}
      {(onEdit || onDelete) && (
        <div className="flex gap-2 px-4 pb-4">
          {onEdit && (
            <button onClick={onEdit} className="flex-1 py-2 rounded-xl font-semibold text-center"
              style={{ fontSize: 12, background: "var(--surface2)", color: "var(--txt2)", border: "1px solid var(--border)" }}>
              ✏️ Modifier
            </button>
          )}
          {onDelete && (
            <button onClick={onDelete} className="py-2 px-4 rounded-xl font-semibold"
              style={{ fontSize: 12, background: "var(--miss-bg)", color: "var(--miss-t)", border: "1px solid var(--miss-b)" }}>
              🗑️
            </button>
          )}
        </div>
      )}
    </div>
  );
}
FILEOF
cat > "src/app/collections/page.tsx" << 'FILEOF'
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
FILEOF
cat > "src/app/library/page.tsx" << 'FILEOF'
"use client";
import { useState, useMemo, useEffect, useCallback } from "react";
import { useSession } from "next-auth/react";
import { Book, ReadStatus, BookType, Collection } from "@/types";
import { STATUS_CONFIG, TYPE_CONFIG } from "@/lib/constants";
import { useLibrary } from "@/hooks/useLibrary";
import BookCard from "@/components/book/BookCard";
import BookDetail from "@/components/book/BookDetail";
import BottomNav from "@/components/layout/BottomNav";
import { Search, SlidersHorizontal, LayoutGrid, List, RefreshCw } from "lucide-react";

type Layout       = "grid" | "list";
type FilterType   = BookType | "all";
type FilterStatus = ReadStatus | "all";

export default function LibraryPage() {
  const { data: session }                   = useSession();
  const { library_id, loading: libLoading } = useLibrary();
  const [books,        setBooks]            = useState<Book[]>([]);
  const [booksLoading, setBooksLoading]     = useState(false);
  const [search,       setSearch]           = useState("");
  const [filterStatus, setFilterStatus]     = useState<FilterStatus>("all");
  const [filterType,   setFilterType]       = useState<FilterType>("all");
  const [layout,       setLayout]           = useState<Layout>("grid");
  const [selected,     setSelected]         = useState<Book | null>(null);
  const [showFilters,  setShowFilters]      = useState(false);
  const [collections,  setCollections]      = useState<Collection[]>([]);

  // ── Fetch from Supabase ─────────────────────────────────────────────────────
  const fetchBooks = useCallback(async (lid: string) => {
    setBooksLoading(true);
    try {
      const res = await fetch(`/api/books?library_id=${lid}`);
      if (res.ok) setBooks(await res.json());
    } finally {
      setBooksLoading(false);
    }
  }, []);

  // Load on mount
  useEffect(() => {
    if (library_id) {
      fetchBooks(library_id);
      fetch(`/api/collections?library_id=${library_id}`)
        .then(r => r.json())
        .then(d => Array.isArray(d) ? setCollections(d) : [])
        .catch(console.error);
    }
  }, [library_id, fetchBooks]);

  // Reload when tab gets focus (e.g. after scanning)
  useEffect(() => {
    if (!library_id) return;
    const onFocus = () => fetchBooks(library_id);
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") fetchBooks(library_id);
    });
    return () => {
      window.removeEventListener("focus", onFocus);
    };
  }, [library_id, fetchBooks]);

  // ── Computed ────────────────────────────────────────────────────────────────
  const stats = useMemo(() => ({
    lu:       books.filter(b => b.status === "lu").length,
    en_cours: books.filter(b => b.status === "en_cours").length,
    a_lire:   books.filter(b => b.status === "a_lire").length,
  }), [books]);

  const filtered = useMemo(() => books.filter(b => {
    const q = search.toLowerCase();
    return (
      (!q || b.title.toLowerCase().includes(q) || b.authors.some(a => a.toLowerCase().includes(q))) &&
      (filterStatus === "all" || b.status === filterStatus) &&
      (filterType   === "all" || b.book_type === filterType)
    );
  }), [books, search, filterStatus, filterType]);

  // ── Mutations ───────────────────────────────────────────────────────────────
  const handleUpdate = async (id: string, updates: Partial<Book>) => {
    await fetch("/api/books", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, ...updates }),
    });
    setBooks(prev => prev.map(b => b.id === id ? { ...b, ...updates } : b));
    setSelected(prev => prev?.id === id ? { ...prev, ...updates } as Book : prev);
  };

  const handleDelete = async (id: string) => {
    await fetch("/api/books", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    });
    setBooks(prev => prev.filter(b => b.id !== id));
    setSelected(null);
  };

  const userName = session?.user?.name?.split(" ")[0] ?? "toi";
  const loading  = libLoading || booksLoading;

  // ── Render ──────────────────────────────────────────────────────────────────
  return (
    <div className="flex flex-col min-h-screen pb-24" style={{ background: "var(--bg)" }}>

      {/* Sticky header */}
      <div className="sticky top-0 z-30 px-4 pt-12 pb-3" style={{ background: "var(--bg)" }}>

        {/* Hero banner */}
        <div className="rounded-2xl p-4 mb-4 flex items-center justify-between relative overflow-hidden"
          style={{ background: "var(--accent)" }}>
          <div className="absolute right-[-20px] top-[-20px] w-28 h-28 rounded-full"
            style={{ background: "rgba(255,255,255,0.07)" }} />
          <div>
            <p className="font-bold text-white" style={{ fontSize: 16 }}>Bienvenue {userName} 👋</p>
            <div className="flex gap-5 mt-2">
              {(["lu","en_cours","a_lire"] as ReadStatus[]).map(s => (
                <div key={s}>
                  <p className="font-bold text-white leading-none" style={{ fontSize: 22 }}>{stats[s]}</p>
                  <p style={{ color: "rgba(255,255,255,0.6)", fontSize: 12, marginTop: 2 }}>
                    {STATUS_CONFIG[s].label}
                  </p>
                </div>
              ))}
            </div>
          </div>
          <div className="flex flex-col items-end gap-2">
            {session?.user?.image
              ? <img src={session.user.image} alt="" className="w-12 h-12 rounded-xl object-cover flex-shrink-0" />
              : <div className="w-12 h-12 rounded-xl flex items-center justify-center font-bold flex-shrink-0"
                  style={{ background: "rgba(255,255,255,0.2)", color: "#fff", fontSize: 20 }}>
                  {userName[0]}
                </div>}
          </div>
        </div>

        {/* Search + controls */}
        <div className="flex gap-2 mb-3">
          <div className="flex-1 flex items-center gap-2 px-4 py-3 rounded-2xl"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <Search className="w-5 h-5 flex-shrink-0" style={{ color: "var(--txt3)" }} />
            <input
              type="text" value={search} onChange={e => setSearch(e.target.value)}
              placeholder="Titre, auteur..."
              className="flex-1 outline-none bg-transparent"
              style={{ color: "var(--txt1)", fontSize: 15 }}
            />
          </div>
          <button
            onClick={() => library_id && fetchBooks(library_id)}
            className="w-11 h-11 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            <RefreshCw className="w-5 h-5" style={{ color: "var(--txt2)" }} />
          </button>
          <button
            onClick={() => setLayout(l => l === "grid" ? "list" : "grid")}
            className="w-11 h-11 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
            {layout === "grid"
              ? <List className="w-5 h-5" style={{ color: "var(--txt2)" }} />
              : <LayoutGrid className="w-5 h-5" style={{ color: "var(--txt2)" }} />}
          </button>
          <button
            onClick={() => setShowFilters(f => !f)}
            className="w-11 h-11 rounded-2xl flex items-center justify-center flex-shrink-0"
            style={{
              background: showFilters ? "var(--accent)" : "var(--surface)",
              border: `1px solid ${showFilters ? "var(--accent)" : "var(--border)"}`,
            }}>
            <SlidersHorizontal className="w-5 h-5" style={{ color: showFilters ? "#fff" : "var(--txt2)" }} />
          </button>
        </div>

        {/* Filters */}
        {showFilters && (
          <div className="space-y-2 mb-2">
            <FilterRow
              options={[{ v:"all", l:"Tous" }, ...Object.entries(STATUS_CONFIG).map(([v,c]) => ({ v, l:`${c.emoji} ${c.label}` }))]}
              value={filterStatus}
              onChange={v => setFilterStatus(v as FilterStatus)}
            />
            <FilterRow
              options={[{ v:"all", l:"Tous types" }, ...Object.entries(TYPE_CONFIG).map(([v,c]) => ({ v, l:`${c.emoji} ${c.label}` }))]}
              value={filterType}
              onChange={v => setFilterType(v as FilterType)}
            />
          </div>
        )}
      </div>

      {/* Count */}
      <div className="flex justify-between items-center px-4 mb-3">
        <span className="font-bold" style={{ fontSize: 15, color: "var(--txt1)" }}>
          {loading ? "Chargement…" : `${filtered.length} ouvrage${filtered.length > 1 ? "s" : ""}`}
        </span>
      </div>

      {/* Book list */}
      <div className="px-4">
        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 rounded-full border-2 animate-spin"
              style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center py-20 gap-3">
            <p className="font-semibold" style={{ fontSize: 17, color: "var(--txt1)" }}>
              {books.length > 0 ? "Aucun résultat" : "Bibliothèque vide"}
            </p>
            <p style={{ fontSize: 14, color: "var(--txt3)" }}>
              {books.length > 0 ? "Essayez un autre filtre" : "Scannez votre premier livre !"}
            </p>
          </div>
        ) : layout === "grid" ? (
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: 12 }}>
            {filtered.map(b => <BookCard key={b.id} book={b} onClick={() => setSelected(b)} />)}
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {filtered.map(b => <BookListRow key={b.id} book={b} onClick={() => setSelected(b)} />)}
          </div>
        )}
      </div>

      {selected && (
        <BookDetail
          book={selected}
          collections={collections}
          onClose={() => setSelected(null)}
          onUpdate={handleUpdate}
          onDelete={handleDelete}
        />
      )}
      <BottomNav />
    </div>
  );
}

// ── Internal components ───────────────────────────────────────────────────────

function FilterRow({ options, value, onChange }: {
  options: { v: string; l: string }[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="flex gap-2 overflow-x-auto pb-1" style={{ scrollbarWidth: "none" }}>
      {options.map(({ v, l }) => (
        <button key={v} onClick={() => onChange(v)}
          className="flex-shrink-0 px-4 py-2 rounded-full font-semibold"
          style={{
            fontSize: 13,
            background: value === v ? "var(--accent)" : "var(--surface)",
            color: value === v ? "#fff" : "var(--txt2)",
            border: `1px solid ${value === v ? "var(--accent)" : "var(--border)"}`,
          }}>
          {l}
        </button>
      ))}
    </div>
  );
}

function BookListRow({ book, onClick }: { book: Book; onClick: () => void }) {
  const { bg, color, label } = STATUS_CONFIG[book.status];
  return (
    <button onClick={onClick}
      className="flex items-center gap-3 p-3 rounded-2xl text-left active:scale-[0.98]"
      style={{ background: "var(--card-bg)", border: "1px solid var(--border)" }}>
      <div className="rounded-xl overflow-hidden flex-shrink-0"
        style={{ width: 52, height: 72, background: "var(--placeholder)" }}>
        {book.cover_url && (
          <img src={book.cover_url} alt="" className="w-full h-full object-cover" />
        )}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-semibold truncate" style={{ fontSize: 15, color: "var(--txt1)" }}>
          {book.title}
        </p>
        <p style={{ fontSize: 13, color: "var(--txt2)", marginTop: 2 }}>{book.authors[0]}</p>
        {book.series_name && (
          <p style={{ fontSize: 12, color: "var(--accent)", marginTop: 2 }}>
            {book.series_name} #{book.series_index}
          </p>
        )}
      </div>
      <span className="px-3 py-1.5 rounded-full font-semibold flex-shrink-0"
        style={{ fontSize: 12, background: bg, color }}>
        {label}
      </span>
    </button>
  );
}
FILEOF
git add -A
git commit -m "feat: edit/delete collections, collection picker in book detail, collection tag on cards"
git push
echo "🎉 Déployé !"
