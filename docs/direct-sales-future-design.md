# Direct / public-sales design (SHELVED — future reference)

> **Status: NOT on the launch path.** Build only when Lumi sells beyond KAKA Kids distribution.
> **Decision (KAKA directors + management, 2026-07-12):** the initial launch runs on
> **whole-school invoicing** — KAKA invoices the school for its entire enrolled headcount, and
> KAKA/Lumi **absorb** the small percentage of families who didn't buy a KAKA book pack (bounded,
> per KAKA's historical per-school order stats). No per-student direct payment for launch.
>
> This document preserves the design worked out for direct/public sales so it can be picked up
> later. It is the eventual behaviour of the `school.accessMode = 'direct_allowed'` mode introduced
> (dormant) by the launch feature — see the whole-school-paid launch plan.

## The problem this solves

Lumi access is distributed **bundled inside a KAKA Kids stationery/book pack** (in place of a
physical reading diary); KAKA↔Lumi money is settled in bulk, off-system. At a Lumi school ~95% of
families buy the pack. A minority source stationery elsewhere (e.g. Officeworks). The direct
channel is for (a) recovering revenue from that minority and (b) eventual general-public sales.

## Why a paid channel is non-trivial (preserve this finding)

**Lumi has no per-student paywall today — by design.** The model is *"active school subscription ⇒
every student is covered."*

- A **link code** only proves parent↔child identity. Issuing one is **not** gated on payment
  (except the automated onboarding-email batch, which skips `not_enrolled`).
- **Access** (`student.access`) is the real entitlement. The Firestore rule that gates reading-log
  creation, `studentAccessLive` (`firestore.rules:134`), checks only `isActive` + `access.status` +
  `access.expiresAt` — never `enrollmentStatus` or any payment record.
- On parent link, if the school sub is active and the student isn't explicitly `revoked`,
  `linkParentToStudentCore` (`functions/src/parent_linking.ts:397-419`) **auto-grants a full year of
  `book_pack_assumed` access** — no payment check. So a non-payer with any valid code links and
  reads free. `enrollmentStatus` (`book_pack`/`direct_purchase`/`not_enrolled`) is a **cosmetic
  label** that drives nothing in enforcement.
- Import default is `enrollmentStatus:'not_enrolled'` with **no `access` map**; the bulk/auto-grant
  paths (`provisionUnprovisionedStudents`, `activateAccessForYear`, the link auto-grant) then grant
  `book_pack_assumed` to every non-`revoked` active student. The only durable "no access" lever is
  an explicit `access.status='revoked'`.

**Implication:** selling per-student access requires **flipping the default** from "on unless
revoked" to **granted-only** (fail-closed). That is safe only once every covered student is
reliably granted first — otherwise flipping locks out paying customers.

## Coverage source = KAKA voucher redemption (dissolves the dirty-data problem)

Reconciling KAKA purchase records back to the school roster is unreliable — ~20% of KAKA online
entries have a wrong student code or a misspelt name. Fix: **make the entitlement travel with the
purchase**, not get matched after the fact. Lumi controls the KAKA backend too, and **each school
has its own KAKA web portal/domain**, which makes this clean:

- At checkout, the KAKA backend **server-stamps the correct `schoolId`** (the parent never types it
  → it can never be wrong) and issues a **voucher code per Lumi seat**.
- **Backbone (reliable):** KAKA pushes `{voucherCode, schoolId, studentName, kakaStudentCode,
  parentEmail, academicYear}` to a Lumi API (`POST /kaka/vouchers`) → Lumi stores a **pending
  voucher**. Coverage never depends on the parent clicking anything.
- **Courtesy front-end:** the KAKA order-confirmation page links to
  `lumi-reading.com/redeem?code=LUMI-XXXX`. The page validates the code, lets the parent
  **confirm/fix the child's name** (free dirty-data cleanup by the person who knows the right
  spelling), and shows *"reserved & paid — ready for the new school year, nothing more to do."*
  Honest wording: at purchase time the student record doesn't exist in Lumi yet, so redemption =
  a **reservation**, not an instant grant.
- **Matching-free final grant:** when the school later issues link codes and the parent links their
  child, the authoritative `studentId` comes from the school's link code. Lumi sees the
  parent/school has a redeemed voucher and grants `book_pack_assumed` to that exact student — **no
  roster name-matching ever happens.** The admin sees a subscribed/paid indicator (pending at
  redemption → firm at link).
