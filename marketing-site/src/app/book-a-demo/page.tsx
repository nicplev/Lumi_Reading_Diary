"use client";

import { useState } from "react";
import Link from "next/link";
import { submitDemoRequest } from "@/lib/firebase";

const ROLE_OPTIONS = ["Principal", "Assistant Principal", "Literacy Lead", "Teacher", "School Admin"];
const TIME_OPTIONS = ["Before school", "Lunchtime", "After school"];
const REGION_OPTIONS = ["NSW", "VIC", "QLD", "WA", "SA", "TAS", "ACT", "NT"];

type Intent = "demo" | "info";

function chipStyle(active: boolean) {
  return {
    border: active ? "#EC4544" : "#E0DBD0",
    bg: active ? "#FFE0DF" : "#FCFBF8",
    color: active ? "#B3282C" : "#4A453E",
  };
}

export default function BookADemoPage() {
  const [intent, setIntent] = useState<Intent>("demo");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [school, setSchool] = useState("");
  const [region, setRegion] = useState("");
  const [role, setRole] = useState("");
  const [time, setTime] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const isDemo = intent === "demo";

  const nameBorder = error && !name.trim() ? "#EC4544" : "#E0DBD0";
  const emailBorder = error && !email.trim() ? "#EC4544" : "#E0DBD0";
  const schoolBorder = error && !school.trim() ? "#EC4544" : "#E0DBD0";

  const submitLabel = submitting ? "Booking…" : intent === "demo" ? "Book my demo" : "Send me the info pack";

  const successTitle = intent === "demo" ? "You're booked in!" : "Info pack on its way!";
  const successBody =
    intent === "demo"
      ? `Thanks ${name.split(" ")[0] || ""}. We'll be in touch within one school day to lock in a time${
          time ? ` ${time.toLowerCase()}` : ""
        } that suits you and your team.`
      : `Thanks ${name.split(" ")[0] || ""}. Your info pack is on its way, with pricing, rollout steps and everything to share with your leadership team.`;

  const submit = async () => {
    const need: string[] = [];
    if (!name.trim()) need.push("your name");
    if (!email.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) need.push("a valid email");
    if (!school.trim()) need.push("your school");
    if (need.length) {
      setError(`Please add ${need.join(", ")}.`);
      return;
    }
    setError("");
    setSubmitting(true);
    try {
      await submitDemoRequest({
        schoolName: school,
        contactPerson: name,
        contactEmail: email,
        region: region || undefined,
        role: role || undefined,
        preferredTime: isDemo ? time || undefined : undefined,
        intent,
        message: message || undefined,
      });
      setSubmitted(true);
    } catch {
      setError("Something went wrong, please try again or email us directly.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="marketing-form-page" style={{ fontFamily: "'Helvetica Neue',Helvetica,Arial,sans-serif", color: "#211C16", background: "#F7F5F0", minHeight: "100vh", display: "flex", flexDirection: "column" }}>
      {/* NAV */}
      <div style={{ background: "rgba(247,245,240,0.88)", borderBottom: "1px solid #ECE7DD" }}>
        <div className="marketing-form-nav" style={{ maxWidth: 1180, margin: "0 auto", padding: "16px 32px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <Link href="/" style={{ display: "flex", alignItems: "center", gap: 10, textDecoration: "none" }}>
            <span style={{ display: "block", width: 26, height: 28 }}>
              <img src="/assets/lumi-red.png" alt="Lumi" style={{ display: "block", width: "100%", height: "100%", objectFit: "contain" }} />
            </span>
            <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 27, color: "#211C16", letterSpacing: "-0.01em" }}>Lumi</span>
          </Link>
          <Link href="/" style={{ fontWeight: 400, fontSize: 15, color: "#4A453E", textDecoration: "none" }}>
            ← Back to site
          </Link>
        </div>
      </div>

      <div className="marketing-form-layout" style={{ flex: 1, maxWidth: 1180, width: "100%", margin: "0 auto", padding: "64px 32px 90px", display: "grid", gridTemplateColumns: "1fr 1.15fr", gap: 64, alignItems: "start" }}>
        {/* LEFT: info */}
        <div>
          <span
            style={{
              display: "inline-block",
              fontFamily: "'Nunito',sans-serif",
              fontWeight: 800,
              fontSize: 12,
              letterSpacing: "0.1em",
              textTransform: "uppercase",
              color: "#C79400",
              background: "#FFF1C2",
              padding: "8px 15px",
              borderRadius: 999,
            }}
          >
            20 minutes, online
          </span>
          <h1 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 50, lineHeight: 1.04, letterSpacing: "-0.02em", margin: "18px 0 0", color: "#1C1812" }}>
            See Lumi in action.
          </h1>
          <p style={{ fontWeight: 300, fontSize: 18, lineHeight: 1.65, color: "#4A453E", margin: "18px 0 0" }}>
            A walkthrough of the parent app and teacher dashboard, mapped to how your school runs home reading. Bring your
            literacy lead.
          </p>

          <div style={{ display: "flex", flexDirection: "column", gap: 16, marginTop: 34 }}>
            <div style={{ display: "flex", alignItems: "flex-start", gap: 14 }}>
              <span style={{ width: 32, height: 32, borderRadius: 10, background: "#FFE0DF", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 14, color: "#EC4544" }}>
                1
              </span>
              <span style={{ fontWeight: 300, fontSize: 16, lineHeight: 1.5, color: "#3A352E", paddingTop: 5 }}>
                The parent logging flow: book, blob, chip, done in seconds.
              </span>
            </div>
            <div style={{ display: "flex", alignItems: "flex-start", gap: 14 }}>
              <span style={{ width: 32, height: 32, borderRadius: 10, background: "#DCF0F8", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 14, color: "#1989CA" }}>
                2
              </span>
              <span style={{ fontWeight: 300, fontSize: 16, lineHeight: 1.5, color: "#3A352E", paddingTop: 5 }}>
                The live class dashboard, allocation and ISBN library scanning.
              </span>
            </div>
            <div style={{ display: "flex", alignItems: "flex-start", gap: 14 }}>
              <span style={{ width: 32, height: 32, borderRadius: 10, background: "#DFF0E3", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 14, color: "#3C9B53" }}>
                3
              </span>
              <span style={{ fontWeight: 300, fontSize: 16, lineHeight: 1.5, color: "#3A352E", paddingTop: 5 }}>
                Setup for your school: reading levels, classes and parent linking codes.
              </span>
            </div>
          </div>

          <div style={{ marginTop: 40, background: "#fff", border: "1px solid #ECE7DD", borderRadius: 20, padding: "24px 26px", position: "relative", overflow: "visible" }}>
            <p style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 700, fontSize: 16, lineHeight: 1.5, color: "#1C1812", margin: 0, paddingRight: 74 }}>
              &quot;The demo took twenty minutes. Rolling it out to the whole school took a week.&quot;
            </p>
            <div style={{ fontWeight: 300, fontSize: 13, color: "#857E73", marginTop: 10 }}>Megan Hollis, Assistant Principal</div>
            <div style={{ position: "absolute", right: 18, top: -34, width: 64, animation: "lumiFloat 5.5s ease-in-out infinite" }}>
              <img src="/assets/lumi-reading.png" alt="Lumi reading" style={{ display: "block", width: 64, height: "auto" }} />
            </div>
          </div>
        </div>

        {/* RIGHT: form / success */}
        <div className="marketing-form-card" style={{ background: "#fff", border: "1px solid #ECE7DD", borderRadius: 26, padding: 38, boxShadow: "0 30px 70px -45px rgba(33,28,22,0.35)" }}>
          {!submitted ? (
            <div>
              {/* intent toggle */}
              <div style={{ display: "flex", gap: 8, background: "#F4F1EA", borderRadius: 999, padding: 5, marginBottom: 28 }}>
                <span
                  onClick={() => setIntent("demo")}
                  style={{
                    flex: 1,
                    textAlign: "center",
                    fontFamily: "'Nunito',sans-serif",
                    fontWeight: isDemo ? 800 : 700,
                    fontSize: 14,
                    padding: 10,
                    borderRadius: 999,
                    background: isDemo ? "#fff" : "transparent",
                    color: isDemo ? "#1C1812" : "#857E73",
                    boxShadow: isDemo ? "0 2px 8px rgba(33,28,22,0.1)" : "none",
                    cursor: "pointer",
                  }}
                >
                  Book a live demo
                </span>
                <span
                  onClick={() => setIntent("info")}
                  style={{
                    flex: 1,
                    textAlign: "center",
                    fontFamily: "'Nunito',sans-serif",
                    fontWeight: !isDemo ? 800 : 700,
                    fontSize: 14,
                    padding: 10,
                    borderRadius: 999,
                    background: !isDemo ? "#fff" : "transparent",
                    color: !isDemo ? "#1C1812" : "#857E73",
                    boxShadow: !isDemo ? "0 2px 8px rgba(33,28,22,0.1)" : "none",
                    cursor: "pointer",
                  }}
                >
                  Request an info pack
                </span>
              </div>

              <div className="marketing-form-two-column" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
                <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
                  <label style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1C1812" }}>Your name *</label>
                  <input
                    value={name}
                    onChange={(e) => {
                      setName(e.target.value);
                      setError("");
                    }}
                    placeholder="Jane Citizen"
                    style={{
                      fontFamily: "inherit",
                      fontWeight: 400,
                      fontSize: 15,
                      padding: "13px 15px",
                      border: `1.5px solid ${nameBorder}`,
                      borderRadius: 12,
                      background: "#FCFBF8",
                      color: "#1C1812",
                      outline: "none",
                    }}
                  />
                </div>
                <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
                  <label style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1C1812" }}>Work email *</label>
                  <input
                    value={email}
                    onChange={(e) => {
                      setEmail(e.target.value);
                      setError("");
                    }}
                    placeholder="jane@school.edu.au"
                    style={{
                      fontFamily: "inherit",
                      fontWeight: 400,
                      fontSize: 15,
                      padding: "13px 15px",
                      border: `1.5px solid ${emailBorder}`,
                      borderRadius: 12,
                      background: "#FCFBF8",
                      color: "#1C1812",
                      outline: "none",
                    }}
                  />
                </div>
                <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
                  <label style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1C1812" }}>School *</label>
                  <input
                    value={school}
                    onChange={(e) => {
                      setSchool(e.target.value);
                      setError("");
                    }}
                    placeholder="School name"
                    style={{
                      fontFamily: "inherit",
                      fontWeight: 400,
                      fontSize: 15,
                      padding: "13px 15px",
                      border: `1.5px solid ${schoolBorder}`,
                      borderRadius: 12,
                      background: "#FCFBF8",
                      color: "#1C1812",
                      outline: "none",
                    }}
                  />
                </div>
                <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
                  <label style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1C1812" }}>State</label>
                  <select
                    value={region}
                    onChange={(e) => {
                      setRegion(e.target.value);
                      setError("");
                    }}
                    style={{
                      fontFamily: "inherit",
                      fontWeight: 400,
                      fontSize: 15,
                      padding: "13px 12px",
                      border: "1.5px solid #E0DBD0",
                      borderRadius: 12,
                      background: "#FCFBF8",
                      color: "#1C1812",
                      outline: "none",
                    }}
                  >
                    <option value="">Select</option>
                    {REGION_OPTIONS.map((r) => (
                      <option key={r} value={r}>
                        {r}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div style={{ display: "flex", flexDirection: "column", gap: 7, marginTop: 16 }}>
                <label style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1C1812" }}>Your role</label>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
                  {ROLE_OPTIONS.map((r) => {
                    const s = chipStyle(role === r);
                    return (
                      <span
                        key={r}
                        onClick={() => setRole(r)}
                        style={{
                          fontFamily: "'Nunito',sans-serif",
                          fontWeight: 700,
                          fontSize: 13.5,
                          padding: "9px 16px",
                          borderRadius: 999,
                          cursor: "pointer",
                          border: `1.5px solid ${s.border}`,
                          background: s.bg,
                          color: s.color,
                        }}
                      >
                        {r}
                      </span>
                    );
                  })}
                </div>
              </div>

              {isDemo && (
                <div style={{ display: "flex", flexDirection: "column", gap: 7, marginTop: 16 }}>
                  <label style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1C1812" }}>Preferred time</label>
                  <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
                    {TIME_OPTIONS.map((t) => {
                      const s = chipStyle(time === t);
                      return (
                        <span
                          key={t}
                          onClick={() => setTime(t)}
                          style={{
                            fontFamily: "'Nunito',sans-serif",
                            fontWeight: 700,
                            fontSize: 13.5,
                            padding: "9px 16px",
                            borderRadius: 999,
                            cursor: "pointer",
                            border: `1.5px solid ${s.border}`,
                            background: s.bg,
                            color: s.color,
                          }}
                        >
                          {t}
                        </span>
                      );
                    })}
                  </div>
                </div>
              )}

              <div style={{ display: "flex", flexDirection: "column", gap: 7, marginTop: 16 }}>
                <label style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1C1812" }}>
                  Anything we should know? <span style={{ fontWeight: 600, color: "#928B7F" }}>(optional)</span>
                </label>
                <textarea
                  value={message}
                  onChange={(e) => {
                    setMessage(e.target.value);
                    setError("");
                  }}
                  rows={3}
                  placeholder="Current diary setup, student numbers, timelines..."
                  style={{
                    fontFamily: "inherit",
                    fontWeight: 400,
                    fontSize: 15,
                    padding: "13px 15px",
                    border: "1.5px solid #E0DBD0",
                    borderRadius: 12,
                    background: "#FCFBF8",
                    color: "#1C1812",
                    outline: "none",
                    resize: "vertical",
                  }}
                />
              </div>

              {!!error && <p style={{ fontWeight: 400, fontSize: 14, color: "#EC4544", margin: "16px 0 0" }}>{error}</p>}

              <div
                onClick={submitting ? undefined : submit}
                style={{
                  marginTop: 24,
                  textAlign: "center",
                  fontFamily: "'Nunito',sans-serif",
                  fontWeight: 800,
                  fontSize: 17,
                  color: "#fff",
                  background: "#EC4544",
                  padding: 16,
                  borderRadius: 999,
                  cursor: submitting ? "default" : "pointer",
                  opacity: submitting ? 0.75 : 1,
                  boxShadow: "0 12px 24px -12px rgba(236,69,68,0.7)",
                }}
              >
                {submitLabel}
              </div>
              <p style={{ fontWeight: 300, fontSize: 12.5, color: "#928B7F", textAlign: "center", margin: "14px 0 0" }}>
                We only use these details to organise your demo. No newsletters, no sharing.
              </p>
            </div>
          ) : (
            <div style={{ textAlign: "center", padding: "26px 10px" }}>
              <img
                src="/assets/lumi-trophy.png"
                alt="Lumi with a trophy"
                style={{ width: 120, height: "auto", margin: "0 auto 22px", display: "block", animation: "lumiFloat 5.5s ease-in-out infinite" }}
              />
              <h2 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 32, letterSpacing: "-0.02em", color: "#1C1812", margin: 0 }}>
                {successTitle}
              </h2>
              <p style={{ fontWeight: 300, fontSize: 16, lineHeight: 1.6, color: "#4A453E", margin: "14px auto 0", maxWidth: 380 }}>{successBody}</p>
              <div style={{ margin: "26px auto 0", display: "inline-block", background: "#F4F1EA", borderRadius: 14, padding: "14px 22px" }}>
                <span style={{ fontWeight: 300, fontSize: 14, color: "#4A453E" }}>Confirmation sent to </span>
                <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 14, color: "#1C1812" }}>{email}</span>
              </div>
              <div style={{ marginTop: 30 }}>
                <Link
                  href="/"
                  style={{
                    fontFamily: "'Nunito',sans-serif",
                    fontWeight: 800,
                    fontSize: 15,
                    color: "#1C1812",
                    background: "#fff",
                    border: "1.5px solid #E0DBD0",
                    padding: "13px 26px",
                    borderRadius: 999,
                    textDecoration: "none",
                  }}
                >
                  Back to site
                </Link>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* FOOTER STRIP */}
      <div className="marketing-form-footer" style={{ background: "#1C1812", padding: "22px 32px" }}>
        <div style={{ maxWidth: 1180, margin: "0 auto", display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 10 }}>
          <span style={{ fontWeight: 300, fontSize: 13, color: "#8A8276" }}>© 2026 Lumi Reading Diary</span>
          <span style={{ fontWeight: 300, fontSize: 13, color: "#8A8276" }}>Made in Australia for primary schools</span>
        </div>
      </div>
    </div>
  );
}
