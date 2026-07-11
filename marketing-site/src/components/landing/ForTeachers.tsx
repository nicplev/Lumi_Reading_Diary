"use client";

import { useState } from "react";

interface StudentLog {
  blob: string;
  title: string;
  when: string;
}

interface Student {
  name: string;
  sub: string;
  subCol: string;
  mark: string;
  bg: string;
  avatar: string;
  streak: number;
  books: number;
  badges: number;
  logs: StudentLog[];
}

const ROSTER: Student[] = [
  {
    name: "Ava",
    sub: "Read tonight · Great!",
    subCol: "#3C9B53",
    mark: "✓",
    bg: "#FFEDBB",
    avatar: "/assets/lumi-pink.png",
    streak: 8,
    books: 31,
    badges: 6,
    logs: [
      { blob: "/assets/blobs/blob-great.png", title: "Bear at the Beach", when: "Tonight" },
      { blob: "/assets/blobs/blob-good.png", title: "The Red Hen", when: "Yesterday" },
      { blob: "/assets/blobs/blob-okay.png", title: "The Big Race", when: "Sunday" },
    ],
  },
  {
    name: "Jye",
    sub: "Last read 4 days ago",
    subCol: "#EC4544",
    mark: "",
    bg: "#C8E8F1",
    avatar: "/assets/lumi-frog.png",
    streak: 0,
    books: 12,
    badges: 3,
    logs: [
      { blob: "/assets/blobs/blob-tricky.png", title: "Mia's Moon Trip", when: "Thursday" },
      { blob: "/assets/blobs/blob-okay.png", title: "The Red Hen", when: "Wednesday" },
      { blob: "/assets/blobs/blob-good.png", title: "Bear at the Beach", when: "Tuesday" },
    ],
  },
  {
    name: "Mia",
    sub: "14-day reading streak! 🔥",
    subCol: "#6B6B6B",
    mark: "✓",
    bg: "#FBE89F",
    avatar: "/assets/lumi-tiger.png",
    streak: 14,
    books: 42,
    badges: 9,
    logs: [
      { blob: "/assets/blobs/blob-great.png", title: "The Big Race", when: "Tonight" },
      { blob: "/assets/blobs/blob-great.png", title: "Bear at the Beach", when: "Yesterday" },
      { blob: "/assets/blobs/blob-good.png", title: "Mia's Moon Trip", when: "Saturday" },
    ],
  },
  {
    name: "Noah",
    sub: "Read tonight · Good",
    subCol: "#3C9B53",
    mark: "✓",
    bg: "#C5E4CC",
    avatar: "/assets/lumi-green.png",
    streak: 5,
    books: 24,
    badges: 5,
    logs: [
      { blob: "/assets/blobs/blob-good.png", title: "The Red Hen", when: "Tonight" },
      { blob: "/assets/blobs/blob-okay.png", title: "The Big Race", when: "Yesterday" },
      { blob: "/assets/blobs/blob-good.png", title: "Bear at the Beach", when: "Friday" },
    ],
  },
  {
    name: "Oliver",
    sub: "25 books read! 📚",
    subCol: "#6B6B6B",
    mark: "✓",
    bg: "#FBE89F",
    avatar: "/assets/lumi-penguin.png",
    streak: 11,
    books: 25,
    badges: 7,
    logs: [
      { blob: "/assets/blobs/blob-great.png", title: "Mia's Moon Trip", when: "Tonight" },
      { blob: "/assets/blobs/blob-good.png", title: "The Big Race", when: "Yesterday" },
      { blob: "/assets/blobs/blob-great.png", title: "The Red Hen", when: "Sunday" },
    ],
  },
  {
    name: "Isla",
    sub: "Not logged yet tonight",
    subCol: "#C79400",
    mark: "",
    bg: "#FFD9D9",
    avatar: "/assets/lumi-red.png",
    streak: 2,
    books: 18,
    badges: 4,
    logs: [
      { blob: "/assets/blobs/blob-okay.png", title: "Bear at the Beach", when: "Yesterday" },
      { blob: "/assets/blobs/blob-tricky.png", title: "The Red Hen", when: "Saturday" },
      { blob: "/assets/blobs/blob-good.png", title: "The Big Race", when: "Friday" },
    ],
  },
];

