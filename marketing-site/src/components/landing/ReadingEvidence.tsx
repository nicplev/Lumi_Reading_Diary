const EVIDENCE = [
  {
    value: "31.8%",
    color: "#EC4544",
    statement: "of Australian students were not yet at Strong or Exceeding in NAPLAN reading in 2025.",
    supports: "Why sustained reading support matters.",
  },
  {
    value: "9.3%",
    color: "#1989CA",
    statement: "of Australian students needed additional support in reading in 2025.",
    supports: "The need for early visibility and follow-up.",
  },
  {
    value: "99 studies",
    color: "#3C9B53",
    statement: "linked frequent print exposure with stronger language, reading and spelling outcomes.",
    supports: "The case for building a regular reading habit.",
  },
];

export function ReadingEvidence() {
  return (
    <section className="marketing-evidence" style={{ padding: "36px 32px 8px" }} aria-labelledby="reading-evidence-title">
      <div
        style={{
          maxWidth: 1180,
          margin: "0 auto",
          background: "#FFFDF8",
          border: "1px solid #E7E1D7",
          borderRadius: 28,
          padding: "clamp(28px, 5vw, 52px)",
          boxShadow: "0 16px 50px -42px rgba(33,28,22,0.45)",
        }}
      >
        <div data-anim="reveal" style={{ textAlign: "center", maxWidth: 660, margin: "0 auto" }}>
          <span
            style={{
              fontFamily: "'Nunito',sans-serif",
              fontWeight: 800,
              fontSize: 13,
              letterSpacing: "0.12em",
              textTransform: "uppercase",
              color: "#EC4544",
            }}
          >
            Why reading habits matter
          </span>
          <h2
            id="reading-evidence-title"
            style={{
              fontFamily: "'Nunito',sans-serif",
              fontWeight: 900,
              fontSize: "clamp(30px, 4vw, 42px)",
              lineHeight: 1.08,
              letterSpacing: "-0.025em",
              margin: "12px 0 0",
              color: "#1C1812",
            }}
          >
            Small reading moments add up.
          </h2>
          <p style={{ fontWeight: 300, fontSize: 17, lineHeight: 1.6, color: "#4A453E", margin: "14px auto 0" }}>
            Lumi makes home reading visible, easier to sustain and simpler for schools and families to support together.
          </p>
        </div>

        <div
          data-anim="stagger"
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",
            gap: 14,
            marginTop: 34,
          }}
        >
          {EVIDENCE.map((item) => (
            <article
              key={item.value}
              style={{
                background: "#FFFFFF",
                border: "1px solid #ECE7DD",
                borderRadius: 20,
                padding: "26px 22px 22px",
                textAlign: "left",
              }}
            >
              <div
                style={{
                  fontFamily: "'Nunito',sans-serif",
                  fontWeight: 900,
                  fontSize: item.value === "99 studies" ? "clamp(38px, 4vw, 50px)" : "clamp(48px, 5vw, 62px)",
                  lineHeight: 0.95,
                  letterSpacing: "-0.04em",
                  color: item.color,
                }}
              >
                {item.value}
              </div>
              <p style={{ fontWeight: 400, fontSize: 15, lineHeight: 1.48, color: "#1C1812", margin: "16px 0 0" }}>
                {item.statement}
              </p>
              <p style={{ fontWeight: 300, fontSize: 13, lineHeight: 1.45, color: "#857E73", margin: "12px 0 0" }}>
                {item.supports}
              </p>
            </article>
          ))}
        </div>

        <p style={{ fontWeight: 300, fontSize: 12, lineHeight: 1.5, color: "#857E73", textAlign: "center", margin: "22px 0 0" }}>
          Sources: <a href="https://www.acara.edu.au/docs/default-source/media-releases/2025-naplan-national-results-broadly-stable-as-participation-rates-bounce-back-30-7-25.pdf" target="_blank" rel="noreferrer" style={{ color: "inherit", textDecoration: "underline" }}>ACARA, NAPLAN 2025</a> and <a href="https://eric.ed.gov/?id=EJ933833" target="_blank" rel="noreferrer" style={{ color: "inherit", textDecoration: "underline" }}>Mol & Bus, 2011</a>.
        </p>
      </div>
    </section>
  );
}
