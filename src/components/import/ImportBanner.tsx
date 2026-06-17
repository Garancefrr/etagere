"use client";
import { useState, useEffect, useCallback } from "react";
import { X, BookOpen, Check } from "lucide-react";

const JOB_KEY = "folio_import_job";

interface ImportJob {
  job_id: string;
  total: number;
}

interface JobStatus {
  status: "running" | "done" | "error";
  progress: number;
  imported: number;
  errors: number;
  total: number;
}

export function useImportJob() {
  const startJob = (job_id: string, total: number) => {
    localStorage.setItem(JOB_KEY, JSON.stringify({ job_id, total }));
    window.dispatchEvent(new Event("folio-import-start"));
  };
  return { startJob };
}

export function ImportBanner({ onComplete }: { onComplete?: () => void }) {
  const [job,    setJob]    = useState<ImportJob | null>(null);
  const [status, setStatus] = useState<JobStatus | null>(null);
  const [done,   setDone]   = useState(false);

  const loadJob = useCallback(() => {
    try {
      const raw = localStorage.getItem(JOB_KEY);
      if (raw) setJob(JSON.parse(raw));
    } catch { /* ignore */ }
  }, []);

  useEffect(() => {
    loadJob();
    window.addEventListener("folio-import-start", loadJob);
    return () => window.removeEventListener("folio-import-start", loadJob);
  }, [loadJob]);

  // Poll status
  useEffect(() => {
    if (!job || done) return;
    const poll = async () => {
      try {
        const res = await fetch(`/api/import-status?job_id=${job.job_id}`);
        if (!res.ok) return;
        const data: JobStatus = await res.json();
        setStatus(data);
        if (data.status === "done") {
          setDone(true);
          onComplete?.();
          setTimeout(() => {
            localStorage.removeItem(JOB_KEY);
            setJob(null);
            setStatus(null);
            setDone(false);
          }, 5000);
        }
      } catch { /* ignore */ }
    };
    poll();
    const interval = setInterval(poll, 2000);
    return () => clearInterval(interval);
  }, [job, done, onComplete]);

  const dismiss = () => {
    localStorage.removeItem(JOB_KEY);
    setJob(null); setStatus(null); setDone(false);
  };

  if (!job || !status) return null;

  const pct = status.progress;
  const isDone = status.status === "done";

  return (
    <div className="fixed bottom-24 left-4 right-4 z-50 rounded-2xl shadow-2xl overflow-hidden"
      style={{ background: "var(--surface)", border: `1px solid ${isDone ? "var(--have-b)" : "var(--accent)"}` }}>
      {/* Progress bar */}
      <div className="h-1" style={{ background: "var(--border)" }}>
        <div className="h-full transition-all duration-500"
          style={{ width: `${pct}%`, background: isDone ? "var(--have-t)" : "var(--accent)" }} />
      </div>

      <div className="flex items-center gap-3 px-4 py-3">
        <div className="w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0"
          style={{ background: isDone ? "var(--have-bg)" : "var(--accent-l)" }}>
          {isDone
            ? <Check className="w-4 h-4" style={{ color: "var(--have-t)" }} />
            : <div className="w-4 h-4 rounded-full border-2 animate-spin" style={{ borderColor: "var(--accent)", borderTopColor: "transparent" }} />}
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-semibold text-sm" style={{ color: "var(--txt1)" }}>
            {isDone ? `✅ Import terminé !` : `Import Babelio en cours…`}
          </p>
          <p style={{ fontSize: 12, color: "var(--txt2)" }}>
            {isDone
              ? `${status.imported} livres importés${status.errors > 0 ? `, ${status.errors} erreurs` : ""}`
              : `${status.imported} / ${status.total} livres · ${pct}%`}
          </p>
        </div>
        <button onClick={dismiss} className="w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0"
          style={{ background: "var(--surface2)" }}>
          <X className="w-3.5 h-3.5" style={{ color: "var(--txt3)" }} />
        </button>
      </div>
    </div>
  );
}
