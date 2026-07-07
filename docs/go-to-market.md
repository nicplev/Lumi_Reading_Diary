# Lumi — Go-to-Market: Landing Page, Pricing & Onboarding

> **Status:** Draft v0.1 · 2026-06-15 · Owner: Lumi (founder)
> **Purpose:** Make the retail (public, self-serve) and wholesale (KAKA-connected,
> sales-assisted) sides of Lumi easy to comprehend, and give a concrete foundation to
> build out the public landing page, pricing, and onboarding.
> **Scope of this doc:** strategy + content only. It is not code. Where it touches the
> app, it points at the real files so the work can be picked up later.
> **Caveats:** all dollar figures are **starting proposals to validate**, not final
> prices. Testimonials and the "hundreds of schools" claim are **placeholders** — replace
> with real, consented quotes/numbers before publishing.
> **⚠ Confidential — the KAKA connection is never public.** The public must not learn that
> KAKA Kids is connected to or runs Lumi. Keep KAKA off **all** public/retail surfaces —
> landing page, pricing, app stores, social, support. KAKA is named only **internally** and
> to **existing KAKA customers / qualified wholesale leads**, who alone receive the KAKA
> connection *and* the wholesale pricing. Publicly, Lumi is a standalone brand.

---

## 0. TL;DR (one screen)

- Lumi is the **digital replacement for the paper reading diary** (paper sells
  ~$7–15/student/year). **KAKA Kids School Supplies** commissioned it to replace its
  physical-diary sales; Lumi is a **separate, standalone brand** — and the KAKA connection
  is **kept confidential from the public** (disclosed only to existing KAKA customers; see caveat above).
- We sell through **two channels** to **two markets**:
  - **Retail (public, self-serve)** — shown on the landing page, transparent pricing.
    Buyers: **schools** *and* **individual parents**.
  - **Wholesale (private, sales-assisted, via KAKA / Lumi sales)** — better pricing,
    white-glove onboarding, POs/invoicing/contracts. **Pricing never shown publicly.**
- **Pricing model = per-student / year**, anchored to the paper diary so schools can
  compare directly to what they pay KAKA today:
  - Schools — **Retail**: ~**$15 → $11** per student/yr (cheaper as the school gets
    bigger), 30-day free trial, card checkout.
  - Schools — **Wholesale**: ~**$9 → $6** per student/yr, quote only, multi-year/PO.
  - Families — **Retail (B2C)**: **$4.99/mo or $39/yr** per child.
- The landing page **already exists** but is school-only and has **no pricing, no
  testimonials, no FAQ, and one undifferentiated CTA**. The biggest wins are: add a
  **pricing section**, add a **"For Families"** path, and **split the CTA** into
  "Start Free Trial" (retail) vs "Talk to Sales" (wholesale).
- Most of the **onboarding plumbing already exists** (demo form, school setup wizard,
  CSV import, parent link codes). The gaps are **billing/payment**, a **school-less
  "family" mode**, and **splitting the self-serve vs sales paths**.

---

## 1. Business model — two channels, two markets

Lumi replaces a consumable physical product (the paper diary, ~$7–15 each, one per
student per year) with a software subscription that does far more (tracking, analytics,
parent↔teacher comms, streaks/rewards, reminders, offline logging). Because there is no
per-unit printing cost, the same revenue per student is now **much higher margin** — and
we can offer it *at or below* the paper price while delivering 10× the value.

**Lumi vs KAKA.** KAKA commissioned Lumi and owns the wholesale relationships (it already
sells physical supplies into schools). Lumi is a separate entity with its own staff. In
practice:

- **KAKA = the wholesale channel + existing school relationships.** Wholesale deals can be
  co-sold with KAKA's physical supplies and ride KAKA's existing accounts.
- **Lumi = the product + the brand + the retail channel.** The public landing page is
  Lumi-branded and self-serve.

> **Confidentiality (decided — not an open question):** the Lumi–KAKA connection is
> **never** surfaced publicly. No "from the makers of KAKA diaries," no KAKA name or logo on
> the landing page, pricing, app stores, or social. KAKA is disclosed only to **existing KAKA
> customers / qualified wholesale leads**, who also receive the wholesale pricing. *(The
> Lumi↔KAKA commercial terms — rev share, who invoices — remain open; see §9.)*

