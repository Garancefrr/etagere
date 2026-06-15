"use client";
import { useEffect } from "react";
import { Check } from "lucide-react";

export interface ToastData { id: number; title: string; subtitle?: string; }

export function Toast({ toast, onDismiss, duration = 3000 }: { toast: ToastData; onDismiss: () => void; duration?: number }) {
  useEffect(() => { const t = setTimeout(onDismiss, duration); return () => clearTimeout(t); }, [onDismiss, duration]);
  return (
    <div className="flex items-center gap-3 px-4 py-3 rounded-2xl shadow-lg"
      style={{ background: "var(--have-bg)", border: "1px solid var(--have-b)", minWidth: 260, maxWidth: 320 }}>
      <div className="w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0" style={{ background: "var(--have-t)" }}>
        <Check className="w-4 h-4 text-white" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-bold truncate" style={{ fontSize: 14, color: "var(--txt1)" }}>{toast.title}</p>
        {toast.subtitle && <p className="truncate" style={{ fontSize: 12, color: "var(--txt2)", marginTop: 1 }}>{toast.subtitle}</p>}
      </div>
    </div>
  );
}

export function ToastStack({ toasts, onDismiss }: { toasts: ToastData[]; onDismiss: (id: number) => void }) {
  if (!toasts.length) return null;
  return (
    <div className="fixed bottom-24 left-0 right-0 z-50 flex flex-col items-center gap-2 px-4 pointer-events-none">
      {toasts.map(t => <Toast key={t.id} toast={t} onDismiss={() => onDismiss(t.id)} />)}
    </div>
  );
}
