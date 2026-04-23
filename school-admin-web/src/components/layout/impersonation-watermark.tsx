interface Props {
  devEmail: string;
  schoolName: string;
  startedAt: number;
}

/**
 * Low-opacity diagonal CSS watermark repeating the dev's identity across the
 * viewport. Rendered as a `pointer-events: none` fixed overlay so it never
 * blocks interaction — its job is solely to attribute screenshots taken
 * during a session.
 */
export function ImpersonationWatermark({ devEmail, schoolName, startedAt }: Props) {
  const label = `${devEmail} · ${schoolName} · ${new Date(startedAt).toISOString()}`;
  const tile = `${label}        ${label}`;
  return (
    <div
      aria-hidden
      className="pointer-events-none fixed inset-0 z-40 overflow-hidden"
    >
      <div
        className="absolute inset-[-50%] flex flex-wrap content-start gap-x-12 gap-y-24 opacity-[0.04] text-[14px] font-semibold leading-none text-[#B91C1C]"
        style={{
          transform: 'rotate(-30deg)',
          whiteSpace: 'nowrap',
          letterSpacing: '0.08em',
        }}
      >
        {Array.from({ length: 120 }).map((_, i) => (
          <span key={i}>{tile}</span>
        ))}
      </div>
    </div>
  );
}