```
                         ┌─────────────────────────────────────┐
                         │            LUMI (product)            │
                         └───────────────┬─────────────────────┘
              RETAIL (public, self-serve)│WHOLESALE (private, sales-assisted)
            ┌───────────────────────────┐│┌──────────────────────────────────┐
            │  Landing page · card pay   │││  KAKA reps / Lumi CS · quote/PO   │
            └─────────────┬──────────────┘│└──────────────────┬───────────────┘
        ┌─────────────────┴───────┐       │                   │
   Schools (B2B)          Families (B2C)   │            Schools (B2B)
   admin/principal        individual       │            districts / KAKA accounts
   /office staff          parents          │
```

---

## 2. Buyer segments

| Segment | Who they are | How they arrive | Who they deal with | Pricing |
|---|---|---|---|---|
| **School — Retail** | Admin / principal / office staff buying for the school | Landing page → "Start Free Trial" → self-serve | Nobody (optional support) | **Public** |
| **School — Wholesale** | Schools, multi-campus, districts — often existing KAKA customers | "Talk to Sales" / KAKA rep | Lumi CS / KAKA | **Private (quote)** |
| **Family — Retail (B2C)** | An individual parent buying for their own child | Landing page → "For Families" → self-serve | Nobody | **Public** |

**Why both retail and wholesale for schools?** Same product, different *motion*. A small
school that finds Lumi online wants to swipe a card and start today (retail). A 600-pupil
school or a district wants a quote, a PO, a contract, data import done for them, and staff
training (wholesale) — and is willing to commit to volume/multi-year for a better rate.
The retail "601+ → Talk to Sales" band is the natural hand-off point between the two.

**Why add Families (B2C)?** It opens a second revenue stream *and* a growth loop: a parent
who loves Lumi at home becomes a referral into their school ("invite your school"), which
feeds the school funnel. It also captures demand from families whose schools haven't (yet)
adopted Lumi.

---

## 3. Product packaging — "Lumi for Schools" vs "Lumi for Families"

Two clearly named offerings keep the page and the pricing legible.

### Lumi for Schools — *exists today*
The full product as built: teacher dashboard & class analytics, reading **allocations**
(by level / by title / free choice), **admin web portal** (user/roster/class management,
CSV bulk import, parent-link codes), parent app linked to the school, school-wide reports
(PDF/CSV), reading **groups** & **levels**, parent↔teacher **comments**, **achievements/
streaks/goals**, **book lookup** (ISBN), **comprehension audio**, **offline** logging,
**smart reminders**. Sold **per student / year** (retail or wholesale).

### Lumi for Families — *new product mode to build (B2C)*
A parent subscribes for their **own child**, even if the school hasn't adopted Lumi. Reuses
the home-facing parts of the app: reading log, streaks, goals, achievements, book lookup,
reminders — **without** teacher/allocations/class/school analytics. Sold **per child**.

> **Product gap to flag:** the app is currently school-centric — a student belongs to a
> `schoolId`/`classId`, and parents join only via a school-issued link code (see
> `lib/services/parent_linking_service.dart`, `StudentModel`). A school-less "family"
> account (a "household" tenant with a parent-owned child profile and home-only
> allocations/free-choice) is **net-new work**. Until it's built, Families is a roadmap
> item, not a live SKU. See §10.

---

## 4. Pricing

### 4.1 Principles
1. **Anchor to the paper diary.** Schools already budget ~$7–15/student/year for diaries
   from KAKA. Quote Lumi in the same unit (per student/year) so the swap is obvious.
2. **Retail is transparent; wholesale is a quote.** Public list prices build trust and
   enable self-serve. Wholesale stays private so we can flex on volume/term and protect
   the channel.
3. **Bigger schools pay less per seat.** Volume bands reward scale and steer large schools
   toward the sales-assisted motion.
4. **Annual by default.** Matches the school-year purchasing rhythm of the paper diary.

### 4.2 Lumi for Schools — Retail (public list price)
Per student / year, **billed annually**, **30-day free trial** (full features, no card —
this matches the existing "No credit card required" badge on the landing page), card
checkout.

