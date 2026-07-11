"use client";

import { useEffect } from "react";

type TrackedEl = HTMLElement & { __tilt?: string; __squash?: string; __blinking?: boolean };

/**
 * Port of the source's `_initCursorTracking` + `_initLumiIdle`: subtle
 * rotate/translate "look at the cursor" tilt on every `[data-lumi-track]`
 * mascot, composed with a periodic random squash-and-stretch "blink" on any
 * visible mascot/hover-pop image. Both write directly to `el.style.transform`
 * (matching the source's imperative DOM approach) rather than React state,
 * since neither is meant to trigger a re-render.
 */
export function useLumiTracking() {
  useEffect(() => {
    if (
      typeof window === "undefined" ||
      (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches)
    ) {
      return;
    }

    function setT(el: TrackedEl) {
      el.style.transform = `${el.__tilt || ""} ${el.__squash || ""}`.trim();
    }

    let mx = -1;
    let my = -1;
    let pending = false;
    function apply() {
      pending = false;
      const els = document.querySelectorAll<TrackedEl>("[data-lumi-track]");
      els.forEach((el) => {
        const r = el.getBoundingClientRect();
        if (!r.width) return;
        const cx = r.left + r.width / 2;
        const cy = r.top + r.height / 2;
        const dx = mx - cx;
        const dy = my - cy;
        const ang = Math.max(-8, Math.min(8, dx / 60));
        const tx = Math.max(-6, Math.min(6, dx / 120));
        const ty = Math.max(-5, Math.min(5, dy / 150));
        el.__tilt = `rotate(${ang.toFixed(2)}deg) translate(${tx.toFixed(1)}px,${ty.toFixed(1)}px)`;
        setT(el);
      });
    }
    function onMouseMove(e: MouseEvent) {
      mx = e.clientX;
      my = e.clientY;
      if (!pending) {
        pending = true;
        requestAnimationFrame(apply);
      }
    }
    document.addEventListener("mousemove", onMouseMove, { passive: true });

    function blink(el: TrackedEl) {
      if (el.__blinking) return;
      el.__blinking = true;
      el.__squash = "scale(1.07, 0.86)";
      setT(el);
      const t1 = setTimeout(() => {
        el.__squash = "scale(0.97, 1.05)";
        setT(el);
      }, 170);
      const t2 = setTimeout(() => {
        el.__squash = "";
        setT(el);
        el.__blinking = false;
      }, 340);
      return () => {
        clearTimeout(t1);
        clearTimeout(t2);
      };
    }

    const idleTimer = setInterval(() => {
      if (Math.random() < 0.4) return; // irregular rhythm
      const els = document.querySelectorAll<TrackedEl>(
        '[data-lumi-track], img[data-hover="peek-l"], img[data-hover="peek-r"], img[data-hover="pop"]'
      );
      if (!els.length) return;
      const el = els[Math.floor(Math.random() * els.length)];
      const r = el.getBoundingClientRect();
      const h = window.innerHeight || document.documentElement.clientHeight;
      if (!r.width || r.bottom < 0 || r.top > h) return; // only blink on-screen
      blink(el);
    }, 1600);

    return () => {
      document.removeEventListener("mousemove", onMouseMove);
      clearInterval(idleTimer);
    };
  }, []);
}
