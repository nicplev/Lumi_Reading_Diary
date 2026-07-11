"use client";

import { useEffect } from "react";

/**
 * Faithful-but-simplified port of the source's `_initScrollReveals`.
 *
 * The source used an IntersectionObserver + a MutationObserver (the latter
 * only mattered for re-scanning after the interactive phone/portal mockups
 * swapped tabs, which don't add new [data-anim] nodes — they're all present
 * from first render here) plus a raw scroll/resize fallback scan. This port
 * keeps the IntersectionObserver + scroll/resize fallback and drops the
 * MutationObserver, per the task's stated simplification allowance.
 *
 * Elements get `data-shown` when they enter the viewport. Group containers
 * (`stagger`, `bento`, `pop`, `bars`) stagger their direct children instead
 * of showing the container itself, matching the source's `delays` map.
 */
export function useScrollReveal() {
  useEffect(() => {
    if (
      typeof window === "undefined" ||
      (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches)
    ) {
      return;
    }

    const doc = document.documentElement;
    const revealed = new WeakSet<Element>();

    function show(el: Element, delay: number) {
      if (!el || el.hasAttribute("data-shown")) return;
      if (delay) {
        setTimeout(() => el.setAttribute("data-shown", ""), delay);
      } else {
        el.setAttribute("data-shown", "");
      }
    }

    function revealGroup(el: Element) {
      const kind = el.getAttribute("data-anim");
      const delays: Record<string, number> = { stagger: 90, bento: 80, pop: 95, bars: 70 };
      if (kind && delays[kind]) {
        const base = kind === "bars" ? 140 : 0;
        Array.prototype.forEach.call(el.children, (child: Element, i: number) => {
          show(child, base + i * delays[kind]);
        });
      } else {
        show(el, 0);
      }
      revealed.add(el);
    }

    function inView(el: Element) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) return false;
      const h = window.innerHeight || doc.clientHeight;
      return r.top < h * 0.88 && r.bottom > 0;
    }

    function scan() {
      document.querySelectorAll("[data-anim]").forEach((el) => {
        if (!revealed.has(el) && inView(el)) revealGroup(el);
      });
    }

    doc.setAttribute("data-reveal-armed", "");
    let raf1 = 0;
    let raf2 = 0;
    raf1 = requestAnimationFrame(() => {
      raf2 = requestAnimationFrame(scan);
    });

    let ticking = false;
    function onScroll() {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(() => {
        scan();
        ticking = false;
      });
    }
    window.addEventListener("scroll", onScroll, { passive: true, capture: true });
    window.addEventListener("resize", onScroll, { passive: true });

    let io: IntersectionObserver | undefined;
    if ("IntersectionObserver" in window) {
      io = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (entry.isIntersecting && !revealed.has(entry.target)) {
              revealGroup(entry.target);
              io?.unobserve(entry.target);
            }
          });
        },
        { threshold: 0.12 }
      );
      document.querySelectorAll("[data-anim]").forEach((el) => io?.observe(el));
    }

    const deadMan = setTimeout(() => {
      if (!document.querySelector("[data-shown]")) doc.removeAttribute("data-reveal-armed");
    }, 3000);

    return () => {
      cancelAnimationFrame(raf1);
      cancelAnimationFrame(raf2);
      window.removeEventListener("scroll", onScroll, { capture: true } as EventListenerOptions);
      window.removeEventListener("resize", onScroll);
      io?.disconnect();
      clearTimeout(deadMan);
    };
  }, []);
}
