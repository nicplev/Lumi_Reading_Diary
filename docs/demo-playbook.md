# Lumi — Sales Demo Playbook

> **Status:** v1.1 · 2026-07-19 · Owner: Lumi (founder)
> **Purpose:** a repeatable script for demoing Lumi to school prospects — on video
> calls and in person — that any future sales/CS teammate can run.
> **Companion tooling:** [`scripts/seed_demo_school.js`](../scripts/seed_demo_school.js)
> creates and resets the demo school this playbook is written around.
> **Pricing & positioning:** see [go-to-market.md](go-to-market.md). Its rules apply
> here too — retail pricing is public, wholesale is quote-only, and the KAKA
> connection is **never** mentioned to retail prospects (§8 below).

---

## 1. The one-sentence demo

> *A child reads at home tonight; Mum logs it in one tap; the teacher sees it
> tomorrow morning and replies; the principal sees the whole school reading more —
> that loop, shown live in 18 minutes.*

Everything below exists to deliver that loop without friction. The demo is a
**story about one family**, not a feature tour.

---

## 2. Demo environment & cast

One command creates (or resets) a fictional, clearly-marked tenant —
**Lumi Demo Primary School** (`schools/lumi_demo_primary_school`, `isDemo: true`) —
inside the production LumiAU Firebase project. Multi-tenancy isolates it from real
schools; the reset guard refuses to touch any school not flagged `isDemo`.

```bash
# from the repo root (once: cd functions && npm install)
FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH=/path/to/lumiau-service-account.json \
  node scripts/seed_demo_school.js --reset
```

The script prints the resolved **project id** and asks for confirmation — check it
says your LumiAU project before typing `yes`. `--dry-run` prints the full plan
without connecting.

### Logins — rolling daily password

The three **shared** logins below are on a **rolling daily password**: the seed
sets an initial one, but in production a nightly cron (`scrambleDemoPasswords`,
just after Sydney midnight) scrambles every demo account, and the super-admin
portal issues that day's password on demand. So on a real demo day you don't use
Use the demo password from the team password manager — you **provision** the
day's password first (see below). No demo password is stored in Git.

| Role | Email | Where they log in | What they show |
|---|---|---|---|
| School admin (shared) | `support+demo@lumi-reading.com` | School-admin web portal | Analytics, roster, parent-link funnel |
| Teacher — *Priya Sharma* | `support+demo.teacher@lumi-reading.com` | Flutter web (or tablet app) | Class 3G dashboard, allocations, comments |
| Parent — *Sarah Nguyen ("Mum")* | `support+demo.parent@lumi-reading.com` | **iPhone app only** | Quick log, streaks, badges, two children |
| Parent 2 — *Marcus Webb ("Dad")* | `demo.parent2@lumidemo.school` | iPhone app | Spare parent account (scrambled nightly, not shared) |
| School admin — *Dana Whitfield* | `demo.admin@lumidemo.school` | School-admin web portal | Internal/backup admin — **never shared**, scrambled nightly |

> The three `support+demo…@lumi-reading.com` addresses plus-alias into a mailbox
> Nic controls, so their password-reset emails are actually receivable. The
> parent experience is **deliberately mobile-only** (enforced in
> `lib/core/routing/app_router.dart` — parents on web are redirected).

Demo accounts are created by the Admin SDK with `emailVerified: true` and **no
MFA**, so logins are instant mid-demo. (Real parent registration enrols SMS MFA —
worth *saying* when security comes up, since the demo accounts won't show it.)

### Provisioning demo access (super-admin portal)

Book-a-Demo requests from the marketing site land in the super-admin
**Onboarding** pipeline's *demo* column. On the request's detail page, the
**Demo access** panel drives the whole flow:

1. **Provision today's demo password** — issues one shared password (idempotent
   within the Sydney day; a second demo reuses the same one) and sets it on the
   three shared accounts. Read it out on the call, or:
