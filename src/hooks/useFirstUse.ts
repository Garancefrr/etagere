import { useState, useEffect } from "react";

export function useFirstUse(key: string): boolean | null {
  const [isFirst, setIsFirst] = useState<boolean | null>(null);

  useEffect(() => {
    const seen = localStorage.getItem(key);
    setIsFirst(!seen);
    if (!seen) localStorage.setItem(key, "1");
  }, [key]);

  return isFirst;
}

