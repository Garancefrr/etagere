import { useState, useCallback, useRef } from "react";
import { ToastData } from "@/components/ui/Toast";

export function useToast() {
  const [toasts, setToasts] = useState<ToastData[]>([]);
  const counter = useRef(0);

  const push = useCallback((title: string, subtitle?: string) => {
    const id = counter.current++;
    setToasts(prev => [...prev, { id, title, subtitle }]);
  }, []);

  const dismiss = useCallback((id: number) => {
    setToasts(prev => prev.filter(t => t.id !== id));
  }, []);

  return { toasts, push, dismiss };
}
