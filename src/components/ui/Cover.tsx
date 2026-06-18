"use client";
import { useState } from "react";
import { BookOpen } from "lucide-react";

interface Props {
  src?: string | null;
  alt: string;
  width?: number;
  height?: number;
  className?: string;
}

// Patterns that indicate a placeholder/unavailable image
const PLACEHOLDER_PATTERNS = [
  "image_not_available",
  "no_cover",
  "nocover",
  "no-image",
  "notoile=1",
];

function isPlaceholder(url: string): boolean {
  const lower = url.toLowerCase();
  return PLACEHOLDER_PATTERNS.some(p => lower.includes(p));
}

export function Cover({ src, alt, width, height, className = "" }: Props) {
  const [error, setError] = useState(false);

  const validSrc = src && !error && !isPlaceholder(src) ? src : null;

  if (validSrc) {
    return (
      <img
        src={validSrc}
        alt={alt}
        className={`object-cover ${className}`}
        style={{ width, height }}
        onError={() => setError(true)}
      />
    );
  }

  return (
    <div
      className={`flex items-center justify-center ${className}`}
      style={{ width, height, background: "var(--placeholder)" }}
    >
      <BookOpen style={{ width: "35%", height: "35%", color: "var(--txt3)" }} />
    </div>
  );
}
