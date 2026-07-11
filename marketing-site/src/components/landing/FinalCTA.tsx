import Link from "next/link";

export function FinalCTA() {
  return (
    <section id="demo" style={{ padding: "30px 32px 90px" }}>
      <div
        style={{
          maxWidth: 1180,
          margin: "0 auto",
          position: "relative",
          background: "#51BA65",
          borderRadius: 32,
          padding: "72px 56px",
          overflow: "hidden",
          textAlign: "center",
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            background: "radial-gradient(90% 120% at 50% -10%, rgba(255,255,255,0.28), rgba(255,255,255,0) 55%)",
          }}
        />
        <div style={{ position: "relative" }}>
          <h2 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 50, lineHeight: 1.04, letterSpacing: "-0.02em", margin: 0, color: "#fff" }}>
            Bring Lumi to your school.
          </h2>
          <p style={{ fontWeight: 300, fontSize: 19, lineHeight: 1.6, color: "#EAF7ED", margin: "18px auto 0", maxWidth: 560 }}>
            See the parent app and teacher dashboard on a 20-minute call. We&apos;ll help you map it to your reading levels
            and library.
          </p>
          <div style={{ display: "flex", gap: 14, justifyContent: "center", marginTop: 32 }}>
            <Link
              href="/book-a-demo"
              style={{
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 800,
                fontSize: 17,
                color: "#fff",
                background: "#EC4544",
                padding: "16px 32px",
                borderRadius: 999,
                textDecoration: "none",
                boxShadow: "0 14px 28px -12px rgba(0,0,0,0.35)",
              }}
            >
              Book a demo
            </Link>
            <Link
              href="/contact-sales"
              style={{
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 800,
                fontSize: 17,
                color: "#0C3A18",
                background: "#fff",
                padding: "16px 32px",
                borderRadius: 999,
                textDecoration: "none",
              }}
            >
              Contact sales
            </Link>
          </div>
        </div>
        <div style={{ position: "absolute", right: 30, bottom: -6, width: 146, animation: "lumiFloat 5.5s ease-in-out infinite" }}>
          <img
            data-lumi-track
            src="/assets/lumi-reading.png"
            alt="Lumi reading a book"
            style={{ display: "block", width: 146, height: "auto", filter: "drop-shadow(0 14px 14px rgba(0,0,0,0.18))", transition: "transform .25s ease-out" }}
          />
        </div>
        <div style={{ position: "absolute", left: 40, top: 28, width: 78, opacity: 0.95, animation: "lumiFloatB 6s ease-in-out infinite" }}>
          <img
            data-lumi-track
            src="/assets/lumi-blue.png"
            alt="Lumi"
            style={{ display: "block", width: 78, height: "auto", transition: "transform .25s ease-out" }}
          />
        </div>
      </div>
    </section>
  );
}
