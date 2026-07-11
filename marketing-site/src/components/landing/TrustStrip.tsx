export function TrustStrip() {
  return (
    <section className="marketing-trust" style={{ padding: "38px 32px 8px" }}>
      <div
        className="marketing-trust-inner"
        style={{
          maxWidth: 1180,
          margin: "0 auto",
          display: "flex",
          flexWrap: "wrap",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 24,
        }}
      >
        <span
          style={{
            fontWeight: 300,
            fontSize: 14,
            letterSpacing: "0.04em",
            textTransform: "uppercase",
            color: "#928B7F",
          }}
        >
          Built for Australian primary classrooms &amp; the science of reading
        </span>
        <div className="marketing-trust-levels" style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <span style={{ fontWeight: 300, fontSize: 13, color: "#928B7F", marginRight: 4 }}>Level systems:</span>
          {["PM Benchmark", "A–Z", "Lexile", "Custom"].map((label) => (
            <span
              key={label}
              style={{
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 700,
                fontSize: 13,
                color: "#4A453E",
                background: "#fff",
                border: "1px solid #ECE7DD",
                padding: "7px 14px",
                borderRadius: 999,
              }}
            >
              {label}
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}
