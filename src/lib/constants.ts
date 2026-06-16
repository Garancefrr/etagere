import { ReadStatus, BookType } from "@/types";

export const LIBRARY_ID = "lib1";
export const USER_ID    = "u1";

export const STATUS_CONFIG: Record<ReadStatus, { label: string; emoji: string; bg: string; color: string }> = {
  a_lire:   { label: "À lire",   emoji: "📌", bg: "var(--accent-l)", color: "var(--accent)"  },
  en_cours: { label: "En cours", emoji: "📖", bg: "#FEF9C3",         color: "#A16207"        },
  lu:       { label: "Lu",       emoji: "✅", bg: "var(--have-bg)",  color: "var(--have-t)"  },
};

export const TYPE_CONFIG: Record<BookType, { label: string; emoji: string }> = {
  livre: { label: "Livre", emoji: "📖" },
  bd:    { label: "BD",    emoji: "🎨" },
  manga: { label: "Manga", emoji: "⛩️" },
};

