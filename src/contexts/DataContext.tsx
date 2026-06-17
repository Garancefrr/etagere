"use client";
import { createContext, useContext, useState, useCallback, useEffect, useRef } from "react";
import { useLibrary } from "@/hooks/useLibrary";
import { Book, Collection } from "@/types";

interface DataState {
  books: Book[];
  collections: Collection[];
  loading: boolean;
  refreshBooks: () => Promise<void>;
  refreshCollections: () => Promise<void>;
  refreshAll: () => Promise<void>;
  setBooks: React.Dispatch<React.SetStateAction<Book[]>>;
  setCollections: React.Dispatch<React.SetStateAction<Collection[]>>;
  library_id: string | null;
  email: string | null;
}

const DataContext = createContext<DataState>({
  books: [], collections: [], loading: true,
  refreshBooks: async () => {}, refreshCollections: async () => {},
  refreshAll: async () => {}, setBooks: () => {}, setCollections: () => {},
  library_id: null, email: null,
});

export function DataProvider({ children }: { children: React.ReactNode }) {
  const { library_id, email, loading: libLoading } = useLibrary();
  const [books,       setBooks]       = useState<Book[]>([]);
  const [collections, setCollections] = useState<Collection[]>([]);
  const [dataLoaded,  setDataLoaded]  = useState(false);
  const fetchedRef = useRef(false);

  const refreshBooks = useCallback(async () => {
    if (!library_id) return;
    try {
      const res = await fetch(`/api/books?library_id=${library_id}`);
      if (res.ok) setBooks(await res.json());
    } catch { /* ignore */ }
  }, [library_id]);

  const refreshCollections = useCallback(async () => {
    if (!library_id) return;
    try {
      const res = await fetch(`/api/collections?library_id=${library_id}`);
      if (res.ok) { const d = await res.json(); if (Array.isArray(d)) setCollections(d); }
    } catch { /* ignore */ }
  }, [library_id]);

  const refreshAll = useCallback(async () => {
    await Promise.all([refreshBooks(), refreshCollections()]);
  }, [refreshBooks, refreshCollections]);

  // Initial fetch — once
  useEffect(() => {
    if (!library_id || fetchedRef.current) return;
    fetchedRef.current = true;
    Promise.all([
      fetch(`/api/books?library_id=${library_id}`).then(r => r.json()).then(d => Array.isArray(d) ? setBooks(d) : null),
      fetch(`/api/collections?library_id=${library_id}`).then(r => r.json()).then(d => Array.isArray(d) ? setCollections(d) : null),
    ]).finally(() => setDataLoaded(true));
  }, [library_id]);

  // Refresh on tab focus
  useEffect(() => {
    if (!library_id) return;
    const onVisible = () => { if (document.visibilityState === "visible") refreshAll(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }, [library_id, refreshAll]);

  const loading = libLoading || !dataLoaded;

  return (
    <DataContext.Provider value={{ books, collections, loading, refreshBooks, refreshCollections, refreshAll, setBooks, setCollections, library_id, email }}>
      {children}
    </DataContext.Provider>
  );
}

export const useData = () => useContext(DataContext);