| School size (students) | Price / student / year |
|---|---|
| 1 – 100 | **$15** |
| 101 – 300 | **$13** |
| 301 – 600 | **$11** |
| 601+ | **Talk to Sales** → wholesale |

### 4.3 Lumi for Schools — Wholesale (private — quote only)
Per student / year, **never shown publicly**. Hand this to the sales/CS team as an internal
price card.

| Commitment | Indicative price / student / year |
|---|---|
| 1-year | **~$9** |
| Multi-year and/or 600+ students | **~$7** |
| District / large multi-campus | **~$6** (negotiated) |

Wholesale **includes** (this is the "edge" vs retail):
- **White-glove onboarding** — dedicated CSM, roster import, reading-level setup, staff
  training, bulk parent-code generation, printable welcome packs.
- **POs, invoicing & contracts** — purchase orders, custom invoices, multi-year MSAs.
- **Optional KAKA bundle** — co-sold alongside KAKA physical supplies; ride existing KAKA
  accounts.

### 4.4 Lumi for Families — Retail (B2C)
Per child:

| Plan | Price |
|---|---|
| Monthly | **$4.99 / month** |
| Annual | **$39 / year** (≈ 35% cheaper than monthly) |
| Additional child | **~50% off** each extra child |
| Free tier (optional) | Basic logging + streaks; upsell to premium for goals/insights/multi-child |

> **Open decision (§11):** free tier vs time-limited trial for Families; exact monthly/
> annual split; whether Families is monthly-first (lower commitment, B2C-typical).

### 4.5 Retail vs Wholesale — at a glance

| | **Retail (public)** | **Wholesale (private)** |
|---|---|---|
| Who | Small/mid schools, individual parents | Larger schools, districts, KAKA accounts |
| Price/student/yr | $15 → $11 | $9 → $6 |
| Pricing shown | Yes, on the landing page | No — quote only |
| Buy how | Card, self-serve, today | Quote → PO/invoice → contract |
| Term | Annual | Annual or multi-year |
| Onboarding | Self-serve wizard (~10 min) | White-glove, done-for-you |
| Support | Standard / self-serve | Dedicated CSM |
| KAKA bundle | No | Optional |

### 4.6 What's free vs paid
- **Free:** 30-day school trial (full features, no card); optional Families free tier.
- **Paid:** everything after trial, priced per the tables above.
- **Always free to the end-user parent on a school plan:** when a *school* pays, parents
  use the app at no cost — the school covers their students (mirrors the paper diary,
  which the school buys for the child).

### 4.7 Discount ladder (stackable, within reason)
Annual prepay (already baseline) · multi-year (wholesale) · volume bands (built into the
table) · **KAKA existing-customer** discount · **early-adopter / founding-school** rate ·
**charter/low-ICSEA or non-profit** consideration (optional, brand-positive).

### 4.8 Worked examples
*(Paper-diary range shown at $7 low / $15 high; "mid" = $11.)*

| School | Paper diary / yr | Lumi **Retail** / yr | Lumi **Wholesale** / yr |
|---|---|---|---|
| 80 students | $560 – $1,200 (mid $880) | 80 × $15 = **$1,200** | 80 × $9 = **$720** |
| 250 students | $1,750 – $3,750 (mid $2,750) | 250 × $13 = **$3,250** | 250 × $9 = **$2,250** (or 250 × $7 = $1,750 multi-year) |
| 800 students | $5,600 – $12,000 (mid $8,800) | → Talk to Sales | 800 × $7 = **$5,600** (≈ paper *low* end, far more value) |

**The pitch this enables:** *"Replace your paper diary at a comparable price — and with
wholesale, often **less** than you pay now — while getting analytics, parent engagement,
and 80% less admin."*

**Family example:** one child = **$39/yr** (≈ $0.75/week); two children ≈ $39 + $19.50 =
**$58.50/yr**.

---

## 5. What to advertise publicly (and what to hide)

**Show on the landing page:**
- School **retail** bands (the §4.2 table) with "Start Free Trial."
- The **Families** plan (§4.4) with "Start Free Trial / Sign Up."
- A door to sales: **"Larger school, multi-campus or district? Get volume & district
  pricing →"** → lead form. (This is the wholesale entrance; **no prices shown**.)