2. **Email demo details** — SendGrids the requester the day's credentials, the
   portal + marketing links, app-store instructions, and the teacher/parent app
   logins (BCC'd to `support@lumi-reading.com` as a paper trail).

Access **self-expires at midnight (Sydney)** — the password scrambles and even
the school-portal session cookie is capped to end-of-day, so a prospect can log
in themselves during/after a Zoom demo without lingering access. The canonical
"who's been given demo access" history lives on the demo school's detail page
(**Demo access** tab). Config (emails, store URLs) is in
`platformConfig/demoAccess`; see `docs/DEMO_DAY_ACCESS_PLAN.md`.

### MFA exception for the shared demo administrator

The demo school-admin account also carries Admin-SDK-only
`demoAdminMfaExempt` + `demoReadOnly` claims. The portal verifies those claims
against the `isDemo: true` tenant before skipping mandatory authenticator MFA.
That admin session is read-only in portal API handlers and middleware, Firestore
Rules, and Cloud Functions. The demo parent and teacher remain able to perform
the scripted activity inside the fictional tenant; neither role is subject to
the admin-only TOTP policy.

### The students that matter

| Student | Class | Why they exist |
|---|---|---|
| **Ava Nguyen** | 3G | The hero: ~45-day streak, 9 badges, a fresh parent↔teacher comment thread on last night's log, and her **newest badge is un-seen** — the celebration popup fires the first time you open the parent app. One-shot per seed: reset restores it. |
| **Leo Nguyen** | 5B | Ava's brother — shows the multi-child switcher on Sarah's account. |
| **Riley Thompson** | 3G | Lapsed: read for weeks, silent for 14 days → lights up the **at-risk** analytics view. |
| **Billy Martin** | 3G | Subscribed but **no parent linked** — the live-linking target. His active link code is printed at the end of every seed run. |
| Ruby Jones / Harper Lee | 3G / 5B | `not_enrolled` — populate the parent-links onboarding funnel ("no subscription" state). |

Everyone else fills out the charts with believable variety (~460 reading logs over
60 days and allocations).

---

## 3. Rig checklists

Fill these in once and keep them with the playbook:

- School-admin portal URL: `___________________` *(your LumiAU hosting URL)*
- Flutter web app URL: `___________________`
- iPhone with the TestFlight build installed and signed in as **Sarah**

### Video call (Zoom/Meet/Teams)

- [ ] Today's password provisioned; the redacted live preflight says **READY** (§4)
- [ ] Browser window 1: school-admin portal, logged in as **Dana**, on Dashboard
- [ ] Browser window 2: Flutter web, logged in as **Priya**, on class 3G
- [ ] iPhone signed in as **Sarah**, app **closed** (preserves the badge popup),
      notifications allowed, Do Not Disturb **off**, media volume up
- [ ] iPhone mirrored to the laptop (macOS: QuickTime → File → New Movie Recording
      → camera dropdown → iPhone) so you can share it as a window
- [ ] Phone on 4G/5G, laptop on ethernet/wifi — different networks means one
      outage can't kill both halves of the live round-trip
- [ ] Plan B on the desktop: the 3 fallback clips + screenshot deck (§6)
- [ ] Notes/pricing one-pager on a second screen, out of the shared window

### In person (staff room / principal's office)

Everything above, plus:

- [ ] iPad or second iPhone signed in as **Priya** (teacher-in-hand beats a laptop
      in a staff room)
- [ ] A **physical paper reading diary** — the single best prop you own
- [ ] Printed link-code card for **Billy Martin** (code from the seed output) for
      the hands-on linking moment
- [ ] Printed pricing one-pager (retail bands only — per go-to-market.md)
- [ ] Phone hotspot ready — never depend on school guest wifi

---

## 4. The pre-demo ritual (10 minutes, every time)

1. **Provision today:** in the super-admin portal, open the prospect's demo
   request and select **Provision today's demo password**. The first provision
   of a new Sydney day performs the fenced demo reseed before issuing the
   password; do not separately run the legacy seed/reset command.
2. **Run the automated live preflight** from the repo root:

   ```bash
   pnpm demo:preflight -- --project=lumi-ninc-au --canary
   ```

   If ADC is not available on this computer, first run
   `gcloud auth application-default login`. The command prints no password,
   token, UID, child identity or document ID. It verifies today's unscrambled
   credential, all three fresh password sign-ins, exact role claims, membership
   indexes, populated demo content, production Rules reads, the read-only admin
   portal session, and reversible parent/teacher login + Terms writes. The
   canary restores every profile field it touches. **Do not begin the call
   unless the final line says `READY`.**
3. **Thirty-second surface smoke:** admin portal dashboard loads and remains
   read-only; teacher account reaches Teacher Home; parent account reaches the
   current Terms screen or Parent Home. If Terms appear, accept them before the
   call. This is the only part the automated gate cannot visually prove.
4. **Parent popup trap:** opening the app can consume Ava's one-shot badge
   celebration. If that moment matters for the call, use the explicit demo
   reseed control after the smoke check, confirm it succeeds, and leave the app
   closed. Same-day password provisioning alone intentionally reuses the
   credential and does not reset activity.
5. **Fallbacks ready:** confirm the three short fallback clips/screenshots are
   on the laptop, then silence everything except Lumi notifications.

The code-level regression suite is `pnpm test:demo-readiness`. It runs in the
`demo-readiness` GitHub workflow whenever demo auth, routing, Rules, portals,
Functions or seed logic changes. It is a release gate, not a substitute for the
daily live preflight above.

---

## 5. The golden path (18 minutes)

Times are cumulative. Each beat: **surface → what you do → the line you say.**

### Beat 1 — Cold open: the paper problem (0:00–2:00) · *no screen*

Hold up the paper diary (or describe it on a call).

> "Your families use one of these. It costs the school **$7–15 per child, every
> year**. It gets lost, it comes back soaked, half the entries say '10 mins ✓' in
> handwriting nobody can read — and it tells you nothing about reading across the
> school. Lumi replaces it for a comparable price. Let me show you one family's
> evening."

### Beat 2 — The parent moment (2:00–6:00) · *iPhone, as Sarah*

1. Open the app → **Ava's new badge celebration pops** — let it land, tap through.
2. Today tab: the ~45-day streak, tonight's book from the teacher's allocation.
3. **One-tap quick log**: 20 minutes, feeling "great", one line — "loved the
   ending". Save. Streak ticks up on screen.
4. Flick to Leo — same account, second child, ten seconds.

> "That's the whole ask for a busy family: one tap at bedtime. Streaks and badges
> do the nagging so teachers don't have to. It works offline and syncs later, and
> reminders respect your quiet hours."

### Beat 3 — The teacher moment (6:00–11:00) · *web, as Priya*

1. Class 3G dashboard: **who read last night** — Ava's log from Beat 2 is already
   there. Say so: *"that's the entry Sarah just made, live."*
2. Open Ava's log → the comment thread → **reply as Priya** ("Fantastic — moving
   her up a book!") → **Sarah's iPhone pings on screen.** This is the killer
   moment; pause on it.
3. Riley Thompson: quietly flagged, 14 days silent. *"You find out in week 2, not
   at parent-teacher night in week 9."*
4. Allocations: the level-based assignment (J–N) that put tonight's book on Ava's
   app; set-and-forget cadence. In person: scan a real book's barcode (ISBN
   scanner) into the library.

