"use client";

import { useState } from "react";

type ATab = "dash" | "classes" | "students" | "lib" | "comms" | "staff" | "parents" | "analytics" | "set";

const SECTIONS: Record<ATab, string> = {
  dash: "#2A9FC4",
  classes: "#D63A39",
  students: "#D63A39",
  lib: "#E6B600",
  comms: "#2A9FC4",
  staff: "#429654",
  parents: "#429654",
  analytics: "#2A9FC4",
  set: "#429654",
};
const BARS: Record<ATab, string> = {
  dash: "#56C8E6",
  classes: "#EC4544",
  students: "#EC4544",
  lib: "#FFCB05",
  comms: "#56C8E6",
  staff: "#51BA65",
  parents: "#51BA65",
  analytics: "#56C8E6",
  set: "#51BA65",
};
const TINTS: Record<ATab, string> = {
  dash: "rgba(86,200,230,0.14)",
  classes: "rgba(236,69,68,0.09)",
  students: "rgba(236,69,68,0.09)",
  lib: "rgba(255,203,5,0.16)",
  comms: "rgba(86,200,230,0.14)",
  staff: "rgba(81,186,101,0.12)",
  parents: "rgba(81,186,101,0.12)",
  analytics: "rgba(86,200,230,0.14)",
  set: "rgba(81,186,101,0.12)",
};

const NAV: { key: ATab; label: string }[] = [
  { key: "dash", label: "Dashboard" },
  { key: "classes", label: "Classes" },
  { key: "students", label: "Students" },
  { key: "lib", label: "Library" },
  { key: "comms", label: "Communication" },
  { key: "staff", label: "Staff" },
  { key: "parents", label: "Parents/Guardians" },
  { key: "analytics", label: "Analytics" },
  { key: "set", label: "Settings" },
];

const CLASS_ROWS = [
  { tag: "3B", name: "Class 3B", teacher: "Sarah Wilson", count: "26 students" },
  { tag: "4A", name: "Class 4A", teacher: "Tom Rivera", count: "25 students" },
  { tag: "1C", name: "Class 1C", teacher: "Grace Lee", count: "24 students" },
  { tag: "5M", name: "Class 5M", teacher: "Priya Nair", count: "27 students" },
];

const STUDENT_ROWS = [
  { name: "Ava Thompson", cls: "3B", streak: "🔥 8", bg: "#FFEDBB", avatar: "/assets/lumi-pink.png" },
  { name: "Jye Martin", cls: "3B", streak: "—", bg: "#C8E8F1", avatar: "/assets/lumi-frog.png" },
  { name: "Mia Chen", cls: "4A", streak: "🔥 14", bg: "#FBE89F", avatar: "/assets/lumi-tiger.png" },
  { name: "Noah Patel", cls: "1C", streak: "🔥 5", bg: "#C5E4CC", avatar: "/assets/lumi-green.png" },
  { name: "Isla Brown", cls: "5M", streak: "🔥 2", bg: "#FFD9D9", avatar: "/assets/lumi-red.png" },
];

const BOOK_ROWS = [
  { title: "Bear at the Beach", meta: "Decodable set · 6 copies", col: "#8FD8EE", tag: "Set A", tagCol: "#2A9FC4", tagBg: "rgba(86,200,230,0.15)" },
  { title: "The Red Hen", meta: "Decodable set · 8 copies", col: "#9FD8AC", tag: "Set A", tagCol: "#2A9FC4", tagBg: "rgba(86,200,230,0.15)" },
  { title: "Mia's Moon Trip", meta: "Picture book · 4 copies", col: "#F5B9CF", tag: "Theme", tagCol: "#429654", tagBg: "rgba(81,186,101,0.12)" },
  { title: "ISBN 9780 1434 0398 1", meta: "Scanned · awaiting details", col: "#E5E2DC", tag: "Needs details", tagCol: "#C79400", tagBg: "#FBE89F" },
];