const TEACHER_BOOKS = [
  { title: "Bear at the Beach", meta: "Decodable set · 6 copies", tag: "Set A", col: "#8FD8EE" },
  { title: "The Red Hen", meta: "Decodable set · 8 copies", tag: "Set A", col: "#9FD8AC" },
  { title: "Mia's Moon Trip", meta: "Picture book · 4 copies", tag: "Theme", col: "#F5B9CF" },
  { title: "The Big Race", meta: "Picture book · 5 copies", tag: "Free", col: "#FFD980" },
];

const ATTENTION_IDX = [1, 2, 4];

function StudentAvatar({ bg, avatar, size = 32, imgSize = 24 }: { bg: string; avatar: string; size?: number; imgSize?: number }) {
  return (
    <span style={{ width: size, height: size, borderRadius: "50%", background: bg, overflow: "hidden", flexShrink: 0 }}>
      <span
        style={{
          display: "block",
          width: "100%",
          height: "100%",
          backgroundImage: `url('${avatar}')`,
          backgroundSize: `${imgSize}px auto`,
          backgroundRepeat: "no-repeat",
          backgroundPosition: "center bottom",
        }}
      />
    </span>
  );
}

type Tab = "dash" | "class" | "lib" | "set";

export function ForTeachers() {
  const [tab, setTab] = useState<Tab>("dash");
  const [student, setStudent] = useState<Student | null>(null);
  const [notif, setNotif] = useState(true);
  const [mile, setMile] = useState(true);

  const goTab = (t: Tab) => {
    setTab(t);
    setStudent(null);
  };

  const onColor = "#51BA65";
  const offColor = "#D6D2C9";
  const tc = (t: Tab) => (tab === t ? "#56C8E6" : "#6B6B6B");

  return (
    <section id="teachers" style={{ padding: "78px 32px", background: "#fff", borderTop: "1px solid #ECE7DD", borderBottom: "1px solid #ECE7DD" }}>
      <div style={{ maxWidth: 1180, margin: "0 auto", display: "grid", gridTemplateColumns: "1fr 1.05fr", gap: 56, alignItems: "center" }}>
        <div data-anim="reveal-left">
          <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, letterSpacing: "0.12em", textTransform: "uppercase", color: "#1989CA" }}>
            For teachers
          </span>
          <h2 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 44, lineHeight: 1.07, letterSpacing: "-0.02em", margin: "14px 0 0", color: "#1C1812" }}>
            Every reading session, live on one class dashboard.
          </h2>
          <p style={{ fontWeight: 300, fontSize: 18, lineHeight: 1.6, color: "#4A453E", margin: "18px 0 0", maxWidth: "52ch" }}>
            See who read last night, read parent comments as they come in, and watch how reading{" "}
            <em style={{ fontStyle: "normal", fontWeight: 600, color: "#1C1812" }}>feels</em> trend over time as students tap the
            mood blobs. Celebrate milestones like &quot;Sarah reached 50 nights!&quot;, and assign the next round of readers in two
            taps. No more chasing paper journals.
          </p>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14, marginTop: 30 }}>
            <div style={{ display: "flex", alignItems: "flex-start", gap: 12 }}>
              <span style={{ width: 30, height: 30, borderRadius: 9, background: "#DCF0F8", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                  <path d="M4 19V5M4 19h16M8 16v-5M12 16V8M16 16v-3" stroke="#1989CA" strokeWidth="2" strokeLinecap="round" />
                </svg>
              </span>
              <span style={{ fontWeight: 300, fontSize: 15, lineHeight: 1.45, color: "#3A352E" }}>
                <strong style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800 }}>Engagement charts</strong> across the class
                and over time
              </span>
            </div>
            <div style={{ display: "flex", alignItems: "flex-start", gap: 12 }}>
              <span style={{ width: 30, height: 30, borderRadius: 9, background: "#FFE0DF", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                  <path d="M12 3v10M12 21h.01" stroke="#EC4544" strokeWidth="2.4" strokeLinecap="round" />
                </svg>
              </span>
              <span style={{ fontWeight: 300, fontSize: 15, lineHeight: 1.45, color: "#3A352E" }}>
                <strong style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800 }}>Priority nudges</strong> for students who
                haven&apos;t read
              </span>
            </div>
            <div style={{ display: "flex", alignItems: "flex-start", gap: 12 }}>
              <span style={{ width: 30, height: 30, borderRadius: 9, background: "#DFF0E3", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                  <path d="M4 6h16M4 12h16M4 18h10" stroke="#3C9B53" strokeWidth="2" strokeLinecap="round" />
                </svg>
              </span>
              <span style={{ fontWeight: 300, fontSize: 15, lineHeight: 1.45, color: "#3A352E" }}>
                <strong style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800 }}>Allocate books</strong> by group, theme,
                genre or choice
              </span>
            </div>
            <div style={{ display: "flex", alignItems: "flex-start", gap: 12 }}>
              <span style={{ width: 30, height: 30, borderRadius: 9, background: "#FFF1C2", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                  <path d="M4 7v10M7 7v10M10 7v10M14 7v10M17 7v10M20 7v10" stroke="#C79400" strokeWidth="1.8" strokeLinecap="round" />
                </svg>
              </span>
              <span style={{ fontWeight: 300, fontSize: 15, lineHeight: 1.45, color: "#3A352E" }}>
                <strong style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800 }}>Scan ISBNs</strong> to build your library in
                minutes
              </span>
            </div>
          </div>
          <p style={{ fontWeight: 300, fontSize: 14, color: "#857E73", margin: "22px 0 0" }}>
            Set allocations on daily, weekly or fortnightly schedules, by reading group, theme, genre, title or free choice. Lumi
            fits however your school runs home reading.
          </p>
          <div style={{ display: "flex", alignItems: "flex-start", gap: 11, marginTop: 20, background: "#F1F8F3", border: "1px solid #DDEEE1", borderRadius: 14, padding: "14px 16px" }}>
            <span style={{ width: 26, height: 26, borderRadius: 8, background: "#DFF0E3", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none">
                <path d="M12 21s-7-4.5-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 11c0 5.5-7 10-7 10Z" stroke="#3C9B53" strokeWidth="2" strokeLinejoin="round" />
              </svg>
            </span>
            <span style={{ fontWeight: 300, fontSize: 14, lineHeight: 1.5, color: "#3A352E" }}>
              <strong style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800 }}>Designed to encourage, not police.</strong>{" "}
              Streaks include rest days and nudges stay gentle, so home reading feels supportive for every family, not like
              surveillance.
            </span>
          </div>
        </div>

        {/* teacher phone mockup */}
        <div data-anim="reveal-right" style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 16 }}>
          <span
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 7,
              fontFamily: "'Nunito',sans-serif",
              fontWeight: 800,
              fontSize: 12.5,
              color: "#1989CA",
              background: "#DCF0F8",
              padding: "8px 14px",
              borderRadius: 999,
            }}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
              <path
                d="M9 11.5V5.5a1.8 1.8 0 0 1 3.6 0v5M12.6 10.5V4.6a1.8 1.8 0 0 1 3.6 0v6M16.2 11V6.6a1.8 1.8 0 0 1 3.6 0V14c0 3.9-2.6 6.5-6.5 6.5-2.2 0-3.7-.8-5-2.4l-2.6-3.3a1.8 1.8 0 0 1 2.7-2.3l1.4 1.4V8.4a1.8 1.8 0 0 1 3.6 0v3.1"
                stroke="#1989CA"
                strokeWidth="1.8"
                strokeLinejoin="round"
              />
            </svg>
            Try it, tap around the tabs
          </span>
          <div style={{ width: 296, background: "#1A1A1A", borderRadius: 44, padding: 9, boxShadow: "0 3px 6px rgba(26,26,26,0.1), 0 32px 64px -24px rgba(26,26,26,0.35)" }}>
            <div style={{ position: "relative", background: "#FBFAF6", borderRadius: 36, overflow: "hidden", padding: "10px 12px 14px" }}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "4px 10px 8px" }}>
                <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 11, color: "#1A1A1A" }}>9:41</span>
                <span style={{ width: 64, height: 18, background: "#1A1A1A", borderRadius: 999 }} />
                <span style={{ display: "flex", gap: 3, alignItems: "center" }}>
                  <svg width="12" height="10" viewBox="0 0 16 12" fill="#1A1A1A">
                    <rect x="0" y="7" width="3" height="5" rx="1" />
                    <rect x="4.5" y="4.5" width="3" height="7.5" rx="1" />
                    <rect x="9" y="2" width="3" height="10" rx="1" />
                  </svg>
                  <svg width="16" height="10" viewBox="0 0 22 12" fill="none">
                    <rect x="0.5" y="0.5" width="18" height="11" rx="3" stroke="#1A1A1A" />
                    <rect x="2" y="2" width="13" height="8" rx="2" fill="#1A1A1A" />
                    <path d="M20.5 4v4c1-0.3 1.5-1 1.5-2s-0.5-1.7-1.5-2Z" fill="#1A1A1A" />
                  </svg>
                </span>
              </div>

              <div style={{ height: 500, position: "relative", overflow: "hidden" }}>
                {/* DASHBOARD */}
                {tab === "dash" && !student && (
                  <div style={{ animation: "lumiRise .4s cubic-bezier(.16,.84,.44,1) both" }}>
                    <div style={{ background: "#56C8E6", borderRadius: 22, padding: "16px 16px 14px", marginBottom: 10 }}>
                      <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 17, letterSpacing: "-0.01em", color: "#fff" }}>
                        Good morning, Sarah
                      </div>
                      <div style={{ fontWeight: 400, fontSize: 11, color: "rgba(255,255,255,0.85)", marginTop: 2 }}>Monday, 6 July</div>
                      <span
                        style={{
                          display: "inline-flex",
                          alignItems: "center",
                          gap: 5,
                          marginTop: 11,
                          fontFamily: "'Nunito',sans-serif",
                          fontWeight: 800,
                          fontSize: 11.5,
                          color: "#fff",
                          background: "rgba(255,255,255,0.22)",
                          padding: "7px 13px",
                          borderRadius: 20,
                        }}
                      >
                        Class 3B{" "}
                        <svg width="9" height="9" viewBox="0 0 24 24" fill="none">
                          <path d="M6 9l6 6 6-6" stroke="#fff" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
                        </svg>
                      </span>
                    </div>
                    <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 22, padding: "14px 16px", marginBottom: 10, display: "flex", alignItems: "center", gap: 14, boxShadow: "0 1px 2px rgba(26,26,26,0.04)" }}>
                      <svg width="76" height="76" viewBox="0 0 76 76" style={{ flexShrink: 0 }}>
                        <circle cx="38" cy="38" r="30" fill="none" stroke="#E5E2DC" strokeWidth="7" />
                        <circle
                          data-draw="ring"
                          cx="38"
                          cy="38"
                          r="30"
                          fill="none"
                          stroke="#56C8E6"
                          strokeWidth="7"
                          strokeLinecap="round"
                          strokeDasharray="159.5 188.5"
                          transform="rotate(-90 38 38)"
                        />
                        <text x="38" y="36" textAnchor="middle" fontFamily="Nunito, sans-serif" fontWeight="800" fontSize="16" fill="#1A1A1A">
                          22/26
                        </text>
                        <text x="38" y="49" textAnchor="middle" fontSize="8" fontWeight="600" fill="#6B6B6B">
                          read today
                        </text>
                      </svg>
                      <div style={{ flex: 1 }}>
                        <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13.5, color: "#1A1A1A" }}>Today&apos;s engagement</div>
                        <div style={{ display: "flex", flexDirection: "column", gap: 4, marginTop: 7 }}>
                          <span style={{ display: "flex", alignItems: "center", gap: 6, fontWeight: 400, fontSize: 11, color: "#6B6B6B" }}>
                            <span style={{ width: 7, height: 7, borderRadius: "50%", background: "#51BA65" }} />
                            14 on a streak
                          </span>
                          <span style={{ display: "flex", alignItems: "center", gap: 6, fontWeight: 400, fontSize: 11, color: "#6B6B6B" }}>
                            <span style={{ width: 7, height: 7, borderRadius: "50%", background: "#F2B705" }} />
                            31 books logged
                          </span>
                          <span style={{ display: "flex", alignItems: "center", gap: 6, fontWeight: 400, fontSize: 11, color: "#6B6B6B" }}>
                            <span style={{ width: 7, height: 7, borderRadius: "50%", background: "#EC4544" }} />
                            4 still to read
                          </span>
                        </div>
                      </div>
                    </div>
                    <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 22, padding: "14px 16px", boxShadow: "0 1px 2px rgba(26,26,26,0.04)" }}>
                      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
                        <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13.5, color: "#1A1A1A" }}>Needs attention</span>
                        <span style={{ fontWeight: 600, fontSize: 10.5, color: "#6B6B6B" }}>3 students</span>
                      </div>
                      {ATTENTION_IDX.map((idx) => {
                        const s = ROSTER[idx];
                        return (
                          <div key={s.name} onClick={() => setStudent(s)} style={{ display: "flex", alignItems: "center", gap: 10, padding: "7px 0", cursor: "pointer" }}>
                            <StudentAvatar bg={s.bg} avatar={s.avatar} />
                            <span style={{ flex: 1, minWidth: 0 }}>
                              <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 700, fontSize: 12.5, color: "#1A1A1A" }}>{s.name}</span>
                              <span style={{ display: "block", fontWeight: 400, fontSize: 10.5, color: s.subCol }}>{s.sub}</span>
                            </span>
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                              <path d="M9 6l6 6-6 6" stroke="rgba(107,107,107,0.5)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
                            </svg>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}

                {/* CLASS */}
                {tab === "class" && !student && (
                  <div style={{ animation: "lumiRise .4s cubic-bezier(.16,.84,.44,1) both" }}>
                    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "4px 4px 10px" }}>
                      <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 16, color: "#1A1A1A" }}>Class 3B</span>
                      <span style={{ fontWeight: 600, fontSize: 10.5, color: "#6B6B6B" }}>26 students</span>
                    </div>
                    <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 22, padding: "8px 16px", boxShadow: "0 1px 2px rgba(26,26,26,0.04)" }}>
                      {ROSTER.map((s) => (
                        <div key={s.name} onClick={() => setStudent(s)} style={{ display: "flex", alignItems: "center", gap: 10, padding: "8px 0", cursor: "pointer", borderBottom: "1px solid #F2EFE8" }}>
                          <StudentAvatar bg={s.bg} avatar={s.avatar} />
                          <span style={{ flex: 1, minWidth: 0 }}>
                            <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 700, fontSize: 12.5, color: "#1A1A1A" }}>{s.name}</span>
                            <span style={{ display: "block", fontWeight: 400, fontSize: 10.5, color: s.subCol }}>{s.sub}</span>
                          </span>
                          <span style={{ fontSize: 12 }}>{s.mark}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* LIBRARY */}
                {tab === "lib" && !student && (
                  <div style={{ animation: "lumiRise .4s cubic-bezier(.16,.84,.44,1) both" }}>
                    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "4px 4px 10px" }}>
                      <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 16, color: "#1A1A1A" }}>Library</span>
                      <span style={{ fontWeight: 600, fontSize: 10.5, color: "#6B6B6B" }}>124 books</span>
                    </div>
                    <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 22, padding: "8px 16px", marginBottom: 10, boxShadow: "0 1px 2px rgba(26,26,26,0.04)" }}>
                      {TEACHER_BOOKS.map((b) => (
                        <div key={b.title} style={{ display: "flex", alignItems: "center", gap: 10, padding: "8px 0", borderBottom: "1px solid #F2EFE8" }}>
                          <span style={{ width: 24, height: 32, borderRadius: 4, background: b.col, flexShrink: 0 }} />
                          <span style={{ flex: 1, minWidth: 0 }}>
                            <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 700, fontSize: 12, color: "#1A1A1A", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                              {b.title}
                            </span>
                            <span style={{ display: "block", fontWeight: 400, fontSize: 10, color: "#6B6B6B" }}>{b.meta}</span>
                          </span>
                          <span style={{ fontWeight: 600, fontSize: 9.5, color: "#2A9FC4", background: "rgba(86,200,230,0.15)", padding: "3px 8px", borderRadius: 20, whiteSpace: "nowrap" }}>
                            {b.tag}
                          </span>
                        </div>
                      ))}
                    </div>
                    <div style={{ background: "#EC4544", borderRadius: 18, padding: 12, display: "flex", alignItems: "center", justifyContent: "center", gap: 8, boxShadow: "0 8px 18px -8px rgba(236,69,68,0.6)" }}>
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                        <path d="M3 8V5a2 2 0 012-2h3M16 3h3a2 2 0 012 2v3M21 16v3a2 2 0 01-2 2h-3M8 21H5a2 2 0 01-2-2v-3M7 12h1M11 12h1M15 12h2" stroke="#fff" strokeWidth="2" strokeLinecap="round" />
                      </svg>
                      <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 12.5, color: "#fff" }}>Scan ISBN to add books</span>
                    </div>
                  </div>
                )}

                {/* SETTINGS */}
                {tab === "set" && !student && (
                  <div style={{ animation: "lumiRise .4s cubic-bezier(.16,.84,.44,1) both" }}>
                    <div style={{ padding: "4px 4px 10px" }}>
                      <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 16, color: "#1A1A1A" }}>Settings</span>
                    </div>
                    <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 22, padding: "6px 16px", marginBottom: 10, boxShadow: "0 1px 2px rgba(26,26,26,0.04)" }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "10px 0", borderBottom: "1px solid #F2EFE8" }}>
                        <span
                          style={{
                            width: 34,
                            height: 34,
                            borderRadius: "50%",
                            background: "#DCF0F8",
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            fontFamily: "'Nunito',sans-serif",
                            fontWeight: 800,
                            fontSize: 12,
                            color: "#1989CA",
                            flexShrink: 0,
                          }}
                        >
                          SW
                        </span>
                        <span style={{ flex: 1 }}>
                          <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 700, fontSize: 12.5, color: "#1A1A1A" }}>Sarah Wilson</span>
                          <span style={{ display: "block", fontWeight: 400, fontSize: 10.5, color: "#6B6B6B" }}>Class 3B teacher</span>
                        </span>
                      </div>
                      <div onClick={() => setNotif((v) => !v)} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "11px 0", borderBottom: "1px solid #F2EFE8", cursor: "pointer" }}>
                        <span style={{ fontWeight: 400, fontSize: 12, color: "#1A1A1A" }}>Daily summary notification</span>
                        <span style={{ width: 34, height: 20, borderRadius: 20, background: notif ? onColor : offColor, position: "relative", transition: "background .25s ease", flexShrink: 0 }}>
                          <span style={{ position: "absolute", top: 2, left: notif ? 16 : 2, width: 16, height: 16, borderRadius: "50%", background: "#fff", boxShadow: "0 1px 3px rgba(0,0,0,0.25)", transition: "left .25s ease" }} />
                        </span>
                      </div>
                      <div onClick={() => setMile((v) => !v)} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "11px 0", cursor: "pointer" }}>
                        <span style={{ fontWeight: 400, fontSize: 12, color: "#1A1A1A" }}>Milestone celebrations</span>
                        <span style={{ width: 34, height: 20, borderRadius: 20, background: mile ? onColor : offColor, position: "relative", transition: "background .25s ease", flexShrink: 0 }}>
                          <span style={{ position: "absolute", top: 2, left: mile ? 16 : 2, width: 16, height: 16, borderRadius: "50%", background: "#fff", boxShadow: "0 1px 3px rgba(0,0,0,0.25)", transition: "left .25s ease" }} />
                        </span>
                      </div>
                    </div>
                    <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 22, padding: "12px 16px", boxShadow: "0 1px 2px rgba(26,26,26,0.04)" }}>
                      <span style={{ display: "block", fontWeight: 400, fontSize: 10.5, color: "#6B6B6B" }}>Parent linking code</span>
                      <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 17, letterSpacing: "0.08em", color: "#1A1A1A", marginTop: 2 }}>
                        LUMI-7F3K
                      </span>
                    </div>
                  </div>
                )}

                {/* STUDENT DETAIL OVERLAY */}
                {student && (
                  <div style={{ position: "absolute", inset: 0, background: "#FBFAF6", animation: "lumiRise .35s cubic-bezier(.16,.84,.44,1) both", zIndex: 2 }}>
                    <div onClick={() => setStudent(null)} style={{ display: "inline-flex", alignItems: "center", gap: 5, padding: "6px 4px 10px", cursor: "pointer" }}>
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                        <path d="M15 6l-6 6 6 6" stroke="#1989CA" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
                      </svg>
                      <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 12, color: "#1989CA" }}>Back</span>
                    </div>
                    <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 22, padding: "18px 16px", textAlign: "center", marginBottom: 10, boxShadow: "0 1px 2px rgba(26,26,26,0.04)" }}>
                      <span style={{ display: "inline-block" }}>
                        <StudentAvatar bg={student.bg} avatar={student.avatar} size={58} imgSize={44} />
                      </span>
                      <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 16, color: "#1A1A1A", marginTop: 8 }}>{student.name}</div>
                      <div style={{ fontWeight: 400, fontSize: 11, color: student.subCol, marginTop: 2 }}>{student.sub}</div>
                      <div style={{ display: "flex", justifyContent: "center", gap: 18, marginTop: 12 }}>
                        <span style={{ textAlign: "center" }}>
                          <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 16, color: "#1A1A1A" }}>{student.streak}</span>
                          <span style={{ display: "block", fontWeight: 400, fontSize: 9.5, color: "#6B6B6B" }}>day streak</span>
                        </span>
                        <span style={{ textAlign: "center" }}>
                          <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 16, color: "#1A1A1A" }}>{student.books}</span>
                          <span style={{ display: "block", fontWeight: 400, fontSize: 9.5, color: "#6B6B6B" }}>books read</span>
                        </span>
                        <span style={{ textAlign: "center" }}>
                          <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 16, color: "#1A1A1A" }}>{student.badges}</span>
                          <span style={{ display: "block", fontWeight: 400, fontSize: 9.5, color: "#6B6B6B" }}>badges</span>
                        </span>
                      </div>
                    </div>
                    <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 22, padding: "12px 16px", boxShadow: "0 1px 2px rgba(26,26,26,0.04)" }}>
                      <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 12.5, color: "#1A1A1A", marginBottom: 6 }}>Recent reading</span>
                      {student.logs.map((l, i) => (
                        <div key={i} style={{ display: "flex", alignItems: "center", gap: 9, padding: "6px 0", borderBottom: "1px solid #F2EFE8" }}>
                          <span style={{ width: 20, height: 22, flexShrink: 0, backgroundImage: `url('${l.blob}')`, backgroundSize: "contain", backgroundRepeat: "no-repeat", backgroundPosition: "center" }} />
                          <span style={{ flex: 1, minWidth: 0, fontWeight: 400, fontSize: 11, color: "#1A1A1A", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                            {l.title}
                          </span>
                          <span style={{ fontWeight: 400, fontSize: 9.5, color: "#6B6B6B", whiteSpace: "nowrap" }}>{l.when}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>

              {/* floating pill bottom nav */}
              <div
                style={{
                  position: "absolute",
                  left: 14,
                  right: 14,
                  bottom: 14,
                  zIndex: 3,
                  background: "rgba(255,255,255,0.9)",
                  backdropFilter: "blur(12px)",
                  border: "1px solid rgba(255,255,255,0.55)",
                  borderRadius: 36,
                  padding: "8px 6px",
                  display: "flex",
                  boxShadow: "0 12px 28px -8px rgba(26,26,26,0.14)",
                }}
              >
                <span onClick={() => goTab("dash")} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 1, cursor: "pointer" }}>
                  <svg width="19" height="19" viewBox="0 0 24 24" fill="none">
                    <path d="M4 12l8-8 8 8M6 10v9h12v-9" stroke={tc("dash")} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                  <span style={{ fontWeight: 600, fontSize: 8.5, color: tc("dash") }}>Dashboard</span>
                </span>
                <span onClick={() => goTab("class")} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 1, cursor: "pointer" }}>
                  <svg width="19" height="19" viewBox="0 0 24 24" fill="none">
                    <circle cx="9" cy="8" r="3" stroke={tc("class")} strokeWidth="1.8" />
                    <circle cx="16.5" cy="9.5" r="2.3" stroke={tc("class")} strokeWidth="1.8" />
                    <path d="M3.5 18c1-3 3-4.5 5.5-4.5s4.5 1.5 5.5 4.5M15 14.5c2 0 3.8 1.2 4.8 3.5" stroke={tc("class")} strokeWidth="1.8" strokeLinecap="round" />
                  </svg>
                  <span style={{ fontWeight: 600, fontSize: 8.5, color: tc("class") }}>Class</span>
                </span>
                <span onClick={() => goTab("lib")} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 1, cursor: "pointer" }}>
                  <svg width="19" height="19" viewBox="0 0 24 24" fill="none">
                    <path d="M12 6c-1.8-1.6-4.2-2-7-2v14c2.8 0 5.2.4 7 2 1.8-1.6 4.2-2 7-2V4c-2.8 0-5.2.4-7 2Z" stroke={tc("lib")} strokeWidth="1.8" strokeLinejoin="round" />
                    <path d="M12 6v14" stroke={tc("lib")} strokeWidth="1.8" />
                  </svg>
                  <span style={{ fontWeight: 600, fontSize: 8.5, color: tc("lib") }}>Library</span>
                </span>
                <span onClick={() => goTab("set")} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 1, cursor: "pointer" }}>
                  <svg width="19" height="19" viewBox="0 0 24 24" fill="none">
                    <circle cx="12" cy="12" r="3" stroke={tc("set")} strokeWidth="1.8" />
                    <path
                      d="M12 4v2M12 18v2M4 12h2M18 12h2M6.3 6.3l1.4 1.4M16.3 16.3l1.4 1.4M6.3 17.7l1.4-1.4M16.3 7.7l1.4-1.4"
                      stroke={tc("set")}
                      strokeWidth="1.8"
                      strokeLinecap="round"
                    />
                  </svg>
                  <span style={{ fontWeight: 600, fontSize: 8.5, color: tc("set") }}>Settings</span>
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
