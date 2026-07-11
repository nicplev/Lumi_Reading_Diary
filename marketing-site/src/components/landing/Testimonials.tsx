const TESTIMONIALS = [
  {
    quote:
      "\"For the first time I can see exactly which kids are reading at home, and reach the ones who aren't this week, not next term.\"",
    initials: "MH",
    bg: "#DFF0E3",
    fg: "#3C9B53",
    name: "Megan Hollis",
    role: "Assistant Principal",
  },
  {
    quote:
      "\"No more lost journals or chasing signatures. I allocate books to my reading groups and the dashboard does the rest.\"",
    initials: "DT",
    bg: "#DCF0F8",
    fg: "#1989CA",
    name: "Daniel Tran",
    role: "Year 2 Teacher",
  },
  {
    quote: "\"My daughter races to log her reading so Lumi celebrates her streak. Thirty seconds and we're done, no typing.\"",
    initials: "SP",
    bg: "#FFE0DF",
    fg: "#EC4544",
    name: "Sarah Patel",
    role: "Parent · Year 1",
  },
];

export function Testimonials() {
  return (
    <section style={{ padding: "78px 32px" }}>
      <div style={{ maxWidth: 1180, margin: "0 auto", position: "relative" }}>
        <div style={{ position: "absolute", right: 4, top: -30, width: 92, animation: "lumiFloat 5.5s ease-in-out infinite" }}>
          <img
            src="/assets/lumi-frog.png"
            alt="Lumi frog"
            data-hover="peek-l"
            style={{ display: "block", width: 92, height: "auto", transition: "transform .3s cubic-bezier(.34,1.56,.64,1)" }}
          />
        </div>
        <div data-anim="reveal" style={{ textAlign: "center", maxWidth: 680, margin: "0 auto 46px" }}>
          <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, letterSpacing: "0.12em", textTransform: "uppercase", color: "#3C9B53" }}>
            From Australian classrooms
          </span>
          <h2 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 46, lineHeight: 1.06, letterSpacing: "-0.02em", margin: "14px 0 0", color: "#1C1812" }}>
            Loved by literacy leaders, teachers and parents.
          </h2>
        </div>
        <div data-anim="stagger" style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 20 }}>
          {TESTIMONIALS.map((t) => (
            <div key={t.name} style={{ background: "#fff", border: "1px solid #ECE7DD", borderRadius: 22, padding: 30, display: "flex", flexDirection: "column" }}>
              <div style={{ display: "flex", gap: 3, marginBottom: 16 }}>
                {Array.from({ length: 5 }).map((_, i) => (
                  <span key={i} style={{ color: "#FFCB05" }}>
                    ★
                  </span>
                ))}
              </div>
              <p style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 700, fontSize: 18, lineHeight: 1.45, color: "#1C1812", margin: "0 0 24px" }}>
                {t.quote}
              </p>
              <div style={{ marginTop: "auto", display: "flex", alignItems: "center", gap: 13 }}>
                <span
                  style={{
                    width: 44,
                    height: 44,
                    borderRadius: "50%",
                    background: t.bg,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    fontFamily: "'Nunito',sans-serif",
                    fontWeight: 800,
                    color: t.fg,
                  }}
                >
                  {t.initials}
                </span>
                <div>
                  <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 15, color: "#1C1812" }}>{t.name}</div>
                  <div style={{ fontWeight: 300, fontSize: 13, color: "#857E73" }}>{t.role}</div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
