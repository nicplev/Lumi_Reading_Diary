const STATS = [
  { value: "3", color: "#EC4544", label: "taps to log a night", sub: "book, blob, bam!" },
  { value: "0", color: "#1989CA", label: "typing required", sub: "no keyboard, no typing" },
  { value: "1", color: "#3C9B53", label: "app for the whole family", sub: "every child, one login" },
];

export function Stats() {
  return (
    <section className="marketing-stats" style={{ padding: "64px 32px 10px" }}>
      <div
        data-anim="stagger"
        className="marketing-stats-grid"
        style={{
          maxWidth: 1180,
          margin: "0 auto",
          display: "grid",
          gridTemplateColumns: "repeat(3, 1fr)",
          gap: 18,
          textAlign: "center",
        }}
      >
        {STATS.map((s) => (
          <div key={s.label} style={{ padding: "18px 10px" }}>
            <div
              className="marketing-stat-value"
              style={{
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 900,
                fontSize: 84,
                lineHeight: 1,
                letterSpacing: "-0.03em",
                color: s.color,
              }}
            >
              {s.value}
            </div>
            <div
              style={{
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 800,
                fontSize: 17,
                color: "#1C1812",
                marginTop: 10,
              }}
            >
              {s.label}
            </div>
            <div style={{ fontWeight: 300, fontSize: 14, color: "#857E73", marginTop: 4 }}>{s.sub}</div>
          </div>
        ))}
      </div>
    </section>
  );
}
