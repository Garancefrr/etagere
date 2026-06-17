"use client";
import { useState, useEffect } from "react";
import { useSession } from "next-auth/react";

interface LibState {
  library_id: string | null;
  profile_id: string | null;
  email: string | null;
  loading: boolean;
}

const CACHE_KEY = "folio_library";

export function useLibrary(): LibState {
  const { data: session, status } = useSession();
  const [state, setState] = useState<LibState>(() => {
    // Try sessionStorage first for instant load
    if (typeof window !== "undefined") {
      try {
        const cached = sessionStorage.getItem(CACHE_KEY);
        if (cached) {
          const parsed = JSON.parse(cached);
          return { ...parsed, loading: false };
        }
      } catch { /* ignore */ }
    }
    return { library_id: null, profile_id: null, email: null, loading: true };
  });

  useEffect(() => {
    if (status === "loading") return;
    const email = session?.user?.email;
    if (!email) { setState({ library_id: null, profile_id: null, email: null, loading: false }); return; }

    // If cached email matches, skip fetch
    if (state.library_id && state.email === email && !state.loading) return;

    fetch(`/api/library?email=${encodeURIComponent(email)}`)
      .then(r => r.json())
      .then(d => {
        const s = { library_id: d.id, profile_id: d.profile_id, email, loading: false };
        setState(s);
        try { sessionStorage.setItem(CACHE_KEY, JSON.stringify(s)); } catch { /* ignore */ }
      })
      .catch(() => setState(prev => ({ ...prev, loading: false })));
  }, [session?.user?.email, status]); // eslint-disable-line react-hooks/exhaustive-deps

  return state;
}
