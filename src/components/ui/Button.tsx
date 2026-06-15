import { ButtonHTMLAttributes, ReactNode } from "react";

interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "ghost" | "danger";
  size?: "sm" | "md" | "lg";
  children: ReactNode;
}

const VARIANTS = {
  primary:   { background: "var(--accent)",   color: "#fff",          border: "none" },
  secondary: { background: "var(--surface2)", color: "var(--txt1)",   border: "1px solid var(--border)" },
  ghost:     { background: "transparent",     color: "var(--txt2)",   border: "1px solid var(--border)" },
  danger:    { background: "var(--miss-bg)",  color: "var(--miss-t)", border: "1px solid var(--miss-b)" },
};
const SIZES = {
  sm: { padding: "6px 12px",  borderRadius: 10, fontSize: 12 },
  md: { padding: "10px 16px", borderRadius: 14, fontSize: 14 },
  lg: { padding: "14px 20px", borderRadius: 18, fontSize: 15 },
};

export function Button({ variant = "primary", size = "md", style, className = "", ...props }: Props) {
  return (
    <button
      className={`font-semibold flex items-center justify-center gap-2 active:scale-95 transition-transform ${className}`}
      style={{ ...VARIANTS[variant], ...SIZES[size], cursor: "pointer", ...style }}
      {...props}
    />
  );
}
