const COLUMNS = [
  {
    key: "parents",
    header: "For parents",
    headerBg: "#EC4544",
    headerCol: "#fff",
    bullet: "#EC4544",
    icon: "/assets/green_bear.png",
    iconAlt: "Green bear Lumi",
    items: [
      "One-tap quick log",
      "No typing, ever",
      "Feeling blobs & comment chips",
      "Reminders that fit your routine",
      "Offline logging + auto-sync",
      "Multi-child support",
    ],
  },
  {
    key: "teachers",
    header: "For teachers",
    headerBg: "#56C8E6",
    headerCol: "#06384A",
    bullet: "#1989CA",
    icon: "/assets/lumi-wizard.png",
    iconAlt: "Lumi wizard",
    items: [
      "Live class dashboard",
      "Engagement charts",
      "Priority nudges & milestone alerts",
      "Fully customisable allocation",
      "ISBN barcode scanner",
      "Flexible reading groups",
    ],
  },
  {
    key: "schools",
    header: "For schools",
    headerBg: "#51BA65",
    headerCol: "#0C3A18",
    bullet: "#3C9B53",
    icon: "/assets/lumi-books.png",
    iconAlt: "Lumi with books",
    items: [
      "User & role management",
      "Parent linking codes",
      "PM, A–Z, Lexile & custom levels",
      "School-wide analytics",
      "Web admin console",
      "Set up in minutes",
    ],
  },
  {
    key: "kids",
    header: "For kids",
    headerBg: "#FFCB05",
    headerCol: "#3A2E00",
    bullet: "#C79400",
    icon: "/assets/lumi-crown.png",
    iconAlt: "Lumi wearing a crown",
    items: [
      "Achievements unlock as they read",
      "Bronze-to-legendary rarity tiers",
      "Five feeling blobs to tap",
      "Streaks with built-in rest days",
      "Celebration animations",
      "Lumi cheers them on",
    ],
  },
];

const CHARACTERS = [
  { file: "lumi-crown.png", alt: "Lumi with a crown" },
  { file: "lumi-wizard.png", alt: "Lumi wizard" },
  { file: "lumi-pirate.png", alt: "Lumi pirate" },
  { file: "lumi-space.png", alt: "Lumi astronaut" },
  { file: "lumi-coolkid.png", alt: "Lumi with a cap" },
  { file: "lumi-ninja.png", alt: "Lumi ninja" },
];

export function FeatureGrid() {
  return (
    <section className="marketing-features" style={{ padding: "78px 32px", background: "#fff", borderTop: "1px solid #ECE7DD", borderBottom: "1px solid #ECE7DD" }}>
      <div style={{ maxWidth: 1180, margin: "0 auto" }}>
        <div data-anim="reveal" style={{ textAlign: "center", maxWidth: 680, margin: "0 auto 48px" }}>
          <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, letterSpacing: "0.12em", textTransform: "uppercase", color: "#C79400" }}>
            Everything in one place
          </span>
          <h2 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 46, lineHeight: 1.06, letterSpacing: "-0.02em", margin: "14px 0 0", color: "#1C1812" }}>
            A whole reading ecosystem, minus the paperwork.
          </h2>
        </div>
        <div data-anim="stagger" className="marketing-feature-grid" style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 18 }}>
          {COLUMNS.map((col) => (
            <div key={col.key} style={{ border: "1px solid #ECE7DD", borderRadius: 22, overflow: "hidden" }}>
              <div style={{ background: col.headerBg, minHeight: 76, boxSizing: "border-box", padding: "18px 22px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 18, color: col.headerCol }}>{col.header}</span>
                {col.icon && <img src={col.icon} alt={col.iconAlt} style={{ display: "block", width: 40, height: 40, objectFit: "contain", flexShrink: 0 }} />}
              </div>
              <div style={{ padding: 22, display: "flex", flexDirection: "column", gap: 13 }}>
                {col.items.map((item) => (
                  <span key={item} style={{ display: "flex", gap: 9, fontWeight: 300, fontSize: 14.5, lineHeight: 1.4, color: "#3A352E" }}>
                    <span style={{ color: col.bullet, fontWeight: 700 }}>·</span> {item}
                  </span>
                ))}
              </div>
            </div>
          ))}
        </div>
        <div
          style={{
            marginTop: 20,
            background: "#F7F5F0",
            border: "1px solid #ECE7DD",
            borderRadius: 22,
            padding: "20px 30px",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 30,
            flexWrap: "wrap",
          }}
        >
          <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 16, color: "#1C1812" }}>Collect characters as they read</span>
          <div data-anim="pop" style={{ display: "flex", alignItems: "flex-end", gap: 10 }}>
            {CHARACTERS.map((c) => (
              <img key={c.file} src={`/assets/${c.file}`} alt={c.alt} style={{ height: 60, width: "auto" }} />
            ))}
          </div>
          <span style={{ fontWeight: 300, fontSize: 14, color: "#857E73" }}>30+ to unlock with badges &amp; streaks</span>
        </div>
      </div>
    </section>
  );
}
