"use client";

import { useState } from "react";
import Link from "next/link";
import { submitContactSalesInquiry } from "@/lib/firebase";

const TOPIC_OPTIONS = ["Whole school pricing", "Purchase orders & invoicing", "School suppliers", "Something else"];

function chipStyle(active: boolean) {
  return {
    border: active ? "#EC4544" : "#E0DBD0",
    bg: active ? "#FFE0DF" : "#FCFBF8",
    color: active ? "#B3282C" : "#4A453E",
  };
}

export default function ContactSalesPage() {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [school, setSchool] = useState("");
  const [topic, setTopic] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const nameBorder = error && !name.trim() ? "#EC4544" : "#E0DBD0";
  const emailBorder = error && !email.trim() ? "#EC4544" : "#E0DBD0";
  const messageBorder = error && !message.trim() ? "#EC4544" : "#E0DBD0";

  const successBody = `Thanks ${name.split(" ")[0] || ""}. Your message is with our team and we'll reply within one school day.`;

  const submit = async () => {
    const need: string[] = [];
    if (!name.trim()) need.push("your name");
    if (!email.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) need.push("a valid email");
    if (!message.trim()) need.push("a message");
    if (need.length) {
      setError(`Please add ${need.join(", ")}.`);
      return;
    }
    setError("");
    setSubmitting(true);
    try {
      await submitContactSalesInquiry({
        name,
        email,
        school: school || undefined,
        topic: topic || undefined,
        message,
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
          <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
            <Link href="/book-a-demo" style={{ fontWeight: 400, fontSize: 15, color: "#4A453E", textDecoration: "none" }}>
              Book a demo
            </Link>
            <Link href="/" style={{ fontWeight: 400, fontSize: 15, color: "#4A453E", textDecoration: "none" }}>
              ← Back to site
            </Link>
          </div>
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
              color: "#B3282C",
              background: "#FFE0DF",
              padding: "8px 15px",
              borderRadius: 999,
            }}
          >
            We reply within one school day
          </span>
          <h1 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 50, lineHeight: 1.04, letterSpacing: "-0.02em", margin: "18px 0 0", color: "#1C1812" }}>
            Talk to sales.
          </h1>
          <p style={{ fontWeight: 300, fontSize: 18, lineHeight: 1.65, color: "#4A453E", margin: "18px 0 0" }}>
            Whole school pricing, purchase orders, rollout planning or anything else. Tell us where you&apos;re at and
            we&apos;ll come back with answers, not a sales pitch.
          </p>

          <a
            href="mailto:support@lumi-reading.com"
            style={{ display: "flex", alignItems: "center", gap: 16, marginTop: 34, background: "#fff", border: "1px solid #ECE7DD", borderRadius: 20, padding: "20px 24px", textDecoration: "none" }}
          >
            <span style={{ width: 44, height: 44, borderRadius: 14, background: "#FFE0DF", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
                <rect x="3" y="5" width="18" height="14" rx="2.5" stroke="#EC4544" strokeWidth="2" />
                <path d="M3.5 7l8.5 6 8.5-6" stroke="#EC4544" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
            <span style={{ display: "flex", flexDirection: "column", gap: 2 }}>
              <span style={{ fontWeight: 300, fontSize: 13, color: "#857E73" }}>Prefer email? Write to us anytime</span>
              <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 17, color: "#1C1812" }}>support@lumi-reading.com</span>
            </span>
          </a>

          <div style={{ display: "flex", flexDirection: "column", gap: 14, marginTop: 32 }}>
            <div style={{ display: "flex", alignItems: "flex-start", gap: 13 }}>
              <span style={{ width: 26, height: 26, borderRadius: 8, background: "#DFF0E3", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, marginTop: 1 }}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                  <path d="M5 12.5l4.5 4.5L19 7" stroke="#3C9B53" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </span>
              <span style={{ fontWeight: 300, fontSize: 15.5, lineHeight: 1.5, color: "#3A352E" }}>Invoicing and purchase orders supported</span>
            </div>
            <div style={{ display: "flex", alignItems: "flex-start", gap: 13 }}>
              <span style={{ width: 26, height: 26, borderRadius: 8, background: "#DFF0E3", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, marginTop: 1 }}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                  <path d="M5 12.5l4.5 4.5L19 7" stroke="#3C9B53" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </span>
              <span style={{ fontWeight: 300, fontSize: 15.5, lineHeight: 1.5, color: "#3A352E" }}>
                Volume pricing through your school supplies provider
              </span>
            </div>
            <div style={{ display: "flex", alignItems: "flex-start", gap: 13 }}>
              <span style={{ width: 26, height: 26, borderRadius: 8, background: "#DFF0E3", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, marginTop: 1 }}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                  <path d="M5 12.5l4.5 4.5L19 7" stroke="#3C9B53" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </span>
              <span style={{ fontWeight: 300, fontSize: 15.5, lineHeight: 1.5, color: "#3A352E" }}>Onboarding support for whole school rollouts</span>
            </div>
          </div>

          <div style={{ marginTop: 38, position: "relative", display: "inline-block" }}>
            <img src="/assets/lumi-books.png" alt="Lumi with a stack of books" style={{ width: 130, height: "auto", display: "block", animation: "lumiFloat 6s ease-in-out infinite" }} />
          </div>
        </div>

        {/* RIGHT: form / success */}
        <div className="marketing-form-card" style={{ background: "#fff", border: "1px solid #ECE7DD", borderRadius: 26, padding: 38, boxShadow: "0 30px 70px -45px rgba(33,28,22,0.35)" }}>
          {!submitted ? (
            <div>
              <h2 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 24, letterSpacing: "-0.01em", color: "#1C1812", margin: "0 0 24px" }}>
                Send us a message
              </h2>

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
              </div>

              <div style={{ display: "flex", flexDirection: "column", gap: 7, marginTop: 16 }}>
                <label style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1C1812" }}>School or organisation</label>
                <input
                  value={school}
                  onChange={(e) => setSchool(e.target.value)}
                  placeholder="School name"
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
                  }}
                />
              </div>

              <div style={{ display: "flex", flexDirection: "column", gap: 7, marginTop: 16 }}>
                <label style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1C1812" }}>What&apos;s it about?</label>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
                  {TOPIC_OPTIONS.map((t) => {
                    const s = chipStyle(topic === t);
                    return (
                      <span
                        key={t}
                        onClick={() => setTopic(t)}
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

              <div style={{ display: "flex", flexDirection: "column", gap: 7, marginTop: 16 }}>
                <label style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1C1812" }}>Your message *</label>
                <textarea
                  value={message}
                  onChange={(e) => {
                    setMessage(e.target.value);
                    setError("");
                  }}
                  rows={4}
                  placeholder="Student numbers, timelines, questions..."
                  style={{
                    fontFamily: "inherit",
                    fontWeight: 400,
                    fontSize: 15,
                    padding: "13px 15px",
                    border: `1.5px solid ${messageBorder}`,
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
                {submitting ? "Sending…" : "Send message"}
              </div>
              <p style={{ fontWeight: 300, fontSize: 12.5, color: "#928B7F", textAlign: "center", margin: "14px 0 0" }}>
                Or email us directly at support@lumi-reading.com. We only use these details to reply.
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
                Message sent!
              </h2>
              <p style={{ fontWeight: 300, fontSize: 16, lineHeight: 1.6, color: "#4A453E", margin: "14px auto 0", maxWidth: 380 }}>{successBody}</p>
              <div style={{ margin: "26px auto 0", display: "inline-block", background: "#F4F1EA", borderRadius: 14, padding: "14px 22px" }}>
                <span style={{ fontWeight: 300, fontSize: 14, color: "#4A453E" }}>We&apos;ll reply to </span>
                <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 14, color: "#1C1812" }}>{email}</span>
              </div>
              <div style={{ marginTop: 30, display: "flex", gap: 12, justifyContent: "center" }}>
                <Link
                  href="/book-a-demo"
                  style={{
                    fontFamily: "'Nunito',sans-serif",
                    fontWeight: 800,
                    fontSize: 15,
                    color: "#fff",
                    background: "#EC4544",
                    padding: "13px 26px",
                    borderRadius: 999,
                    textDecoration: "none",
                  }}
                >
                  Book a demo too
                </Link>
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