**Never show publicly:**
- **The KAKA connection itself** — that KAKA Kids is connected to or runs Lumi (no name,
  logo, or "from the makers of…" anywhere public). Disclosed only to existing KAKA
  customers / qualified wholesale leads.
- Wholesale per-student rates, KAKA bundle terms, contract/PO terms, internal discounts.
  These live in the sales/CS price card and in quotes.

---

## 6. Landing page content spec

The page already exists: `lib/screens/marketing/landing_screen.dart` (SEO meta in
`web/index.html`). Brand voice is warm/playful — *"Making reading magical for every
child,"* the **Lumi Flame** mascot, Nunito type, palette of Sky Blue / Rose Pink / Warm
Orange / Mint Green / Soft Yellow. **Keep all of that.** Below, ✅ = exists today, 🆕 = add.

### 6.1 Section-by-section

1. ✅ **Header** — logo + nav. 🆕 Change nav to two CTAs: **Start Free Trial** (primary) and
   **Talk to Sales** (text). Add a **For Schools / For Families** switch.
2. ✅ **Hero** — keep *"Transform Reading into Magical Adventures."* 🆕 Make it
   audience-aware (Schools vs Families variants — see §6.3). 🆕 Replace the
   "📚 Dashboard Preview" placeholder with a real screenshot/short loop.
3. ✅ **Features** (6 cards) — keep.
4. ✅ **How Lumi Works** (Schools Set Up → Teachers Assign → Parents Track) — keep for
   Schools. 🆕 Add a Families variant (Sign up → Add your child → Log & celebrate).
5. 🆕 **"Replace your paper reading diary"** — side-by-side comparison (see §6.2). High
   impact for the principal/admin/office-staff buyer.
6. ✅ **Benefits** (Save Time / Boost Engagement / Data-Driven / Secure & Private / Easy
   Setup / Family Friendly) — keep. Soften unverified stats ("80%", "3×") to "up to" or
   substantiate.
7. 🆕 **Pricing** — the centrepiece that's missing today (see §6.4).
8. 🆕 **Social proof / testimonials** — replace the bare "hundreds of schools" claim with
   real, consented quotes + logos (see §6.5; copy is placeholder).
9. 🆕 **FAQ** — see §6.6.
10. ✅ **Final CTA** — keep *"Ready to Transform Reading at Your School?"* 🆕 add the dual
    CTA + a Families line. Keep the trust badges (no card / 10-min setup / free onboarding).
11. ✅ **Footer** — keep tagline; 🆕 add Pricing, For Families, FAQ, Contact Sales links;
    update "© 2025" → current year; add Privacy/Terms links.

### 6.2 "Replace your paper reading diary" block (draft copy)

> **From paper to magical.** *Heading*

| | 📓 Paper diary | ✨ Lumi |
|---|---|---|
| Cost | ~$7–15 per child, every year | Comparable — or less on wholesale |
| Lost / damaged | Re-buy & re-print | Always in the app |
| Legibility | "What does this say?" | Clear, timestamped logs |
| Visibility | Teacher sees it once a week | Real-time for teacher *and* parent |
| Motivation | A signature | Streaks, badges, goals |
| Reminders | Hope for the best | Gentle nudges home |
| Insights | None | School- & class-level analytics |

### 6.3 Hero variants (draft copy)
- **Schools:** *"Transform Reading into Magical Adventures"* / "The digital reading diary
  that replaces paper — simple for teachers, parents, and students. Set up in 10 minutes."
  CTAs: **Start Free Trial** · **Talk to Sales**.
- **Families:** *"Make reading magical at home"* / "Track your child's reading, keep the
  streak alive, and celebrate every milestone — from $39/year." CTA: **Start Free Trial**.

### 6.4 Pricing section (draft layout)
Three cards under the **For Schools / For Families** switch:
- **Schools — Retail:** show the §4.2 bands, "30-day free trial · no credit card," primary
  CTA **Start Free Trial**, and a quiet line *"600+ students? Get volume pricing →"*.
- **Families:** $4.99/mo or $39/yr, CTA **Start Free Trial**.
- **Districts / large schools:** "Custom pricing, white-glove setup, POs & invoicing" →
  CTA **Talk to Sales** (no numbers).
Add the **"compare to your paper diary"** one-liner and link to the §6.2 block.