const STAFF_ROWS = [
  { initials: "PN", name: "Priya Nguyen", sub: "School admin", tag: "Admin", bg: "rgba(81,186,101,0.15)", fg: "#429654", tagCol: "#429654", tagBg: "rgba(81,186,101,0.12)" },
  { initials: "SW", name: "Sarah Wilson", sub: "Class 3B", tag: "Teacher", bg: "#DCF0F8", fg: "#1989CA", tagCol: "#2A9FC4", tagBg: "rgba(86,200,230,0.15)" },
  { initials: "TR", name: "Tom Rivera", sub: "Class 4A", tag: "Teacher", bg: "#FFE0DF", fg: "#EC4544", tagCol: "#2A9FC4", tagBg: "rgba(86,200,230,0.15)" },
  { initials: "GL", name: "Grace Lee", sub: "Hasn't signed in yet", tag: "Invite pending", bg: "#FBE89F", fg: "#C79400", tagCol: "#C79400", tagBg: "#FBE89F" },
];

const LEVEL_OPTIONS = ["PM Benchmark", "A–Z", "Lexile", "Custom"];

export function ForSchoolLeaders() {
  const [tab, setTab] = useState<ATab>("parents");
  const [copied, setCopied] = useState(false);
  const [level, setLevel] = useState("PM Benchmark");

  const openTab = (key: ATab) => {
    setTab(key);
    setCopied(false);
  };

  // Dashboard quick-links ("Assign →" / "View →") switch tabs without
  // resetting the copy-code state, matching the source's aGoStudents/aGoParents
  // (only the sidebar nav's `open` handler clears aCopied).
  const goToTab = (key: ATab) => setTab(key);

  const doCopy = () => {
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  };

  return (
    <section id="schools" style={{ padding: "78px 32px" }}>
      <div style={{ maxWidth: 1180, margin: "0 auto", display: "grid", gridTemplateColumns: "1.05fr 1fr", gap: 56, alignItems: "center" }}>
        {/* admin illustration (left) */}
        <div data-anim="reveal-left" style={{ order: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 16 }}>
          <span
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 7,
              fontFamily: "'Nunito',sans-serif",
              fontWeight: 800,
              fontSize: 12.5,
              color: "#3C9B53",
              background: "#DFF0E3",
              padding: "8px 14px",
              borderRadius: 999,
            }}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
              <path
                d="M9 11.5V5.5a1.8 1.8 0 0 1 3.6 0v5M12.6 10.5V4.6a1.8 1.8 0 0 1 3.6 0v6M16.2 11V6.6a1.8 1.8 0 0 1 3.6 0V14c0 3.9-2.6 6.5-6.5 6.5-2.2 0-3.7-.8-5-2.4l-2.6-3.3a1.8 1.8 0 0 1 2.7-2.3l1.4 1.4V8.4a1.8 1.8 0 0 1 3.6 0v3.1"
                stroke="#3C9B53"
                strokeWidth="1.8"
                strokeLinejoin="round"
              />
            </svg>
            Try it, tap through the portal
          </span>
          <div
            style={{
              width: "100%",
              background: "#fff",
              border: "1px solid #E5E2DC",
              borderRadius: 18,
              overflow: "hidden",
              display: "flex",
              boxShadow: "0 2px 4px rgba(26,26,26,0.06), 0 24px 48px -20px rgba(26,26,26,0.22)",
            }}
          >
            {/* sidebar */}
            <div style={{ width: 138, flexShrink: 0, borderRight: "1px solid #E5E2DC", padding: "14px 8px", display: "flex", flexDirection: "column", gap: 2 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 7, padding: "0 6px 12px" }}>
                <span style={{ width: 26, height: 26, borderRadius: 8, background: "rgba(236,69,68,0.1)", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                  <img src="/assets/lumi-red.png" alt="" style={{ width: 15, height: "auto" }} />
                </span>
                <span style={{ minWidth: 0 }}>
                  <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 11, color: "#1A1A1A", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                    Sunnybank PS
                  </span>
                  <span style={{ display: "block", fontWeight: 600, fontSize: 8, color: "#6B6B6B" }}>School Portal</span>
                </span>
              </div>
              {NAV.map((n) => {
                const active = tab === n.key;
                return (
                  <span
                    key={n.key}
                    onClick={() => openTab(n.key)}
                    style={{
                      position: "relative",
                      fontWeight: active ? 700 : 600,
                      fontSize: 11,
                      color: active ? SECTIONS[n.key] : "#6B6B6B",
                      background: active ? TINTS[n.key] : "transparent",
                      padding: "6px 8px",
                      borderRadius: 8,
                      cursor: "pointer",
                      whiteSpace: "nowrap",
                    }}
                  >
                    <span
                      style={{
                        position: "absolute",
                        left: 0,
                        top: "50%",
                        transform: "translateY(-50%)",
                        height: 14,
                        width: 3,
                        borderRadius: 999,
                        background: active ? BARS[n.key] : "transparent",
                      }}
                    />
                    {n.label}
                  </span>
                );
              })}
            </div>
            {/* content */}
            <div style={{ flex: 1, background: "#F7F5F0", padding: 16, minWidth: 0, height: 398, overflow: "hidden", position: "relative" }}>
              {/* DASHBOARD */}
              {tab === "dash" && (
                <div style={{ animation: "lumiRise .35s cubic-bezier(.16,.84,.44,1) both" }}>
                  <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 15, color: "#1A1A1A", marginBottom: 10 }}>Sunnybank PS</div>
                  <div style={{ display: "flex", gap: 8, marginBottom: 10 }}>
                    <div style={{ flex: 1, background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "10px 12px" }}>
                      <div style={{ fontWeight: 600, fontSize: 9.5, color: "#6B6B6B" }}>Students</div>
                      <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 17, color: "#1A1A1A" }}>312</div>
                    </div>
                    <div style={{ flex: 1, background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "10px 12px" }}>
                      <div style={{ fontWeight: 600, fontSize: 9.5, color: "#6B6B6B" }}>Staff</div>
                      <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 17, color: "#1A1A1A" }}>18</div>
                    </div>
                    <div style={{ flex: 1, background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "10px 12px" }}>
                      <div style={{ fontWeight: 600, fontSize: 9.5, color: "#6B6B6B" }}>Classes</div>
                      <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 17, color: "#1A1A1A" }}>14</div>
                    </div>
                  </div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "12px 14px", marginBottom: 10 }}>
                    <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 12, color: "#1A1A1A", marginBottom: 8 }}>Attention required</div>
                    <div onClick={() => goToTab("students")} style={{ display: "flex", alignItems: "center", gap: 8, background: "#F7F5F0", borderRadius: 9, padding: "8px 10px", marginBottom: 6, cursor: "pointer" }}>
                      <span style={{ width: 24, height: 24, borderRadius: 7, background: "rgba(236,69,68,0.12)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11, color: "#EC4544", flexShrink: 0 }}>
                        !
                      </span>
                      <span style={{ flex: 1, fontWeight: 600, fontSize: 10.5, color: "#1A1A1A" }}>6 students not assigned to a class</span>
                      <span style={{ fontWeight: 700, fontSize: 9.5, color: "#D63A39", whiteSpace: "nowrap" }}>Assign →</span>
                    </div>
                    <div onClick={() => goToTab("parents")} style={{ display: "flex", alignItems: "center", gap: 8, background: "#F7F5F0", borderRadius: 9, padding: "8px 10px", cursor: "pointer" }}>
                      <span style={{ width: 24, height: 24, borderRadius: 7, background: "rgba(81,186,101,0.15)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11, color: "#429654", flexShrink: 0 }}>
                        ✉
                      </span>
                      <span style={{ flex: 1, fontWeight: 600, fontSize: 10.5, color: "#1A1A1A" }}>12 parent invitations awaiting acceptance</span>
                      <span style={{ fontWeight: 700, fontSize: 9.5, color: "#429654", whiteSpace: "nowrap" }}>View →</span>
                    </div>
                  </div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "12px 14px" }}>
                    <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 6 }}>
                      <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 12, color: "#1A1A1A" }}>Reading this week</span>
                      <span style={{ fontWeight: 600, fontSize: 10, color: "#6B6B6B" }}>262/312 students read</span>
                    </div>
                    <div style={{ height: 8, borderRadius: 999, background: "#F7F5F0", overflow: "hidden" }}>
                      <span style={{ display: "block", height: "100%", width: "84%", borderRadius: 999, background: "#56C8E6" }} />
                    </div>
                    <div style={{ fontWeight: 600, fontSize: 10, color: "#2A9FC4", marginTop: 5 }}>84% participation</div>
                  </div>
                </div>
              )}

              {/* CLASSES */}
              {tab === "classes" && (
                <div style={{ animation: "lumiRise .35s cubic-bezier(.16,.84,.44,1) both" }}>
                  <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 15, color: "#1A1A1A", marginBottom: 10 }}>Classes</div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "6px 14px" }}>
                    {CLASS_ROWS.map((c) => (
                      <div key={c.tag} style={{ display: "flex", alignItems: "center", gap: 9, padding: "9px 0", borderBottom: "1px solid #F2EFE8" }}>
                        <span
                          style={{
                            width: 28,
                            height: 28,
                            borderRadius: 9,
                            background: "rgba(236,69,68,0.1)",
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            fontFamily: "'Nunito',sans-serif",
                            fontWeight: 800,
                            fontSize: 10,
                            color: "#EC4544",
                            flexShrink: 0,
                          }}
                        >
                          {c.tag}
                        </span>
                        <span style={{ flex: 1, minWidth: 0 }}>
                          <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 700, fontSize: 11.5, color: "#1A1A1A" }}>{c.name}</span>
                          <span style={{ display: "block", fontWeight: 500, fontSize: 9.5, color: "#6B6B6B" }}>{c.teacher}</span>
                        </span>
                        <span style={{ fontWeight: 600, fontSize: 9.5, color: "#6B6B6B", whiteSpace: "nowrap" }}>{c.count}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* STUDENTS */}
              {tab === "students" && (
                <div style={{ animation: "lumiRise .35s cubic-bezier(.16,.84,.44,1) both" }}>
                  <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 15, color: "#1A1A1A", marginBottom: 10 }}>Students</div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "6px 14px", marginBottom: 8 }}>
                    {STUDENT_ROWS.map((s) => (
                      <div key={s.name} style={{ display: "flex", alignItems: "center", gap: 9, padding: "8px 0", borderBottom: "1px solid #F2EFE8" }}>
                        <span style={{ width: 28, height: 28, borderRadius: "50%", background: s.bg, overflow: "hidden", flexShrink: 0 }}>
                          <span
                            style={{
                              display: "block",
                              width: "100%",
                              height: "100%",
                              backgroundImage: `url('${s.avatar}')`,
                              backgroundSize: "21px auto",
                              backgroundRepeat: "no-repeat",
                              backgroundPosition: "center bottom",
                            }}
                          />
                        </span>
                        <span style={{ flex: 1, minWidth: 0, fontFamily: "'Nunito',sans-serif", fontWeight: 700, fontSize: 11.5, color: "#1A1A1A" }}>{s.name}</span>
                        <span style={{ fontWeight: 600, fontSize: 9, color: "#D63A39", background: "rgba(236,69,68,0.09)", padding: "3px 8px", borderRadius: 999 }}>{s.cls}</span>
                        <span style={{ fontWeight: 600, fontSize: 9.5, color: "#6B6B6B", whiteSpace: "nowrap" }}>{s.streak}</span>
                      </div>
                    ))}
                  </div>
                  <div style={{ fontWeight: 600, fontSize: 9.5, color: "#6B6B6B", textAlign: "center" }}>312 students · CSV import supported</div>
                </div>
              )}

              {/* LIBRARY */}
              {tab === "lib" && (
                <div style={{ animation: "lumiRise .35s cubic-bezier(.16,.84,.44,1) both" }}>
                  <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 15, color: "#1A1A1A", marginBottom: 10 }}>Library</div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "6px 14px", marginBottom: 8 }}>
                    {BOOK_ROWS.map((b) => (
                      <div key={b.title} style={{ display: "flex", alignItems: "center", gap: 9, padding: "8px 0", borderBottom: "1px solid #F2EFE8" }}>
                        <span style={{ width: 20, height: 27, borderRadius: 4, background: b.col, flexShrink: 0 }} />
                        <span style={{ flex: 1, minWidth: 0 }}>
                          <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 700, fontSize: 11, color: "#1A1A1A", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                            {b.title}
                          </span>
                          <span style={{ display: "block", fontWeight: 500, fontSize: 9, color: "#6B6B6B" }}>{b.meta}</span>
                        </span>
                        <span style={{ fontWeight: 600, fontSize: 9, color: b.tagCol, background: b.tagBg, padding: "3px 8px", borderRadius: 999, whiteSpace: "nowrap" }}>{b.tag}</span>
                      </div>
                    ))}
                  </div>
                  <div style={{ background: "#FFCB05", borderRadius: 10, padding: 9, display: "flex", alignItems: "center", justifyContent: "center", gap: 6 }}>
                    <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 10.5, color: "#3A2E00" }}>Scan ISBNs from the teacher app to add books</span>
                  </div>
                </div>
              )}

              {/* COMMUNICATION */}
              {tab === "comms" && (
                <div style={{ animation: "lumiRise .35s cubic-bezier(.16,.84,.44,1) both" }}>
                  <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 15, color: "#1A1A1A", marginBottom: 10 }}>Communication</div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "12px 14px", marginBottom: 8 }}>
                    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 4 }}>
                      <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 12, color: "#1A1A1A" }}>Book Week is coming! 📚</span>
                      <span style={{ fontWeight: 600, fontSize: 9, color: "#429654", background: "rgba(81,186,101,0.12)", padding: "3px 8px", borderRadius: 999 }}>Sent</span>
                    </div>
                    <div style={{ fontWeight: 500, fontSize: 10, color: "#6B6B6B" }}>Delivered to 312 families · Tuesday 9:00 am</div>
                  </div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "12px 14px", marginBottom: 8 }}>
                    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 4 }}>
                      <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 12, color: "#1A1A1A" }}>Term 3 reading challenge</span>
                      <span style={{ fontWeight: 600, fontSize: 9, color: "#C79400", background: "#FBE89F", padding: "3px 8px", borderRadius: 999 }}>Draft</span>
                    </div>
                    <div style={{ fontWeight: 500, fontSize: 10, color: "#6B6B6B" }}>Scheduled for Monday 8:00 am</div>
                  </div>
                  <div style={{ background: "#56C8E6", borderRadius: 10, padding: 9, textAlign: "center" }}>
                    <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 10.5, color: "#fff" }}>+ New announcement</span>
                  </div>
                </div>
              )}

              {/* STAFF */}
              {tab === "staff" && (
                <div style={{ animation: "lumiRise .35s cubic-bezier(.16,.84,.44,1) both" }}>
                  <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 15, color: "#1A1A1A", marginBottom: 10 }}>Staff</div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "6px 14px" }}>
                    {STAFF_ROWS.map((u) => (
                      <div key={u.initials} style={{ display: "flex", alignItems: "center", gap: 9, padding: "9px 0", borderBottom: "1px solid #F2EFE8" }}>
                        <span
                          style={{
                            width: 28,
                            height: 28,
                            borderRadius: "50%",
                            background: u.bg,
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            fontFamily: "'Nunito',sans-serif",
                            fontWeight: 800,
                            fontSize: 10,
                            color: u.fg,
                            flexShrink: 0,
                          }}
                        >
                          {u.initials}
                        </span>
                        <span style={{ flex: 1, minWidth: 0 }}>
                          <span style={{ display: "block", fontFamily: "'Nunito',sans-serif", fontWeight: 700, fontSize: 11.5, color: "#1A1A1A" }}>{u.name}</span>
                          <span style={{ display: "block", fontWeight: 500, fontSize: 9.5, color: "#6B6B6B" }}>{u.sub}</span>
                        </span>
                        <span style={{ fontWeight: 600, fontSize: 9, color: u.tagCol, background: u.tagBg, padding: "3px 8px", borderRadius: 999, whiteSpace: "nowrap" }}>{u.tag}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* PARENTS/GUARDIANS */}
              {tab === "parents" && (
                <div style={{ animation: "lumiRise .35s cubic-bezier(.16,.84,.44,1) both" }}>
                  <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 15, color: "#1A1A1A", marginBottom: 10 }}>Parents &amp; Guardians</div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: 14, marginBottom: 10 }}>
                    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
                      <span style={{ fontWeight: 600, fontSize: 11, color: "#6B6B6B" }}>Parent linking code</span>
                      <span style={{ fontWeight: 600, fontSize: 10, color: "#429654", background: "rgba(81,186,101,0.12)", padding: "3px 8px", borderRadius: 999 }}>Active · 312 linked</span>
                    </div>
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 19, letterSpacing: "0.1em", color: "#1A1A1A" }}>LUMI-7F3K</span>
                      <span
                        onClick={doCopy}
                        style={{
                          fontWeight: 700,
                          fontSize: 10.5,
                          color: copied ? "#fff" : "#429654",
                          border: "1px solid rgba(81,186,101,0.4)",
                          background: copied ? "#51BA65" : "transparent",
                          padding: "4px 11px",
                          borderRadius: 999,
                          cursor: "pointer",
                          transition: "all .2s ease",
                        }}
                      >
                        {copied ? "Copied!" : "Copy"}
                      </span>
                    </div>
                  </div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "12px 14px", marginBottom: 10 }}>
                    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 6 }}>
                      <span style={{ fontWeight: 600, fontSize: 11, color: "#6B6B6B" }}>Parent onboarding</span>
                      <span style={{ fontWeight: 600, fontSize: 10, color: "#C79400", background: "#FBE89F", padding: "3px 8px", borderRadius: 999 }}>12 pending</span>
                    </div>
                    <div style={{ height: 8, borderRadius: 999, background: "#F7F5F0", overflow: "hidden" }}>
                      <span style={{ display: "block", height: "100%", width: "92%", borderRadius: 999, background: "#51BA65" }} />
                    </div>
                    <div style={{ fontWeight: 600, fontSize: 10, color: "#429654", marginTop: 5 }}>300 of 312 families connected</div>
                  </div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "12px 14px" }}>
                    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                      <span style={{ fontWeight: 600, fontSize: 11, color: "#6B6B6B" }}>Send onboarding email</span>
                      <span style={{ fontWeight: 700, fontSize: 10, color: "#429654", border: "1px solid rgba(81,186,101,0.4)", padding: "4px 11px", borderRadius: 999 }}>Preview</span>
                    </div>
                  </div>
                </div>
              )}

              {/* ANALYTICS */}
              {tab === "analytics" && (
                <div style={{ animation: "lumiRise .35s cubic-bezier(.16,.84,.44,1) both" }}>
                  <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 15, color: "#1A1A1A", marginBottom: 10 }}>Analytics</div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "12px 14px", marginBottom: 8 }}>
                    <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 8 }}>
                      <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 12, color: "#1A1A1A" }}>Nightly reading · this term</span>
                      <span style={{ fontWeight: 600, fontSize: 9.5, color: "#2A9FC4" }}>▲ 12%</span>
                    </div>
                    <div data-anim="bars" style={{ display: "flex", alignItems: "flex-end", gap: 5, height: 64 }}>
                      {[
                        { h: 46, c: "#C8E8F1" },
                        { h: 58, c: "#C8E8F1" },
                        { h: 52, c: "#C8E8F1" },
                        { h: 68, c: "#56C8E6" },
                        { h: 76, c: "#56C8E6" },
                        { h: 84, c: "#2A9FC4" },
                      ].map((bar, i) => (
                        <span key={i} style={{ flex: 1, height: `${bar.h}%`, background: bar.c, borderRadius: "4px 4px 0 0" }} />
                      ))}
                    </div>
                  </div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "12px 14px" }}>
                    <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 12, color: "#1A1A1A", marginBottom: 8 }}>How reading felt this week</div>
                    <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between", gap: 4 }}>
                      {[
                        { file: "blob-great.png", pct: "46%" },
                        { file: "blob-good.png", pct: "31%" },
                        { file: "blob-okay.png", pct: "15%" },
                        { file: "blob-tricky.png", pct: "6%" },
                        { file: "blob-hard.png", pct: "2%" },
                      ].map((b) => (
                        <span key={b.file} style={{ flex: 1, textAlign: "center" }}>
                          <span
                            style={{
                              display: "block",
                              width: 22,
                              height: 24,
                              margin: "0 auto 3px",
                              backgroundImage: `url('/assets/blobs/${b.file}')`,
                              backgroundSize: "contain",
                              backgroundRepeat: "no-repeat",
                              backgroundPosition: "bottom",
                            }}
                          />
                          <span style={{ fontWeight: 700, fontSize: 9.5, color: "#1A1A1A" }}>{b.pct}</span>
                        </span>
                      ))}
                    </div>
                  </div>
                </div>
              )}

              {/* SETTINGS */}
              {tab === "set" && (
                <div style={{ animation: "lumiRise .35s cubic-bezier(.16,.84,.44,1) both" }}>
                  <div style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 15, color: "#1A1A1A", marginBottom: 10 }}>Settings</div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: 14, marginBottom: 10 }}>
                    <div style={{ fontWeight: 600, fontSize: 11, color: "#6B6B6B", marginBottom: 8 }}>Reading level system · tap to change</div>
                    <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                      {LEVEL_OPTIONS.map((label) => {
                        const active = level === label;
                        return (
                          <span
                            key={label}
                            onClick={() => setLevel(label)}
                            style={{
                              fontFamily: "'Nunito',sans-serif",
                              fontWeight: active ? 700 : 500,
                              fontSize: 11,
                              color: active ? "#fff" : "#6B6B6B",
                              background: active ? "#51BA65" : "transparent",
                              border: `1px solid ${active ? "#51BA65" : "#E5E2DC"}`,
                              padding: "5px 11px",
                              borderRadius: 999,
                              cursor: "pointer",
                              transition: "all .2s ease",
                            }}
                          >
                            {active ? `${label} ✓` : label}
                          </span>
                        );
                      })}
                    </div>
                  </div>
                  <div style={{ background: "#fff", border: "1px solid #E5E2DC", borderRadius: 12, padding: "12px 14px" }}>
                    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", paddingBottom: 8, borderBottom: "1px solid #F2EFE8" }}>
                      <span style={{ fontWeight: 600, fontSize: 11, color: "#1A1A1A" }}>School name</span>
                      <span style={{ fontWeight: 600, fontSize: 10.5, color: "#6B6B6B" }}>Sunnybank PS</span>
                    </div>
                    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", paddingTop: 8 }}>
                      <span style={{ fontWeight: 600, fontSize: 11, color: "#1A1A1A" }}>Timezone</span>
                      <span style={{ fontWeight: 600, fontSize: 10.5, color: "#6B6B6B" }}>Australia/Brisbane</span>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>

        <div data-anim="reveal-right" style={{ order: 2 }}>
          <span style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800, fontSize: 13, letterSpacing: "0.12em", textTransform: "uppercase", color: "#3C9B53" }}>
            For school leaders
          </span>
          <h2 style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 900, fontSize: 44, lineHeight: 1.07, letterSpacing: "-0.02em", margin: "14px 0 0", color: "#1C1812" }}>
            Run reading across the whole school from one web dashboard.
          </h2>
          <p style={{ fontWeight: 300, fontSize: 18, lineHeight: 1.6, color: "#4A453E", margin: "18px 0 0", maxWidth: "52ch" }}>
            Set the system up once, and give every teacher and family a consistent home-reading routine, with the
            school-wide picture always a click away.
          </p>
          <div style={{ display: "flex", flexDirection: "column", gap: 14, marginTop: 28 }}>
            {[
              { strong: "Manage users & roles", rest: "for staff, classes and families" },
              { strong: "Generate parent linking codes", rest: "for secure, simple sign-up" },
              { strong: "Configure level systems", rest: ": PM Benchmark, A–Z, Lexile or custom" },
              { strong: "View school-wide analytics", rest: "on engagement and progress" },
            ].map((item) => (
              <div key={item.strong} style={{ display: "flex", alignItems: "flex-start", gap: 13 }}>
                <span style={{ width: 26, height: 26, borderRadius: 8, background: "#DFF0E3", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, marginTop: 1 }}>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                    <path d="M5 12.5l4.5 4.5L19 7" stroke="#3C9B53" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </span>
                <span style={{ fontWeight: 300, fontSize: 16, lineHeight: 1.5, color: "#3A352E" }}>
                  <strong style={{ fontFamily: "'Nunito',sans-serif", fontWeight: 800 }}>{item.strong}</strong> {item.rest}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
