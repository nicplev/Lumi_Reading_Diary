# Penetration Test — Vendor Shortlist (Victoria / AU)

> Research 2026-07-20 to help Nic pick firms for the ST4S-evidence pen test.
> Companion to `PENETRATION_TEST_SCOPING_PACK.md` and
> `PENETRATION_TEST_RFQ_EMAIL.md`.
>
> **Important caveat:** the official CREST directories would not load during
> research, so almost every "CREST" label below is a vendor self-claim
> corroborated by secondary sources — **not** directory-verified. Before
> submitting any report to ST4S, ask each finalist for their **CREST
> membership number** (confirm on marketplace.crest.org) and the **named
> testers' certs** (OSCP / CREST CRT/CCT), since ST4S may verify individual
> tester credentials.

## Market price sanity-check (small web+cloud pentest, AU, 2025–26)

- Broad market ~$4k–$40k+; a single web-app test commonly $5k–$15k.
- Startup-stage anchors: seed/1-app ≈ $4k–$8k; Series-A SaaS + a cloud
  config review ≈ $8k–$15k.
- **Realistic for Lumi's full scope** (2 portals + ~60 Cloud Functions/API +
  Firestore/Storage rules review + Flutter mobile + the AI/LLM feature):
  **~$8k–$18k** as one combined engagement; a pared-back "one portal + API +
  rules review" first test could land **~$6k–$10k**.
- **Red flag:** anything materially below ~$5k for this surface is likely a
  shallow/automated scan — which ST4S T1/T2 explicitly does NOT accept in
  place of manual testing.

## Top 3

### 1. Project Black — best overall fit
- **Melbourne office** (727 Collins St, Docklands). Genuinely Victorian.
- CREST member (self-claimed); testers hold **CREST CRT, OSCP, OSCE**. Also
  an Australian **CVE Numbering Authority** publishing ~10 zero-days/yr — a
  strong independent credibility signal.
- Does web/API, network, **mobile**, cloud; has published research on AI in
  pentesting.
- **Pricing: SME-friendly** — small projects from ~$3,600; most tests
  $6k–$10k; 1–3 weeks.
- **The only shortlisted firm with a published ST4S guide AND stated edtech
  ST4S experience AND a Victorian office.** (projectblack.io/blog/st4s-assessment/)
- Ranked #1 because it hits every priority: local, CREST-claimed,
  strong testers, cheapest entry point, ST4S/edtech-specific, AI-aware.
- Verify: CREST membership number; that they'll cover Firestore/Storage
  rules review + the LLM prompt-injection testing.

### 2. Siege Cyber — best value / most transparent pricing
- Australian-owned, **HQ Newcastle NSW** (serves Melbourne remotely — not
  Victoria-based).
- Displays CREST; covers web, **API (REST/GraphQL/…)**, **GCP**, **mobile**.
- **Published fixed price bands** (most transparent found): Web App & API
  **$5,900–$16,500**; Basic Website $3,400–$6,500; Mobile App
  $5,900–$16,500; External Network $3,400–$9,500. Prefers fixed price.
- Whole brand aimed at **small/mid SaaS firms** (SOC2/ISO27001) — Lumi's
  profile. No ST4S/edtech track record; no Firebase-rules mention.
- Use their published bands as the number to sanity-check other quotes.

### 3. Cybra Security — best local Victorian boutique
- **Melbourne CBD HQ.** Truly Victorian.
- Testers stated **OSCP + CREST** (org-level CREST unconfirmed).
- Web, cloud, **mobile**, network, red team. No explicit GCP/Firebase or
  AI callout.
- **Pricing not published**; positions as cheaper than big firms; offers a
  subscription model that can bundle annual pentest + quarterly scans
  (matches the ST4S cadence). 5.0 Google rating shown (count unverified).
- Held at #3 only because pricing + CREST/review specifics are unverified.
  **Gridware (below) is a more-verified alternative for this slot.**

## Runners-up (worth a quote for comparison)

- **Gridware** — Sydney HQ + real **Melbourne office**; CREST-accredited;
  full suite incl. mobile/API/cloud. **Strongest verified reputation**
  (Google 5.0 from 39 reviews; Clutch: $5k+ min, $300+/hr). Leans slightly
  larger but takes small jobs. Best pick if you weight verified track record
  over boutique pricing.
- **Core Sentinel** — Sydney; senior-only; **explicit ST4S + edtech
  specialism** (claims helped numerous edtech firms pass ST4S). Pricing
  **$8k–$15k**. Not Victorian, but very ST4S-relevant — worth including for
  comparison.
- **Capture The Bug** — PTaaS built for ANZ (HQ Hamilton NZ). Uniquely
  matches Lumi: **dedicated EdTech page + dedicated AI/LLM pentest service +
  cloud**; flexible startup pricing (from ~$5k). Confirm named-tester certs
  and that its report format is ST4S-acceptable (community-tester model).
- **Cliffside** — Sydney, on-site Melbourne when needed; excellent testers
  (OSCP/OSWE/OSCE, CREST CPSA/CRT); no offshoring. Client base skews
  enterprise/regulated; pricing unpublished — likely pricier.

**Enterprise / likely-expensive (not recommended for a small ST4S test):**
CyberCX (Melbourne; Australia's largest; quote-only) and Tesserent/Thales
(Melbourne; enterprise-scale).

## ST4S-specific notes worth knowing
- ST4S control **6.2.7-T1**: annual pentest + testing after major changes,
  plus monthly automated scans (scans do **not** replace manual pentest);
  higher tiers favour **external, independent** testers.
- ST4S **v2024.1 added AI requirements** — testing for **prompt injection**
  and **PII leakage** through the model/logs/API — so make the AI feature an
  explicit RFQ line item (Lumi's scoping pack already does).
- Multi-tenant SaaS emphasis is **web-app + API** testing: broken access
  control, tenant isolation, auth/session, business logic — exactly Lumi's
  Firestore-rules boundary.

## Recommended action
Send the RFQ (`PENETRATION_TEST_RFQ_EMAIL.md`) to **Project Black, Siege
Cyber, and Cybra**, plus **Gridware** and **Core Sentinel** for comparison.
In each, explicitly ask for: CREST membership number; named testers' certs;
**Firebase/Firestore + GCP IAM rules-review capability** (no firm advertises
this by name — must be asked); **AI/LLM prompt-injection + PII-leakage
testing** per ST4S v2024.1; and a fixed price. Project Black is the natural
first call given the Victorian office + ST4S/edtech fit + SME pricing.

## Could-not-verify (do before relying on a vendor)
- Official CREST directory unreachable 2026-07-20 → confirm every CREST
  claim via membership number (only CyberCX was directory-confirmed, via the
  CREST ANZ council).
- No shortlisted firm advertises Firestore-rules review by name → ask.
- Review counts verified only for Gridware; Cybra's 5.0 count unconfirmed.
- Published pricing exists only for Siege Cyber (bands), Project Black
  (~$3.6k from / $6–10k), Core Sentinel ($8–15k); others are quote-only.