### 6.5 Testimonials (PLACEHOLDER — replace with real, consented quotes)
Anchor to the existing personas. **Do not publish until real:**
- *Principal (cf. "Dr. Patel"):* "We swapped our paper diaries for Lumi and finally have
  school-wide reading data — at a similar cost." — *Name, School*
- *Teacher (cf. "Sarah"):* "Allocations and logging that used to eat my Friday afternoons
  now take minutes." — *Name, School*
- *Parent (cf. "Marcus"):* "One tap at bedtime and we can see the streak grow." — *Name*

### 6.6 FAQ (draft copy)
- **How is this different from a paper diary?** → point to §6.2.
- **What does it cost?** → schools from $11–15/student/yr (free trial); families from
  $39/yr; volume/district pricing on request.
- **Is my child's data safe?** → encryption + privacy posture (the page claims GDPR/COPPA —
  **verify with legal before repeating**; see §11).
- **What if a family doesn't have a smartphone?** → web access; teacher/paper fallback;
  school can still log.
- **Can I try before paying?** → 30-day full-feature trial, no card.
- **Can I cancel?** → yes; annual terms, no auto-price-hikes mid-term.
- **My school doesn't use Lumi — can I still use it?** → yes, **Lumi for Families**; and you
  can **invite your school**.

### 6.7 Persona messaging matrix
| Persona | Cares about | Lead message |
|---|---|---|
| Principal / decision-maker | Outcomes, budget, reporting, easy rollout | "School-wide reading data, at paper-diary cost." |
| Office staff / admin | Less paperwork, easy setup, roster import | "Bulk-import your roster, auto-generate parent codes, done in an afternoon." |
| Teacher | Time saved, class insight | "Allocations and logging in minutes, not Friday afternoons." |
| Parent | Simplicity, their child's progress | "One tap a night; watch the streak grow." |

---

## 7. Onboarding flows

Goal: **super easy and convenient.** Three paths. Most plumbing exists — gaps are flagged.

### 7.1 School — self-serve (Retail)
*Extends today's flow.* Today, **both** "Start Free Trial" and "Request Demo" route into
`DemoRequestScreen` → `SchoolRegistrationWizard`. Recommendation: make this the **retail**
path and keep it fast.

1. Landing → **Start Free Trial**.
2. Create admin account (email/password; 🆕 add **Google sign-up** for speed).
3. **School setup wizard** — `lib/screens/onboarding/school_registration_wizard.dart`
   (School Info → Admin Account → Reading Levels → Complete).
4. **Add roster** — CSV bulk import (exists in `school-admin-web/`); 🆕 one-click
   **"generate all parent link codes"** + **printable welcome letters / QR**.
5. **30-day trial active** (full features). 🆕 needs trial start/end on the school record.
6. **Choose plan & pay** in-app before trial end (per-student card checkout) → **active**.
   🆕 needs billing (see §10).

*Reuses:* `onboarding_service.dart` status machine (`demo → interested → registered →
setupInProgress → active`).

### 7.2 School — sales-assisted (Wholesale)
*Reuse the existing demo form as the lead capture* — `DemoRequestScreen` already collects
school name, contact person/email/phone, **estimated student & teacher counts**, and
**referral source**: exactly what sales needs to qualify.

1. Landing → **Talk to Sales** (or "Get volume/district pricing").
2. Lead form (`DemoRequestScreen`) → onboarding record (`demo`/`interested`).
3. Lumi CS / KAKA rep follows up → demo (run it per **[demo-playbook.md](demo-playbook.md)**)
   → **quote** (wholesale per-student) → **contract / PO / invoice**.
4. **White-glove setup** by CS via `school-admin-web/`: create school, import roster (CSV),
   configure reading levels, train staff, bulk-issue parent codes → `setupInProgress` →
   `active`.
5. Optional **KAKA physical-supply bundle**.

> Note: currently the demo form auto-advances into the *self-serve wizard*. For wholesale,
> it should instead **stop at "thanks, we'll be in touch"** and notify sales. That CTA
> split is the main change. (Code change — roadmap §10, not this doc.)

