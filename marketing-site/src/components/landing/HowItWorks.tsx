"use client";

import { useState } from "react";

const TONIGHT_BOOKS = [
  {
    title: "The Lost Kite",
    iconGradient: "linear-gradient(135deg, rgba(86,200,230,0.35), rgba(86,200,230,0.1))",
    iconStroke: "rgba(42,159,196,0.65)",
    tag: "Level 12",
    tagCol: "#2A9FC4",
    tagBg: "rgba(86,200,230,0.15)",
    extra: "Assigned",
  },
  {
    title: "Sam's Big Day",
    iconGradient: "linear-gradient(135deg, rgba(86,200,230,0.35), rgba(86,200,230,0.1))",
    iconStroke: "rgba(42,159,196,0.65)",
    tag: "Level 12",
    tagCol: "#2A9FC4",
    tagBg: "rgba(86,200,230,0.15)",
    extra: "Assigned",
  },
  {
    title: "Grandpa's Garden",
    iconGradient: "linear-gradient(135deg, rgba(81,186,101,0.35), rgba(81,186,101,0.1))",
    iconStroke: "rgba(66,150,84,0.65)",
    tag: "Free choice",
    tagCol: "#429654",
    tagBg: "rgba(81,186,101,0.15)",
    extra: null,
  },
];

const TIMES = ["5 min", "10 min", "15 min", "20+"];

const BLOBS = [
  { label: "Hard", file: "blob-hard.png", col: "#6FA8DC" },
  { label: "Tricky", file: "blob-tricky.png", col: "#7CB97C" },
  { label: "Okay", file: "blob-okay.png", col: "#E8C547" },
  { label: "Good", file: "blob-good.png", col: "#F5A347" },
  { label: "Great!", file: "blob-great.png", col: "#E86B6B" },
];

const CHIPS = ["Great job!", "Sounded out words well", "Read with expression", "Asked great questions", "Retold the story"];

function CheckIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 24 24" fill="none">
      <path d="M5 12.5l4.5 4.5L19 7" stroke="#fff" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function BookIcon({ stroke }: { stroke: string }) {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
      <path
        d="M12 6c-1.8-1.6-4.2-2-7-2v14c2.8 0 5.2.4 7 2 1.8-1.6 4.2-2 7-2V4c-2.8 0-5.2.4-7 2Z"
        stroke={stroke}
        strokeWidth="2"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function HowItWorks() {
  const [booksOn, setBooksOn] = useState<string[]>(["The Lost Kite"]);
  const [mins, setMins] = useState("10 min");
  const [blob, setBlob] = useState("Great!");
  const [chipsOn, setChipsOn] = useState<string[]>(["Read with expression"]);

  const toggleBook = (title: string) => {
    setBooksOn((cur) => (cur.includes(title) ? cur.filter((x) => x !== title) : cur.concat(title)));
  };

  const toggleChip = (label: string) => {
    setChipsOn((cur) => {
      if (cur.includes(label)) return cur.filter((x) => x !== label);
      if (cur.length >= 3) return cur;
      return cur.concat(label);
    });
  };

  return (
    <section id="how" className="marketing-how" style={{ padding: "78px 32px" }}>
      <div style={{ maxWidth: 1180, margin: "0 auto" }}>
        <div data-anim="reveal" style={{ textAlign: "center", maxWidth: 680, margin: "0 auto" }}>
          <span
            style={{
              fontFamily: "'Nunito',sans-serif",
              fontWeight: 800,
              fontSize: 13,
              letterSpacing: "0.12em",
              textTransform: "uppercase",
              color: "#EC4544",
            }}
          >
            The parent logging flow
          </span>
          <h2
            style={{
              fontFamily: "'Nunito',sans-serif",
              fontWeight: 900,
              fontSize: 46,
              lineHeight: 1.06,
              letterSpacing: "-0.02em",
              margin: "14px 0 0",
              color: "#1C1812",
            }}
          >
            Three taps. No typing. Done before the next chapter.
          </h2>
          <p style={{ fontWeight: 300, fontSize: 18, lineHeight: 1.6, color: "#4A453E", margin: "16px auto 0" }}>
            Logging a night of reading takes longer to describe than to do.
          </p>
        </div>

        <div
          data-anim="stagger"
          className="marketing-how-steps"
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
            gap: 20,
            marginTop: 48,
          }}
        >
          {/* step 1 */}
          <div
            style={{
              background: "#fff",
              border: "1px solid #ECE7DD",
              borderRadius: 24,
              padding: 30,
              display: "flex",
              flexDirection: "column",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
              <span
                style={{
                  fontFamily: "'Nunito',sans-serif",
                  fontWeight: 900,
                  fontSize: 15,
                  color: "#fff",
                  background: "#1C1812",
                  width: 34,
                  height: 34,
                  borderRadius: "50%",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                1
              </span>
              <span style={{ fontWeight: 300, fontSize: 13, color: "#928B7F" }}>Parent app</span>
            </div>
            <h3 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 22, margin: "22px 0 8px", color: "#1C1812" }}>
              Pick tonight&apos;s book
            </h3>
            <p style={{ fontWeight: 300, fontSize: 15, lineHeight: 1.6, color: "#4A453E", margin: "0 0 22px" }}>
              The books assigned by your child&apos;s teacher are already waiting. Just tap the ones you read tonight.
            </p>
            <div
              style={{
                marginTop: "auto",
                background: "#FBFAF6",
                border: "1px solid #E5E2DC",
                borderRadius: 16,
                padding: "14px 12px 12px",
              }}
            >
              <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1A1A1A" }}>
                Tonight&apos;s books
              </div>
              <div style={{ fontWeight: 400, fontSize: 10.5, color: "#6B6B6B", margin: "2px 0 10px" }}>Tap what you read</div>
              <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
                {TONIGHT_BOOKS.map((b) => {
                  const on = booksOn.includes(b.title);
                  return (
                    <div
                      key={b.title}
                      onClick={() => toggleBook(b.title)}
                      style={{
                        background: on ? "rgba(81,186,101,0.08)" : "#fff",
                        border: `1.5px solid ${on ? "#51BA65" : "#E5E2DC"}`,
                        borderRadius: 12,
                        padding: "8px 10px",
                        display: "flex",
                        alignItems: "center",
                        gap: 10,
                        cursor: "pointer",
                        transition: "border-color .2s ease, background .2s ease",
                      }}
                    >
                      <span
                        style={{
                          width: 32,
                          height: 42,
                          borderRadius: 6,
                          background: b.iconGradient,
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          flexShrink: 0,
                        }}
                      >
                        <BookIcon stroke={b.iconStroke} />
                      </span>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div
                          style={{
                            fontWeight: 500,
                            fontSize: 12.5,
                            color: "#1A1A1A",
                            whiteSpace: "nowrap",
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                          }}
                        >
                          {b.title}
                        </div>
                        <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 3 }}>
                          <span
                            style={{
                              fontWeight: 600,
                              fontSize: 9.5,
                              color: b.tagCol,
                              background: b.tagBg,
                              padding: "2px 7px",
                              borderRadius: 20,
                              whiteSpace: "nowrap",
                            }}
                          >
                            {b.tag}
                          </span>
                          {b.extra && (
                            <span style={{ fontWeight: 400, fontSize: 10, color: "#6B6B6B", whiteSpace: "nowrap" }}>
                              {b.extra}
                            </span>
                          )}
                        </div>
                      </div>
                      <span
                        style={{
                          width: 18,
                          height: 18,
                          borderRadius: "50%",
                          background: "#51BA65",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          flexShrink: 0,
                          opacity: on ? 1 : 0,
                          transition: "opacity .2s ease",
                        }}
                      >
                        <CheckIcon />
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>

          {/* step 2 */}
          <div
            style={{
              position: "relative",
              background: "#fff",
              border: "1px solid #ECE7DD",
              borderRadius: 24,
              padding: 30,
              display: "flex",
              flexDirection: "column",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
              <span
                style={{
                  fontFamily: "'Nunito',sans-serif",
                  fontWeight: 900,
                  fontSize: 15,
                  color: "#fff",
                  background: "#1C1812",
                  width: 34,
                  height: 34,
                  borderRadius: "50%",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                2
              </span>
              <span style={{ fontWeight: 300, fontSize: 13, color: "#928B7F" }}>Child taps</span>
            </div>
            <h3 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 22, margin: "22px 0 8px", color: "#1C1812" }}>
              Tap how it felt
            </h3>
            <p style={{ fontWeight: 300, fontSize: 15, lineHeight: 1.6, color: "#4A453E", margin: "0 0 22px" }}>
              Your child taps a friendly Lumi blob, from &quot;tricky&quot; to &quot;great.&quot; It&apos;s theirs to answer, not
              yours.
            </p>
            <div
              style={{
                marginTop: "auto",
                background: "#FBFAF6",
                border: "1px solid #E5E2DC",
                borderRadius: 16,
                padding: "14px 14px 12px",
                marginBottom: 10,
              }}
            >
              <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1A1A1A" }}>
                How long did you read?
              </div>
              <div style={{ display: "flex", gap: 6, marginTop: 9 }}>
                {TIMES.map((t) => {
                  const on = mins === t;
                  return (
                    <span
                      key={t}
                      onClick={() => setMins(t)}
                      style={{
                        flex: 1,
                        textAlign: "center",
                        fontWeight: on ? 700 : 500,
                        fontSize: 12,
                        color: on ? "#2A9FC4" : "#6B6B6B",
                        background: on ? "rgba(86,200,230,0.16)" : "#fff",
                        border: `1.5px solid ${on ? "#56C8E6" : "#E5E2DC"}`,
                        padding: "7px 0",
                        borderRadius: 20,
                        cursor: "pointer",
                        transition: "background .2s ease, border-color .2s ease, color .2s ease",
                      }}
                    >
                      {t}
                    </span>
                  );
                })}
              </div>
            </div>
            <div style={{ background: "#FBFAF6", border: "1px solid #E5E2DC", borderRadius: 16, padding: "14px 8px 12px" }}>
              <div style={{ textAlign: "center", fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1A1A1A" }}>
                How did reading feel?
              </div>
              <div style={{ textAlign: "center", fontWeight: 400, fontSize: 10.5, color: "#6B6B6B", margin: "2px 0 10px" }}>
                Let your child choose
              </div>
              <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "center", gap: 4 }}>
                {BLOBS.map((b) => {
                  const on = blob === b.label;
                  return (
                    <span
                      key={b.label}
                      onClick={() => setBlob(b.label)}
                      style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 5, cursor: "pointer" }}
                    >
                      <span
                        data-hover="pop"
                        style={{
                          width: 38,
                          height: 46,
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          borderRadius: 11,
                          border: `2px solid ${on ? b.col : "transparent"}`,
                          background: on ? `${b.col}29` : "transparent",
                          transform: `scale(${on ? 1.18 : 1})`,
                          transition: "transform .25s cubic-bezier(.34,1.56,.64,1), border-color .2s ease, background .2s ease",
                        }}
                      >
                        <img src={`/assets/blobs/${b.file}`} alt={b.label} style={{ width: 27, height: "auto" }} />
                      </span>
                      <span
                        style={{
                          fontWeight: on ? 800 : 500,
                          fontSize: 10,
                          color: on ? b.col : "rgba(26,26,26,0.7)",
                          transition: "color .2s ease",
                        }}
                      >
                        {b.label}
                      </span>
                    </span>
                  );
                })}
              </div>
            </div>
          </div>

          {/* step 3 */}
          <div
            style={{
              background: "#fff",
              border: "1px solid #ECE7DD",
              borderRadius: 24,
              padding: 30,
              display: "flex",
              flexDirection: "column",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
              <span
                style={{
                  fontFamily: "'Nunito',sans-serif",
                  fontWeight: 900,
                  fontSize: 15,
                  color: "#fff",
                  background: "#1C1812",
                  width: 34,
                  height: 34,
                  borderRadius: "50%",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                3
              </span>
              <span style={{ fontWeight: 300, fontSize: 13, color: "#928B7F" }}>One last tap</span>
            </div>
            <h3 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 22, margin: "22px 0 8px", color: "#1C1812" }}>
              Add a quick chip
            </h3>
            <p style={{ fontWeight: 300, fontSize: 15, lineHeight: 1.6, color: "#4A453E", margin: "0 0 22px" }}>
              Tap chips to build the teacher&apos;s note. Pick up to three that fit the night.
            </p>
            <div style={{ marginTop: "auto", background: "#FBFAF6", border: "1px solid #E5E2DC", borderRadius: 16, padding: "14px 14px 12px" }}>
              <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, color: "#1A1A1A" }}>How did it go?</div>
              <div style={{ fontWeight: 400, fontSize: 10.5, color: "#6B6B6B", margin: "2px 0 10px" }}>
                Select up to 3 that apply (optional)
              </div>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 7 }}>
                {CHIPS.map((label) => {
                  const on = chipsOn.includes(label);
                  const atLimit = chipsOn.length >= 3;
                  const enabled = on || !atLimit;
                  return (
                    <span
                      key={label}
                      onClick={() => toggleChip(label)}
                      style={{
                        display: "inline-flex",
                        alignItems: "center",
                        fontWeight: 500,
                        fontSize: 12,
                        background: on ? "#B5DAB8" : "#fff",
                        border: `1px solid ${on ? "#51BA65" : "#E5E2DC"}`,
                        padding: "7px 13px",
                        borderRadius: 20,
                        color: "#1A1A1A",
                        cursor: "pointer",
                        opacity: enabled ? 1 : 0.4,
                        transition: "background .2s ease, border-color .2s ease, opacity .2s ease",
                      }}
                    >
                      <span style={{ width: 14, flexShrink: 0, opacity: on ? 1 : 0, transition: "opacity .2s ease" }}>✓</span>
                      {label}
                    </span>
                  );
                })}
              </div>
            </div>
          </div>
        </div>

        <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "center", gap: "10px 28px", marginTop: 30 }}>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 9, fontWeight: 300, fontSize: 15, color: "#4A453E" }}>
            <span style={{ width: 8, height: 8, borderRadius: "50%", background: "#51BA65" }} />
            Logs offline, syncs automatically
          </span>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 9, fontWeight: 300, fontSize: 15, color: "#4A453E" }}>
            <span style={{ width: 8, height: 8, borderRadius: "50%", background: "#56C8E6" }} />
            Reminders that fit your routine, morning to bedtime
          </span>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 9, fontWeight: 300, fontSize: 15, color: "#4A453E" }}>
            <span style={{ width: 8, height: 8, borderRadius: "50%", background: "#EC4544" }} />
            One app covers every child in the family
          </span>
        </div>

        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 14, marginTop: 38 }}>
          <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, letterSpacing: "0.02em", color: "#857E73" }}>
            Get the free parent app
          </span>
          <div style={{ display: "flex", gap: 12, flexWrap: "wrap", justifyContent: "center" }}>
            <a
              href="#demo"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 10,
                background: "#1C1812",
                color: "#fff",
                padding: "11px 18px",
                borderRadius: 13,
                textDecoration: "none",
              }}
            >
              <svg width="22" height="22" viewBox="0 0 24 24" fill="#fff">
                <path d="M16.4 12.7c0-2 1.6-3 1.7-3-.9-1.4-2.4-1.5-2.9-1.6-1.2-.1-2.4.7-3 .7-.6 0-1.6-.7-2.6-.7-1.3 0-2.6.8-3.2 2-1.4 2.4-.4 6 1 8 .7.9 1.4 2 2.4 1.9 1-.04 1.3-.6 2.5-.6 1.2 0 1.5.6 2.5.6 1 0 1.7-.9 2.3-1.9.7-1 1-2 1-2-.1 0-2-.8-2.2-2.9ZM14.6 6.3c.5-.7.9-1.6.8-2.5-.8 0-1.7.5-2.3 1.2-.5.6-.9 1.5-.8 2.4.9.05 1.7-.4 2.3-1.1Z" />
              </svg>
              <span style={{ display: "flex", flexDirection: "column", lineHeight: 1.05 }}>
                <span style={{ fontFamily: "'Helvetica Neue',Helvetica,Arial,sans-serif", fontWeight: 300, fontSize: 10, color: "#C9C2B5" }}>
                  Download on the
                </span>
                <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 17, color: "#fff" }}>App Store</span>
              </span>
            </a>
            <a
              href="#demo"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 10,
                background: "#1C1812",
                color: "#fff",
                padding: "11px 18px",
                borderRadius: 13,
                textDecoration: "none",
              }}
            >
              <svg width="20" height="22" viewBox="0 0 24 26" fill="none">
                <path d="M3 2.2 14.5 13 3 23.8c-.4-.2-.7-.7-.7-1.4V3.6c0-.7.3-1.2.7-1.4Z" fill="#56C8E6" />
                <path d="M3 2.2c.3-.15.7-.13 1.1.1l14 8-3.6 2.7L3 2.2Z" fill="#51BA65" />
                <path d="M18.1 10.3 22 12.5c.8.5.8 1.6 0 2l-3.9 2.2-3.6-3.4 3.6-3Z" fill="#FFCB05" />
                <path d="M4.1 23.7c-.4.2-.8.25-1.1.1l11.5-10.8 3.6 3.4-14 7.3Z" fill="#EC4544" />
              </svg>
              <span style={{ display: "flex", flexDirection: "column", lineHeight: 1.05 }}>
                <span style={{ fontFamily: "'Helvetica Neue',Helvetica,Arial,sans-serif", fontWeight: 300, fontSize: 10, color: "#C9C2B5" }}>
                  Get it on
                </span>
                <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 17, color: "#fff" }}>Google Play</span>
              </span>
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
