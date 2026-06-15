"use client";
import { useState } from "react";
import { BookOpen } from "lucide-react";

interface Props { src?: string; alt: string; width?: number; height?: number; className?: string; }

export function Cover({ src, alt, width, height, className = "" }: Props) {
  const [error, setError] = useState(false);
  if (src && !error) {
    return <img src={src} alt={alt} className={`object-cover ${className}`} style={{ width, height }} onError={() => setError(true)} />;
  }
  return (
    <div className={`flex items-center justify-center ${className}`} style={{ width, height, background: "var(--placeholder)" }}>
      <BookOpen style={{ width: "35%", height: "35%", color: "var(--txt3)" }} />
    </div>
  );
}
