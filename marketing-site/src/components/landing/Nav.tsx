"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

export function Nav() {
  const [condensed, setCondensed] = useState(false);

  useEffect(() => {
    function update() {
      const y = window.scrollY || document.documentElement.scrollTop || 0;
      setCondensed(y > 40);
    }
    window.addEventListener("scroll", update, { passive: true, capture: true });
    window.addEventListener("resize", update, { passive: true });
    update();
    return () => {
      window.removeEventListener("scroll", update, { capture: true } as EventListenerOptions);
      window.removeEventListener("resize", update);
    };
  }, []);

  return (
    <div
      data-nav
      data-condensed={condensed ? "" : undefined}
      style={{
        position: "sticky",
        top: 0,
        zIndex: 50,
        background: "rgba(247,245,240,0.88)",
        backdropFilter: "blur(10px)",
        borderBottom: "1px solid #ECE7DD",
      }}
    >
      <div
        style={{
          maxWidth: 1180,
          margin: "0 auto",
          padding: "16px 32px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 40 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span style={{ display: "block", width: 26, height: 34 }}>
              <img
                src="/assets/lumi-red.png"
                alt="Lumi"
                style={{ display: "block", width: "100%", height: "100%", objectFit: "contain" }}
              />
            </span>
            <span
              style={{
                fontFamily: "'Nunito',sans-serif",
                fontWeight: 900,
                fontSize: 27,
                color: "#211C16",
                letterSpacing: "-0.01em",
              }}
            >
              Lumi
            </span>
          </div>
          <div style={{ display: "flex", gap: 26, fontWeight: 400, fontSize: 15, color: "#4A453E" }}>
            <a href="#how" style={{ color: "#4A453E", textDecoration: "none" }}>
              How it works
            </a>
            <a href="#teachers" style={{ color: "#4A453E", textDecoration: "none" }}>
              For Teachers
            </a>
            <a href="#schools" style={{ color: "#4A453E", textDecoration: "none" }}>
              For Schools
            </a>
            <a href="#pricing" style={{ color: "#4A453E", textDecoration: "none" }}>
              Pricing
            </a>
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
          <a
            href="https://lumi-school-admin-au.web.app/login"
            style={{ fontWeight: 400, fontSize: 15, color: "#4A453E", textDecoration: "none" }}
          >
            Log in
          </a>
          <Link href="/contact-sales" style={{ fontWeight: 400, fontSize: 15, color: "#4A453E", textDecoration: "none" }}>
            Contact sales
          </Link>
          <Link
            href="/book-a-demo"
            style={{
              fontFamily: "'Nunito',sans-serif",
              fontWeight: 800,
              fontSize: 15,
              color: "#fff",
              background: "#EC4544",
              padding: "11px 22px",
              borderRadius: 999,
              textDecoration: "none",
            }}
          >
            Book a demo
          </Link>
        </div>
      </div>
    </div>
  );
}
