/**
 * Resolves the current user's library_id and profile_id from their email.
 * Used by all pages that need to interact with the database.
 */
import { useState, useEffect } from "react";
import { useSession } from "next-auth/react";

export interface LibraryContext {
  library_id: string | null;
  profile_id: string | null;
  email: string | null;
  loading: boolean;
}

export function useLibrary(): LibraryContext {
  const { data: session }             = useSession();
  const [library_id, setLibraryId]   = useState<string | null>(null);
  const [profile_id, setProfileId]   = useState<string | null>(null);
  const [loading,    setLoading]      = useState(true);

  useEffect(() => {
    const email = session?.user?.email;
    if (!email) { setLoading(false); return; }

    fetch(`/api/library?email=${encodeURIComponent(email)}`)
      .then(r => r.json())
      .then(d => {
        if (d.id)         setLibraryId(d.id);
        if (d.profile_id) setProfileId(d.profile_id);
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [session]);

  return {
    library_id,
    profile_id,
    email: session?.user?.email ?? null,
    loading,
  };
}

