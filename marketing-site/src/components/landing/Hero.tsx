"use client";

import { useState } from "react";
import Link from "next/link";

const BOOKS = [
  { title: "Bear at the Beach", gradient: "linear-gradient(135deg,#8FD8EE,#C8E8F1)" },
  { title: "The Red Hen", gradient: "linear-gradient(135deg,#9FD8AC,#C5E4CC)" },
  { title: "Mia's Moon Trip", gradient: "linear-gradient(135deg,#F5B9CF,#FBDCE8)" },
  { title: "The Big Race", gradient: "linear-gradient(135deg,#FFD980,#FFEDBB)" },
];

const BLOBS = [
  { file: "blob-hard.png", alt: "Hard", size: 40 },
  { file: "blob-tricky.png", alt: "Tricky", size: 40 },
  { file: "blob-okay.png", alt: "Okay", size: 40 },
  { file: "blob-good.png", alt: "Good", size: 40 },
  { file: "blob-great.png", alt: "Great!", size: 50 },
];

const CHIPS = ["Great job!", "Read with expression", "Sounded out words", "Needed some help", "Retold the story"];

export function Hero() {
  const [demoStage, setDemoStage] = useState(0);
  const [demoStart, setDemoStart] = useState(0);
  const [demoSecs, setDemoSecs] = useState("");

  const pickBook = () => {
    setDemoStage(1);
    setDemoStart((start) => start || Date.now());
  };
  const pickBlob = () => setDemoStage(2);
  const pickChip = () => {
    setDemoStage(3);
    setDemoSecs(Math.max(1, (Date.now() - (demoStart || Date.now())) / 1000).toFixed(1));
  };
  const resetDemo = () => {
    setDemoStage(0);
    setDemoStart(0);
    setDemoSecs("");
  };

  return (
    <section id="hero" className="marketing-hero" style={{ position: "relative", padding: "64px 32px 20px", overflow: "hidden" }}>
      <div style={{ maxWidth: 1180, margin: "0 auto", position: "relative" }}>
        <div
          className="hero-mascot"
          style={{
            position: "absolute",
            left: -6,
            top: 118,
            width: 116,
            animation: "lumiFloatB 6s ease-in-out infinite",
            zIndex: 1,
          }}
        >
          <img
            data-lumi-track
            src="/assets/green_bear.png"
            alt="Green bear Lumi"
            style={{
              display: "block",
              width: 116,
              height: "auto",
              filter: "drop-shadow(0 14px 16px rgba(33,28,22,0.12))",
              transition: "transform .25s ease-out",
            }}
          />
        </div>
        <div
          className="hero-mascot"
          style={{
            position: "absolute",
            right: -8,
            top: 92,
            width: 132,
            animation: "lumiFloat 5.5s ease-in-out infinite",
            zIndex: 1,
          }}
        >
          <img
            data-lumi-track
            src="/assets/lumi-reading.png"
            alt="Lumi reading a book"
            style={{
              display: "block",
              width: 132,
              height: "auto",
              filter: "drop-shadow(0 14px 16px rgba(33,28,22,0.14))",
              transition: "transform .25s ease-out",
            }}
          />
        </div>

        <div style={{ textAlign: "center" }}>
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
            No paper · No typing · Just seconds
          </span>
          <h1
            className="marketing-hero-title"
            style={{
              fontFamily: "'Nunito',sans-serif",
              fontWeight: 900,
              fontSize: 62,
              lineHeight: 1.02,
              letterSpacing: "-0.025em",
              margin: "20px auto 0",
              maxWidth: 860,
              color: "#1C1812",
            }}
          >
            Nightly reading, logged in seconds.
          </h1>
          <p
            className="marketing-hero-copy"
            style={{
              fontWeight: 300,
              fontSize: 20,
              lineHeight: 1.6,
              color: "#4A453E",
              margin: "20px auto 0",
              maxWidth: 620,
            }}
          >
            Lumi replaces the paper reading diary with a tap-only nightly log for parents and a live class dashboard
            for teachers, keeping real, physical books at the centre of reading.
          </p>
          <div className="marketing-hero-actions" style={{ display: "flex", gap: 14, justifyContent: "center", marginTop: 30 }}>
            <Link
              href="/book-a-demo"
              style={{
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 800,
                fontSize: 17,
                color: "#fff",
                background: "#EC4544",
                padding: "16px 30px",
                borderRadius: 999,
                textDecoration: "none",
                boxShadow: "0 12px 24px -12px rgba(236,69,68,0.7)",
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
                color: "#1C1812",
                background: "#fff",
                border: "1.5px solid #E0DBD0",
                padding: "16px 30px",
                borderRadius: 999,
                textDecoration: "none",
              }}
            >
              Contact sales
            </Link>
          </div>
        </div>

        {/* bento grid */}
        <div
          data-anim="bento"
          className="marketing-hero-bento"
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(3, 1fr)",
            gridAutoRows: 176,
            gap: 18,
            marginTop: 46,
          }}
        >
          {/* Try it: log a night */}
          <div
            style={{
              gridRow: "span 2",
              background: "#FFCB05",
              borderRadius: 24,
              padding: 28,
              display: "flex",
              flexDirection: "column",
              justifyContent: "space-between",
              overflow: "hidden",
            }}
          >
            <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 8 }}>
              <span
                style={{
                  fontFamily: "'Nunito',sans-serif",
                  fontWeight: 900,
                  fontSize: 22,
                  lineHeight: 1.15,
                  color: "#3A2E00",
                }}
              >
                Try it: log a night
              </span>
              <span
                style={{
                  fontFamily: "'Nunito',sans-serif",
                  fontWeight: 800,
                  fontSize: 10,
                  letterSpacing: "0.08em",
                  textTransform: "uppercase",
                  color: "#FFCB05",
                  background: "#3A2E00",
                  padding: "5px 10px",
                  borderRadius: 999,
                  whiteSpace: "nowrap",
                  flexShrink: 0,
                }}
              >
                Live demo
              </span>
            </div>

            {demoStage === 0 && (
              <div style={{ display: "flex", flexDirection: "column", justifyContent: "flex-end", gap: 8 }}>
                <p style={{ fontWeight: 300, fontSize: 13, color: "#6B5600", margin: "0 0 2px" }}>
                  1 of 3 · Tap tonight&apos;s book
                </p>
                {BOOKS.map((b) => (
                  <div
                    key={b.title}
                    onClick={pickBook}
                    data-hover="lift"
                    style={{
                      background: "#fff",
                      borderRadius: 12,
                      padding: "9px 11px",
                      display: "flex",
                      alignItems: "center",
                      gap: 10,
                      cursor: "pointer",
                      transition: "transform .2s ease",
                      boxShadow: "0 2px 6px rgba(58,46,0,0.12)",
                    }}
                  >
                    <span
                      style={{
                        width: 26,
                        height: 34,
                        borderRadius: 5,
                        background: b.gradient,
                        flexShrink: 0,
                      }}
                    />
                    <span style={{ fontWeight: 500, fontSize: 13, color: "#1A1A1A" }}>{b.title}</span>
                  </div>
                ))}
              </div>
            )}

            {demoStage === 1 && (
              <div style={{ display: "flex", flexDirection: "column", justifyContent: "flex-end", gap: 8 }}>
                <p style={{ fontWeight: 300, fontSize: 13, color: "#6B5600", margin: "0 0 2px" }}>
                  2 of 3 · Tap how it felt
                </p>
                <div
                  style={{
                    display: "flex",
                    gap: 9,
                    alignItems: "flex-end",
                    justifyContent: "center",
                    background: "rgba(255,255,255,0.8)",
                    borderRadius: 14,
                    padding: "16px 10px",
                  }}
                >
                  {BLOBS.map((b) => (
                    <img
                      key={b.file}
                      onClick={pickBlob}
                      src={`/assets/blobs/${b.file}`}
                      alt={b.alt}
                      data-hover="pop"
                      style={{
                        width: b.size,
                        height: "auto",
                        cursor: "pointer",
                        transition: "transform .2s cubic-bezier(.34,1.56,.64,1)",
                      }}
                    />
                  ))}
                </div>
              </div>
            )}

            {demoStage === 2 && (
              <div style={{ display: "flex", flexDirection: "column", justifyContent: "flex-end", gap: 8 }}>
                <p style={{ fontWeight: 300, fontSize: 13, color: "#6B5600", margin: "0 0 2px" }}>
                  3 of 3 · Add a quick comment chip
                </p>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 8, justifyContent: "center" }}>
                  {CHIPS.map((label) => (
                    <span
                      key={label}
                      onClick={pickChip}
                      data-hover="lift"
                      style={{
                        background: "#fff",
                        borderRadius: 999,
                        padding: "10px 15px",
                        fontWeight: 500,
                        fontSize: 13,
                        color: "#1A1A1A",
                        cursor: "pointer",
                        transition: "transform .2s ease",
                        boxShadow: "0 2px 6px rgba(58,46,0,0.12)",
                      }}
                    >
                      {label}
                    </span>
                  ))}
                </div>
              </div>
            )}

            {demoStage === 3 && (
              <div
                style={{
                  position: "relative",
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  justifyContent: "flex-end",
                  textAlign: "center",
                }}
              >
                <span
                  style={{
                    position: "absolute",
                    top: -4,
                    left: "6%",
                    width: 8,
                    height: 8,
                    borderRadius: 2,
                    background: "#EC4544",
                    animation: "confettiFall 1s ease-in 0s both",
                  }}
                />
                <span
                  style={{
                    position: "absolute",
                    top: -4,
                    left: "18%",
                    width: 7,
                    height: 7,
                    borderRadius: "50%",
                    background: "#51BA65",
                    animation: "confettiFall 1.1s ease-in .08s both",
                  }}
                />
                <span
                  style={{
                    position: "absolute",
                    top: -4,
                    left: "30%",
                    width: 8,
                    height: 8,
                    borderRadius: 2,
                    background: "#56C8E6",
                    animation: "confettiFall .95s ease-in .16s both",
                  }}
                />
                <span
                  style={{
                    position: "absolute",
                    top: -4,
                    left: "42%",
                    width: 7,
                    height: 7,
                    borderRadius: "50%",
                    background: "#fff",
                    animation: "confettiFall 1.05s ease-in .04s both",
                  }}
                />
                <span
                  style={{
                    position: "absolute",
                    top: -4,
                    left: "54%",
                    width: 8,
                    height: 8,
                    borderRadius: 2,
                    background: "#F5A1C5",
                    animation: "confettiFall 1s ease-in .2s both",
                  }}
                />
                <span
                  style={{
                    position: "absolute",
                    top: -4,
                    left: "66%",
                    width: 7,
                    height: 7,
                    borderRadius: "50%",
                    background: "#EC4544",
                    animation: "confettiFall 1.1s ease-in .12s both",
                  }}
                />
                <span
                  style={{
                    position: "absolute",
                    top: -4,
                    left: "78%",
                    width: 8,
                    height: 8,
                    borderRadius: 2,
                    background: "#51BA65",
                    animation: "confettiFall .9s ease-in .24s both",
                  }}
                />
                <span
                  style={{
                    position: "absolute",
                    top: -4,
                    left: "90%",
                    width: 7,
                    height: 7,
                    borderRadius: "50%",
                    background: "#56C8E6",
                    animation: "confettiFall 1.05s ease-in .06s both",
                  }}
                />
                <img
                  src="/assets/lumi-trophy.png"
                  alt="Lumi celebrating"
                  style={{ width: 88, height: "auto", animation: "popIn .5s cubic-bezier(.34,1.56,.64,1) both" }}
                />
                <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 20, color: "#3A2E00", marginTop: 8 }}>
                  Logged in {demoSecs}s!
                </div>
                <p style={{ fontWeight: 300, fontSize: 12.5, color: "#6B5600", margin: "4px 0 0" }}>
                  That&apos;s the whole reading diary. No typing.
                </p>
                <span
                  onClick={resetDemo}
                  style={{
                    marginTop: 9,
                    fontFamily: "'Nunito',sans-serif",
                    fontWeight: 800,
                    fontSize: 12,
                    color: "#3A2E00",
                    textDecoration: "underline",
                    cursor: "pointer",
                  }}
                >
                  Try again
                </span>
              </div>
            )}
          </div>

          {/* live dashboard */}
          <div
            style={{
              gridColumn: "span 2",
              background: "#56C8E6",
              borderRadius: 24,
              padding: 28,
              display: "flex",
              alignItems: "center",
              gap: 26,
              overflow: "hidden",
            }}
          >
            <div style={{ flex: 1 }}>
              <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 24, color: "#06384A" }}>
                A live dashboard for every class
              </span>
              <p style={{ fontWeight: 300, fontSize: 15, color: "#0B4A60", margin: "8px 0 0", maxWidth: 300 }}>
                Engagement charts and priority nudges for students who haven&apos;t read.
              </p>
            </div>
            <div
              style={{
                display: "flex",
                alignItems: "flex-end",
                gap: 8,
                height: 104,
                background: "rgba(255,255,255,0.55)",
                padding: 16,
                borderRadius: 16,
              }}
            >
              {[46, 72, 34, 64, 84].map((h, i) => (
                <span key={i} style={{ width: 17, height: h, background: "#1989CA", borderRadius: 4 }} />
              ))}
            </div>
          </div>

          {/* allocate books */}
          <div
            style={{
              background: "#51BA65",
              borderRadius: 24,
              padding: 28,
              display: "flex",
              flexDirection: "column",
              justifyContent: "space-between",
              overflow: "hidden",
            }}
          >
            <span
              style={{
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 900,
                fontSize: 21,
                lineHeight: 1.15,
                color: "#0C3A18",
              }}
            >
              Allocate books your way
            </span>
            <div style={{ display: "flex", gap: 7, flexWrap: "wrap" }}>
              {["Reading groups", "Themes", "Genres", "Free choice"].map((t) => (
                <span
                  key={t}
                  style={{
                    fontWeight: 300,
                    fontSize: 13,
                    background: "rgba(255,255,255,0.65)",
                    padding: "6px 12px",
                    borderRadius: 999,
                    color: "#0C3A18",
                  }}
                >
                  {t}
                </span>
              ))}
            </div>
          </div>

          {/* achievements */}
          <div
            style={{
              position: "relative",
              background: "#EC4544",
              borderRadius: 24,
              padding: 28,
              display: "flex",
              flexDirection: "column",
              justifyContent: "space-between",
              overflow: "hidden",
            }}
          >
            <span
              style={{
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 900,
                fontSize: 21,
                lineHeight: 1.15,
                color: "#fff",
                maxWidth: 150,
              }}
            >
              Achievements unlock as they read
            </span>
            <span style={{ fontWeight: 300, fontSize: 14, color: "#FFE0DF", maxWidth: 132 }}>
              Badges, streaks and celebrations
            </span>
            <div
              style={{
                position: "absolute",
                right: -4,
                bottom: -10,
                width: 104,
                animation: "lumiFloatB 5s ease-in-out infinite",
              }}
            >
              <img
                data-lumi-track
                src="/assets/lumi-blue.png"
                alt="Lumi"
                style={{ display: "block", width: 104, height: "auto", transition: "transform .25s ease-out" }}
              />
            </div>
          </div>

          {/* scan ISBNs */}
          <div
            style={{
              background: "#fff",
              border: "1px solid #ECE7DD",
              borderRadius: 24,
              padding: 28,
              display: "flex",
              flexDirection: "column",
              justifyContent: "space-between",
              overflow: "hidden",
            }}
          >
            <span
              style={{
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 900,
                fontSize: 21,
                lineHeight: 1.15,
                color: "#1C1812",
              }}
            >
              Build your library by scanning ISBNs
            </span>
            <div
              style={{
                position: "relative",
                display: "inline-flex",
                alignSelf: "flex-start",
                gap: 4,
                alignItems: "flex-end",
                height: 40,
              }}
            >
              <span
                style={{
                  position: "absolute",
                  top: -6,
                  bottom: -6,
                  left: 2,
                  width: 2,
                  background: "#EC4544",
                  boxShadow: "0 0 8px rgba(236,69,68,0.8)",
                  borderRadius: 2,
                  animation: "scanSweep 2.8s ease-in-out infinite",
                }}
              />
              {[4, 3, 6, 3, 5, 3, 7, 3, 4, 6, 3, 5, 3, 6, 4, 3, 7, 3, 5, 4].map((w, i) => (
                <span key={i} style={{ width: w, height: 40, background: "#211C16" }} />
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
