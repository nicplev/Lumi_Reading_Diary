import Link from "next/link";

export default function OpenLumiPage() {
  return (
    <main
      style={{
        minHeight: "100vh",
        display: "grid",
        placeItems: "center",
        padding: 24,
        background: "#F7F5F0",
        color: "#211C16",
        fontFamily: "'Nunito', sans-serif",
      }}
    >
      <section
        style={{
          width: "min(100%, 560px)",
          padding: "48px 32px",
          borderRadius: 28,
          background: "#FFFFFF",
          boxShadow: "0 18px 60px rgba(33, 28, 22, 0.10)",
          textAlign: "center",
        }}
      >
        <p style={{ margin: 0, color: "#F4B400", fontSize: 18, fontWeight: 900 }}>
          LUMI
        </p>
        <h1 style={{ margin: "12px 0", fontSize: 38, lineHeight: 1.1 }}>
          Open Lumi on your device
        </h1>
        <p style={{ margin: "0 auto 28px", maxWidth: 430, color: "#665E55", fontSize: 18 }}>
          If Lumi is installed, this link opens the app securely. Otherwise,
          return to the Lumi website for product and support information.
        </p>
        <Link
          href="/"
          style={{
            display: "inline-block",
            padding: "14px 24px",
            borderRadius: 999,
            background: "#211C16",
            color: "#FFFFFF",
            fontWeight: 800,
            textDecoration: "none",
          }}
        >
          Return to Lumi
        </Link>
      </section>
    </main>
  );
}