> "No more collecting 25 diaries on a Friday. Priya sees the class at a glance,
> replies in seconds, and the right books go home by reading level."

### Beat 4 — The leader moment (11:00–15:00) · *school-admin portal, as Dana*

1. Dashboard: school-wide minutes, engagement trend, class comparison (3G vs 5B).
2. At-risk view: Riley again — same signal, school-wide lens.
3. Parent-links tab: the funnel — linked / ready / no subscription. *"You can see
   exactly which families are on board."*
4. Rollout proof: CSV roster import + **generate-all-codes** button. *"Your office
   uploads the roster, prints code letters, done — rollout is one afternoon, and
   we can do it with you."*

### Beat 5 — Close (15:00–18:00) · *stop sharing, face them*

1. Anchor to the diary: *"You already budget $7–15 per child for paper. Lumi is
   [retail band for their size] per student per year — see the pricing page."*
   (Bands from go-to-market.md §4.2. **Never quote wholesale numbers unprompted**;
   600+ students → "let's put a volume quote together.")
2. Trial: *"30 days, whole school, free, no card. If the teachers don't love it,
   you've lost nothing."*
3. **Book the next step before you hang up**: trial kickoff or onboarding call,
   date agreed now.

---

## 6. The two live moments — choreography & fallbacks

The demo has exactly two moments that depend on live infrastructure. Rehearse
them; protect them.

**Round-trip A — parent log → teacher dashboard** (Beat 2 → Beat 3):
log on the phone *before* switching to the teacher window; by the time you've
said the transition line, the log is on Priya's dashboard. If it isn't: pull-to-
refresh, keep talking, it lands.

**Round-trip B — teacher reply → parent push** (Beat 3):
requires the phone to have notification permission, DND off, and the app
backgrounded (not force-quit). Send the reply, then *stop talking* until the
banner drops. Nothing you say beats that banner.

**Plan B (record these once, keep on the desktop):**
1. 30s clip — parent quick-log + streak tick
2. 30s clip — teacher reply → push notification landing
3. Screenshot deck — admin analytics, at-risk, parent-links funnel

If the venue network dies: *"Rather than fight the wifi, here's the exact moment
recorded yesterday"* — then keep the live admin portal on your hotspot.

---

## 7. Objection handling

