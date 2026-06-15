interface Props { checked: boolean; onChange: (v: boolean) => void; label?: string; }

export function Toggle({ checked, onChange, label }: Props) {
  return (
    <button role="switch" aria-checked={checked} aria-label={label} onClick={() => onChange(!checked)}
      style={{ width: 48, height: 28, borderRadius: 14, border: "none", cursor: "pointer", flexShrink: 0,
        background: checked ? "var(--accent)" : "var(--border)", position: "relative", transition: "background 0.2s" }}>
      <div style={{ position: "absolute", top: 3, left: 3, width: 22, height: 22, borderRadius: 11,
        background: "#fff", transition: "transform 0.2s", transform: checked ? "translateX(20px)" : "translateX(0)" }} />
    </button>
  );
}