- **Fail-safe:** on genuine ambiguity, grant a short **provisional** access (e.g. 2–4 weeks) and
  flag for review, rather than hard-locking a family that did pay.

This makes *flip-the-default* safe: **covered = has a redeemed KAKA voucher; everyone else pays
direct.**

## Stripe direct channel (for the non-covered / general public)

Retail **A$12.95 / child / year**, one-time payment, AUD (aligns to the fixed 31-Jan academic
expiry — no auto-renew; parent re-buys each year).

- Audience v1-future: non-KAKA families **at a Lumi school** — the child is a real rostered student,
  so reuse the existing `parent_direct` path (NOT a synthetic school). Identify `{schoolId,
  studentId}` via the **school-issued link code** (`verifyStudentLinkCode` / `resolveLinkCodeSchool`
  — unauthenticated, read-only, rejects used codes) → no school/class guessing. Sequencing gotcha:
  the code must still be **unused** at purchase (linking consumes it).
- Audience later: fully public / no-school families → needs a school-less student model (larger,
  separate).

**Constraint:** the marketing site is a **static export** (`marketing-site/next.config.js`
`output:'export'`) → **no Next API routes**; server-side Stripe must live in **Cloud Functions**.
The site already ships the Firebase client SDK (calls callables like `submitDemoRequest`).

- New `functions/src/stripe_direct.ts`, mirroring `functions/src/marketing_leads.ts` (v2 `onCall`,
  own `STRIPE_DIRECT_APP_CHECK_ENFORCED` flag default-off, `limitedString`,
  `enforceMarketingRateLimit`; region/SA from `global_options.ts`):
  - `lookupDirectPurchaseChild({code})` → child/school confirmation.
  - `createDirectCheckoutSession({code, email})` → validate code + active school sub + not already
    active → Stripe Checkout Session `mode:'payment'`, `metadata:{schoolId, studentId,
    academicYear}` → return hosted `{url}` (no Stripe.js needed on the client).
  - `stripeWebhook` (`onRequest` — the codebase's **first** HTTP function; verify `req.rawBody`
    signature; idempotency via `stripeEvents/{event.id}`) → grant via
    `buildStudentAccess({source:'parent_direct'})` (`functions/src/access.ts`), set
    `enrollmentStatus:'direct_purchase'`, stamp `stripeCustomerId` + `directPurchase{...}`.
- `defineSecret STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET`; add `stripe` to `functions/package.json`.
- Marketing: Direct "Get started" → `/get-started`; add `/checkout/{success,cancel}`; two callable
  refs in `marketing-site/src/lib/firebase.ts`.
- `firestore.rules`: add `directPurchase` to server-only student fields.
- PCI: Stripe hosted Checkout → Lumi never touches card data (SAQ-A).
- Deploy everything **manually** (CI deploys neither functions nor the marketing site).

## Reuse map

- `functions/src/access.ts` — `buildStudentAccess`, `hardExpiryFor`, `isActiveSubscriptionStatus`.
- `functions/src/parent_linking.ts` — `resolveLinkCodeSchool`, `verifyStudentLinkCode`.
- `functions/src/marketing_leads.ts` — onCall + App-Check flag + rate-limit pattern.
- `school-admin-web/src/lib/firestore/access-activation.ts` — `updateStudentEnrollmentAndAccess`
  already maps `direct_purchase → parent_direct`.
- The school roster already renders a blue **"Direct"** badge
  (`school-admin-web/.../students-page.tsx:373`) for `enrollmentStatus === 'direct_purchase'`.

## Edge cases already reasoned through

- **Double-pay:** `book_pack_assumed` and `parent_direct` both resolve to `status:'active'` — grants
  are idempotent, never stacked, never double-charged; checkout rejects an already-active student.
- **School sub lapses:** `onSchoolSubscriptionWrite` cascade suspends all that school's students,
  including `parent_direct` ones (they belong to that school). Acceptable; note it.
- **Later school claim:** stamping `stripeCustomerId` + `directPurchase` keeps a future admin
  "claim/transfer into a real class" tool possible; out of scope.
