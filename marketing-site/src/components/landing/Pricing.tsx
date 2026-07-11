import Link from "next/link";

export function Pricing() {
  return (
    <section id="pricing" className="marketing-pricing" style={{ padding: "78px 32px", background: "#fff", borderTop: "1px solid #ECE7DD", borderBottom: "1px solid #ECE7DD" }}>
      <div style={{ maxWidth: 1180, margin: "0 auto", position: "relative" }}>
        <div className="marketing-section-mascot" style={{ position: "absolute", left: 2, top: -26, width: 90, animation: "lumiFloatB 6s ease-in-out infinite" }}>
          <img
            src="/assets/lumi-tiger.png"
            alt="Lumi tiger"
            data-hover="peek-r"
            style={{ display: "block", width: 90, height: "auto", transition: "transform .3s cubic-bezier(.34,1.56,.64,1)" }}
          />
        </div>
        <div data-anim="reveal" style={{ textAlign: "center", maxWidth: 680, margin: "0 auto 46px" }}>
          <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, letterSpacing: "0.12em", textTransform: "uppercase", color: "#EC4544" }}>
            Pricing
          </span>
          <h2 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 46, lineHeight: 1.06, letterSpacing: "-0.02em", margin: "14px 0 0", color: "#1C1812" }}>
            Simple per-student pricing. Unlimited parents.
          </h2>
          <p style={{ fontWeight: 300, fontSize: 18, lineHeight: 1.6, color: "#4A453E", margin: "16px auto 0" }}>
            Billed annually in AUD. Invoicing, POs and funding supported.
          </p>
        </div>
        <div data-anim="stagger" className="marketing-pricing-grid" style={{ display: "grid", gridTemplateColumns: "repeat(2, 1fr)", gap: 20, alignItems: "stretch", maxWidth: 840, margin: "0 auto" }}>
          {/* direct */}
          <div style={{ background: "#F7F5F0", border: "1px solid #ECE7DD", borderRadius: 24, padding: 32, display: "flex", flexDirection: "column" }}>
            <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 20, color: "#1C1812" }}>Direct</div>
            <p style={{ fontWeight: 300, fontSize: 14, color: "#857E73", margin: "6px 0 20px" }}>For parents and guardians purchasing online.</p>
            <div style={{ display: "flex", alignItems: "baseline", gap: 4 }}>
              <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 40, color: "#1C1812" }}>A$9.99</span>
              <span style={{ fontWeight: 300, fontSize: 14, color: "#857E73" }}>/ child · year</span>
            </div>
            <Link
              href="/contact-sales"
              style={{
                margin: "24px 0 26px",
                textAlign: "center",
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 800,
                fontSize: 15,
                color: "#1C1812",
                background: "#fff",
                border: "1.5px solid #E0DBD0",
                padding: 13,
                borderRadius: 999,
                textDecoration: "none",
              }}
            >
              Get started
            </Link>
            <div style={{ display: "flex", flexDirection: "column", gap: 11 }}>
              {[
                "Full parent app, unlimited guardians",
                "Logging in seconds & comment chips",
                "Feeling blobs your child taps",
                "Badges, milestones & celebrations",
                "Reminders, offline logging & multi-child",
              ].map((item) => (
                <span key={item} style={{ display: "flex", gap: 10, fontWeight: 300, fontSize: 14, color: "#3A352E" }}>
                  <span style={{ color: "#51BA65" }}>✓</span> {item}
                </span>
              ))}
            </div>
            <div style={{ marginTop: 18, paddingTop: 16, borderTop: "1px solid #ECE7DD" }}>
              <span style={{ display: "flex", gap: 9, fontWeight: 300, fontSize: 13, lineHeight: 1.5, color: "#857E73" }}>
                <span style={{ color: "#51BA65", fontWeight: 700 }}>★</span> Your school already uses Lumi? The app is free for
                your family, just enter your school linking code.
              </span>
            </div>
          </div>
          {/* whole school */}
          <div
            style={{
              background: "#1C1812",
              borderRadius: 24,
              padding: 32,
              display: "flex",
              flexDirection: "column",
              position: "relative",
              boxShadow: "0 28px 60px -30px rgba(28,24,18,0.6)",
            }}
          >
            <span
              style={{
                position: "absolute",
                top: -13,
                left: "50%",
                transform: "translateX(-50%)",
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 800,
                fontSize: 12,
                letterSpacing: "0.06em",
                textTransform: "uppercase",
                color: "#3A2E00",
                background: "#FFCB05",
                padding: "6px 16px",
                borderRadius: 999,
              }}
            >
              Best value
            </span>
            <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 20, color: "#fff" }}>Whole school</div>
            <p style={{ fontWeight: 300, fontSize: 14, color: "#B8B2A8", margin: "6px 0 20px" }}>Tailored pricing for your whole school.</p>
            <div style={{ display: "flex", alignItems: "baseline", gap: 4 }}>
              <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 40, color: "#fff" }}>Custom</span>
            </div>
            <Link
              href="/contact-sales"
              style={{
                margin: "24px 0 26px",
                textAlign: "center",
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 800,
                fontSize: 15,
                color: "#fff",
                background: "#EC4544",
                padding: 13,
                borderRadius: 999,
                textDecoration: "none",
                boxShadow: "0 12px 24px -12px rgba(236,69,68,0.8)",
              }}
            >
              Contact sales
            </Link>
            <div style={{ display: "flex", flexDirection: "column", gap: 11 }}>
              {["Everything in Direct", "Admin console & linking codes", "School-wide analytics", "Configurable level systems", "Onboarding support"].map(
                (item) => (
                  <span key={item} style={{ display: "flex", gap: 10, fontWeight: 300, fontSize: 14, color: "#E8E4DC" }}>
                    <span style={{ color: "#51BA65" }}>✓</span> {item}
                  </span>
                )
              )}
            </div>
          </div>
        </div>
        <p style={{ textAlign: "center", fontWeight: 300, fontSize: 14, color: "#857E73", margin: "26px auto 0", maxWidth: 520 }}>
          Schools can also purchase Lumi through their preferred school supplies provider. Ask yours about volume pricing.
        </p>
      </div>
    </section>
  );
}
