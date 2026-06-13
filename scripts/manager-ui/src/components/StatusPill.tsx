import type { Tone } from "../lib/format";

type StatusPillProps = {
  tone: Tone;
  children: string | number;
};

export function StatusPill({ tone, children }: StatusPillProps) {
  return (
    <span className="status-pill" data-tone={tone}>
      {children}
    </span>
  );
}