| Objection | Response |
|---|---|
| "Some families don't have smartphones." | Teachers/office can log on a student's behalf; multiple guardians (grandparents, carers) can link to one child; a paper fallback can coexist for the handful who need it. The school still gets one system of record. |
| "What about privacy / our data?" | School-scoped tenancy; parents see only their own children; real parent accounts use SMS multi-factor; audited access. Offer the security one-pager. **Don't ad-lib compliance claims** — go-to-market.md §9 (legal review) governs what we assert. |
| "Teachers are already overloaded." | Teachers *receive* data instead of collecting diaries; allocations are set-and-forget; commenting is optional and takes seconds. Show Beat 3 again if needed. |
| "We tried an app and it died out." | Adoption lives and dies on the parent tap being trivial — that's why the demo starts at one tap, streaks, and reminders. Plus the school sees engagement live (parent-links funnel), so you can chase stragglers in week 1, not term 3. |
| "What does it cost?" | Anchor to the paper diary; give the public retail band for their size; 600+ → volume quote conversation. Never discount on the spot. |
| "Can it import our student list?" | Yes — CSV import, shown in Beat 4. For assisted rollouts we do it for you. |

---

## 8. Hygiene & guardrails (non-negotiable)

- **Reset before every demo.** Live demos mutate the data (logs, comments, used
  link codes, consumed badge popup). `--reset` restores the exact starting state.
- **Never** show a real school's data, the super-admin portal, the impersonation
  tooling (support-only — see `impersonation-runbook.md`), or your terminal.
- **Never mention KAKA to retail prospects.** Per go-to-market.md, the KAKA
  connection is confidential; it may only come up in wholesale conversations with
  existing KAKA customers — and even then, you don't volunteer it on screen.
- Wholesale pricing never appears on a slide, screen, or leave-behind.
- Demo data is fictional — say so if asked ("this is our demo school").

---

## 9. Lead capture → follow-up loop

- **Inbound:** the public site's *Request Demo* form (`DemoRequestScreen`) creates
  a `schoolOnboarding` record (status `demo`) with school size and referral
  source — triage these in the admin portal's onboarding pipeline and book the
  call from there.
- **Outbound/in-person:** after the demo, create the same record yourself so every
  prospect lives in one pipeline (`demo → interested → registered →
  setupInProgress → active`).
- **Within 24h send the recap:** three bullets tailored to what landed (usually:
  the round-trip moment, at-risk view, rollout-in-an-afternoon), the pricing band
  for their size, and the already-agreed next step with date.
- No reply in 5 days → one nudge referencing their trigger moment. Then one final
  "door's open" note. Update the onboarding status as you go.

---

## 10. Scaling the demo motion

**Cut-downs of the same golden path** (never invent a new flow on the fly):

- **5-minute teaser** (corridor, conference stand): Beat 2 + Round-trip B + the
  pricing anchor line. Phone only — it's the most portable demo you have.
- **45-minute committee** (leadership team, in person): full golden path, then
  hands-on — hand the iPad (as Priya) to the deputy, and let someone link
  **Billy Martin** live on your spare phone with the printed code. Finish with
  pricing + rollout plan discussion.

**Train-the-trainer checklist** (for the first sales/CS hire):

1. Watch you run it twice (once video, once in person)
2. Run the pre-demo ritual solo; you verify
3. Co-run: they drive Beats 2–3, you drive 4–5
4. Solo run, scored on: both live moments landed · story stayed on one family ·
   pricing anchored to the diary · next step booked · guardrails respected (§8)

**Async demo video:** record Beats 2–4 as a tight 3-minute screen capture off the
freshly-reset demo school and use it in follow-ups and on the landing page — same
story, same data, zero live risk.

---

## 11. Troubleshooting & quirks

| Symptom | Cause / fix |
|---|---|
| Parent login on a laptop bounces | By design — parents are mobile-only (`app_router.dart`). Use the iPhone. |
| No badge popup on app open | It fired earlier (once per seed) — run `--reset`. |
| Push notification didn't arrive | Permission denied, DND on, or app force-quit. Fix, resend the teacher reply — or use fallback clip 2. |
| Stats look slightly different minutes later | Cloud Functions recompute stats from logs on every write (gentle-streak tolerance can nudge numbers up). Cosmetic; converges. |
| Demo login asks for MFA | Demo accounts have none; you've hit a real account. Check the email you typed. |
| Seed fails: can't resolve `firebase-admin` | `cd functions && npm install`, re-run from the repo root. |
| Wrong project id at the confirm prompt | Stop. Point `FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH` at the LumiAU service account. |

---

*Related: [go-to-market.md](go-to-market.md) (pricing, channels, confidentiality) ·
[`scripts/seed_demo_school.js`](../scripts/seed_demo_school.js) (demo data) ·
[impersonation-runbook.md](impersonation-runbook.md) (support tooling — not for demos).*
