import Link from "next/link";

export function Footer() {
  return (
    <footer id="contact" className="marketing-footer" style={{ background: "#1C1812", padding: "60px 32px 40px" }}>
      <div className="marketing-footer-grid" style={{ maxWidth: 1180, margin: "0 auto", display: "grid", gridTemplateColumns: "1.5fr 1fr 1fr 1fr", gap: 40 }}>
        <div>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span style={{ display: "block", width: 24, height: 28 }}>
              <img src="/assets/lumi-red.png" alt="Lumi" style={{ display: "block", width: "100%", height: "100%", objectFit: "contain" }} />
            </span>
            <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 24, color: "#fff" }}>Lumi</span>
          </div>
          <p style={{ fontWeight: 300, fontSize: 15, lineHeight: 1.6, color: "#A49C8E", margin: "16px 0 0", maxWidth: 280 }}>
            The home reading diary for Australian primary schools. Real books at the centre, paperwork gone.
          </p>
        </div>
        <div>
          <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 14, color: "#fff", marginBottom: 16 }}>Product</div>
          <div style={{ display: "flex", flexDirection: "column", gap: 11 }}>
            <a href="#how" style={{ fontWeight: 300, fontSize: 14, color: "#A49C8E", textDecoration: "none" }}>
              How it works
            </a>
            <a href="#teachers" style={{ fontWeight: 300, fontSize: 14, color: "#A49C8E", textDecoration: "none" }}>
              For teachers
            </a>
            <a href="#schools" style={{ fontWeight: 300, fontSize: 14, color: "#A49C8E", textDecoration: "none" }}>
              For schools
            </a>
            <a href="#pricing" style={{ fontWeight: 300, fontSize: 14, color: "#A49C8E", textDecoration: "none" }}>
              Pricing
            </a>
          </div>
        </div>
        <div>
          <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 14, color: "#fff", marginBottom: 16 }}>Company</div>
          <div style={{ display: "flex", flexDirection: "column", gap: 11 }}>
            <a href="#contact" style={{ fontWeight: 300, fontSize: 14, color: "#A49C8E", textDecoration: "none" }}>
              About
            </a>
            <Link href="/contact-sales" style={{ fontWeight: 300, fontSize: 14, color: "#A49C8E", textDecoration: "none" }}>
              Contact sales
            </Link>
            <a href="#contact" style={{ fontWeight: 300, fontSize: 14, color: "#A49C8E", textDecoration: "none" }}>
              Careers
            </a>
          </div>
        </div>
        <div>
          <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 14, color: "#fff", marginBottom: 16 }}>Resources</div>
          <div style={{ display: "flex", flexDirection: "column", gap: 11 }}>
            <a
              href="/support"
              style={{ fontWeight: 300, fontSize: 14, color: "#A49C8E", textDecoration: "none" }}
            >
              Help centre
            </a>
            <a
              href="/legal/privacy"
              style={{ fontWeight: 300, fontSize: 14, color: "#A49C8E", textDecoration: "none" }}
            >
              Privacy
            </a>
            <a
              href="/legal/terms"
              style={{ fontWeight: 300, fontSize: 14, color: "#A49C8E", textDecoration: "none" }}
            >
              Terms
            </a>
          </div>
        </div>
      </div>
        <div
          className="marketing-footer-bottom"
        style={{
          maxWidth: 1180,
          margin: "40px auto 0",
          paddingTop: 24,
          borderTop: "1px solid #38322A",
          display: "flex",
          flexWrap: "wrap",
          gap: 12,
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <span style={{ fontWeight: 300, fontSize: 13, color: "#8A8276" }}>© 2026 Lumi Reading Diary</span>
        <span style={{ fontWeight: 300, fontSize: 13, color: "#8A8276" }}>Made in Australia for primary schools</span>
      </div>
    </footer>
  );
}