### 7.3 Parent — direct (B2C)
Two sub-cases:
- **(a) School uses Lumi** — parent gets an **8-char link code** → registers → links to
  child. *Exists:* `parent_linking_service.dart`, `parent_registration_modal.dart`. Free to
  the parent (school pays).
- **(b) School doesn't use Lumi** — **Lumi for Families**: parent signs up → creates a child
  profile (no school) → home reading mode → pays per child. 🆕 net-new (school-less mode,
  §3/§10). Include an **"invite your school"** referral that drops the school into the §7.1
  or §7.2 funnel.

### 7.4 Convenience checklist (applies across paths)
Google/Apple sign-up · CSV roster import · one-click parent-code generation · printable/QR
welcome packs · "setup in ~10 minutes" promise for retail · done-for-you for wholesale ·
sensible defaults (reading-level schema, minute targets) so a school can start same-day.

---

## 8. Implementation roadmap (future — not this task)

Phased, with the code each phase touches, so this can be picked up directly.

1. **Landing page content** (no backend): add **Pricing**, **For Families** path,
   **paper-vs-Lumi** block, **testimonials**, **FAQ**; **split CTAs** (Start Free Trial vs
   Talk to Sales). Files: `lib/screens/marketing/landing_screen.dart`, `web/index.html`,
   footer year/links. *Lowest effort, highest immediate value.*
2. **Lead routing**: make `DemoRequestScreen` serve the wholesale path (stop at confirmation
   + notify sales) and add a separate streamlined retail "create account" entry.
3. **Billing**: plan tiers + trial + checkout (e.g. Stripe). Extend the currently-unused
   `SchoolModel.subscriptionPlan` / `subscriptionExpiry` (+ trial start/end), enforce
   status in `firestore.rules` / Cloud Functions. Add a billing screen to
   `school-admin-web/`.
4. **Lumi for Families** (B2C): school-less "household" tenant + parent-owned child profile
   + home-only allocations; per-child subscription; "invite your school" loop. Largest
   product effort.
5. **Wholesale tooling**: quote/lead pipeline + internal price card in the admin portal.

Suggested order: **1 → 2 → 3 → 4/5**. Item 1 alone makes the page sell.

---

## 9. Open decisions

None block writing/using this doc; each needs a founder/team call before **publishing**:

1. **Exact price points** — validate the §4 numbers against willingness-to-pay and KAKA's
   current diary prices.
2. **Currency & region** — is "$" AUD? (KAKA = "School Supplies"; likely AU/NZ.) Affects
   GST/tax handling and copy.
3. **Lumi ↔ KAKA commercial terms** — revenue share, who invoices the school on wholesale,
   how the bundle is priced.
4. **Trial length** (30 days proposed) and **Families: free tier vs trial**, monthly-first
   vs annual-first.
5. **Tax/GST** display (inc/ex), invoicing entity, payment provider.
6. **Compliance claims** — confirm GDPR/COPPA (and AU Privacy Act / state education
   data rules) with legal before repeating on the page.
7. **Substantiate stats** — "80% less admin," "3× more reading," "hundreds of schools":
   back with data or soften.

---

## 10. Appendix — existing assets & code references

| Concern | Where |
|---|---|
| Landing page | `lib/screens/marketing/landing_screen.dart` |
| SEO / social meta | `web/index.html` |
| Demo / lead capture | `lib/screens/onboarding/demo_request_screen.dart` |
| School setup wizard | `lib/screens/onboarding/school_registration_wizard.dart` |
| Onboarding status machine | `lib/services/onboarding_service.dart` |
| Parent↔school linking | `lib/services/parent_linking_service.dart`, `..._registration_modal.dart` |
| Billing fields (unused) | `SchoolModel.subscriptionPlan` / `subscriptionExpiry`; `packages/types/src/school.ts` |
| Admin portal (white-glove tooling) | `school-admin-web/` (CSV import, parent-link mgmt) |
| Brand / personas | `lumi_flame_concept.html`, `docs/parent-ux-research.md` |

**Glossary:** *Retail* = public, self-serve, transparent pricing. *Wholesale* = private,
sales-assisted, quoted (KAKA channel). *B2B* = selling to schools. *B2C* = selling to
individual parents (Lumi for Families). *Per-student/year* = the pricing unit, mirroring
the one-diary-per-child-per-year paper model.
