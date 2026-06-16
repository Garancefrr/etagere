import { ReadStatus } from "@/types";
import { STATUS_CONFIG } from "@/lib/constants";

export function StatusBadge({ status }: { status: ReadStatus }) {
  const { label, bg, color } = STATUS_CONFIG[status];
  return (
    <span style={{ background: bg, color, fontSize: 10, fontWeight: 700, padding: "2px 6px", borderRadius: 6 }}>
      {label}
    </span>
  );
}

