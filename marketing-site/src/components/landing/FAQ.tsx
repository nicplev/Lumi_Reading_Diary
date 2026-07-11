"use client";

import { useState } from "react";

const FAQS = [
  {
    q: "Do students need their own devices?",
    a: "No. Parents log nightly reading on their own phone in seconds, and teachers use the Lumi app on their own phone or iPad. There's no requirement for student devices in class.",
  },
  {
    q: "What if a family doesn't have internet at reading time?",
    a: "Logging works fully offline. The night's reading is saved on the parent's phone and syncs automatically the next time they're connected. Nothing is lost.",
  },
  {
    q: "How do reminders work?",
    a: "Parents pick the time that fits their routine (morning, after school, evening or bedtime) and can change it anytime. If a night hasn't been logged by early evening, a gentle backup nudge goes out; if it has, Lumi stays quiet.",
  },
  {
    q: "Does Lumi fit how our school runs home reading?",
    a: "Yes. Allocation is fully customisable: teachers assign books by reading group, theme, genre, title or free choice, on daily, weekly or fortnightly schedules. If your school uses reading levels you can configure those too, but they're never required. Lumi adapts to your existing routine rather than replacing it.",
  },
  {
    q: "Which reading level systems does Lumi support?",
    a: "PM Benchmark, A–Z and Lexile are built in, and you can define a fully custom level system. Your school configures this once and every class inherits it.",
  },
  {
    q: "How do parents connect to their child?",
    a: "Admins generate secure parent linking codes from the web console. A parent enters the code once, and a single app then covers every child in the family.",
  },
  {
    q: "How much work is this for teachers each day?",
    a: "Close to none. The class dashboard updates itself as families log at home, so there's nothing to collect, count or sign. Teachers glance at who read, tap to send a gentle nudge if needed, and assign the next round of books in two taps. Most of the daily admin that came with paper journals simply disappears.",
  },
  {
    q: "What about families who can't use the app?",
    a: "Lumi is built for the whole class. The app works offline for families with limited data, supports multiple guardians for shared-care households, and one login covers every child in the family. For families without a suitable device or who need extra support, teachers can still log reading on their behalf, so no student is left out and the class picture stays complete.",
  },
  {
    q: "Is our students' data safe?",
    a: "Yes. Lumi is built privacy-first for Australian schools: student data is hosted in Australia and handled in line with the Australian Privacy Principles (APP). Your admins control users, roles and access, data is never shared or sold, and our full privacy policy and terms are published online.",
  },
  {
    q: "How long does it take to set up?",
    a: "Most schools are running within a week. Build your library by scanning ISBN barcodes, import classes, set your level system, and hand out linking codes.",
  },
  {
    q: "Do we still use physical books?",
    a: "Yes, that's the point. Lumi keeps real, physical books at the centre of reading and only digitises the tracking, communication and motivation around them.",
  },
];

export function FAQ() {
  const [open, setOpen] = useState(0);

  return (
    <section className="marketing-faq" style={{ padding: "78px 32px" }}>
      <div style={{ maxWidth: 820, margin: "0 auto", position: "relative" }}>
        <div className="marketing-section-mascot" style={{ position: "absolute", right: -26, top: -22, width: 86, animation: "lumiFloat 5.5s ease-in-out infinite" }}>
          <img
            src="/assets/lumi-penguin.png"
            alt="Lumi penguin"
            data-hover="peek-l"
            style={{ display: "block", width: 86, height: "auto", transition: "transform .3s cubic-bezier(.34,1.56,.64,1)" }}
          />
        </div>
        <div data-anim="reveal" style={{ textAlign: "center", marginBottom: 42 }}>
          <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, letterSpacing: "0.12em", textTransform: "uppercase", color: "#1989CA" }}>
            Questions
          </span>
          <h2 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 46, lineHeight: 1.06, letterSpacing: "-0.02em", margin: "14px 0 0", color: "#1C1812" }}>
            The things schools ask first.
          </h2>
        </div>
        <div data-anim="stagger" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {FAQS.map((f, i) => {
            const isOpen = open === i;
            return (
              <div key={f.q} style={{ background: "#fff", border: "1px solid #ECE7DD", borderRadius: 18, overflow: "hidden" }}>
                <div
                  className="marketing-faq-question"
                  onClick={() => setOpen((cur) => (cur === i ? -1 : i))}
                  style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16, padding: "22px 26px", cursor: "pointer" }}
                >
                  <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 18, color: "#1C1812" }}>{f.q}</span>
                  {isOpen ? (
                    <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 24, color: "#EC4544", lineHeight: 1 }}>–</span>
                  ) : (
                    <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 24, color: "#C9C2B5", lineHeight: 1 }}>+</span>
                  )}
                </div>
                {isOpen && (
                  <div style={{ padding: "0 26px 24px", fontWeight: 300, fontSize: 16, lineHeight: 1.6, color: "#4A453E", maxWidth: 680 }}>{f.a}</div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
