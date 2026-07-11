# Demo-Day Access Plan — rolling passwords for the shared demo school

**Status:** IMPLEMENTED (2026-07-11) — all five workstreams coded and in review; **prod
deploys pending** (all manual, confirm-first). Written 2026-07-11 after a 3-agent codebase
exploration. All open questions were resolved by Nic on 2026-07-11 — see §10.
**Goal owner:** Nic. **Implementer:** follow the PR workstreams in §7, in order.

### Implementation status

| PR | Branch | Scope | State | Deploy |
|---|---|---|---|---|
| PR-1 | `feat/demo-day-backend` | functions (`demo_access.ts`, email template) + rules + tests | PR open | **manual** `firebase deploy --only functions:processDemoAccessEmail,functions:scrambleDemoPasswords,firestore:rules` |
| PR-2 | `feat/demo-day-seed` | seed: `support+demo@` + teacher/parent renames + `platformConfig/demoAccess` | PR open | **manual** one-time seed run vs prod `lumi-ninc-au` |
| PR-3 | `feat/demo-day-portal` | admin portal: provision + email panel + history tab; `@lumi/server-ops`/`@lumi/types` | PR open | CI on merge — **blocked by a pre-existing zod-v4/@hookform build error on `main`** (see PR-3 notes) |
| PR-4 | `feat/demo-day-session-ttl` | school-portal: cap demo session to end-of-day Sydney | PR open | **manual** `hosting:school` deploy |
| PR-5 | `feat/demo-day-docs` | this STATUS + `docs/demo-playbook.md` | this PR | n/a |

**Merge order:** PR-1 must be **deployed** before PR-3 merges (its email button has no consumer
otherwise). PR-4 conceptually overlaps in-flight admin-TOTP work but was built decoupled (touches
only the inside of `createSessionCookie`). Full deploy/verify runbook: §8–§9.

---

## 1. Feature summary

Replace "provision a fresh school" for sales demos with a **persistent, pre-seeded demo school**
and a **rolling daily password**, driven from the super-admin portal's Onboarding kanban:

1. Demo requests from the marketing site already land in the `schoolOnboarding` pipeline with
   `status: "demo"` (first kanban column). On such a request, instead of "Provision school", the
   operator clicks **"Provision today's demo password"**.
2. That rotates the password on the demo school's login accounts. The **admin login email never
   changes**: `support+demo@lumi-reading.com`. The password **only works that calendar day**
   (Sydney time) — a nightly cron scrambles it.
3. A second button, **"Email demo details"**, sends the requester (the `contactEmail` captured by
   the marketing form) a SendGrid email containing: the day's credentials, a link to
   lumi-reading.com (whose nav already has a portal Log-in link), the direct portal login URL,
   App Store / Google Play download instructions, and **teacher + parent demo app logins** using
   the same day password.
4. This supports demos run over Zoom as well as in person: the prospect can log in themselves
   during/after the call, and access self-expires at midnight.

---

## 2. What already exists (verified, with file refs)

Do **not** rebuild these — reuse them.

| Piece | Where | Notes |
|---|---|---|
| Persistent demo school | `scripts/seed_demo_school.js` — `SCHOOL_ID = "lumi_demo_primary_school"`, "Lumi Demo Primary School", `isDemo: true` (`:149,154,532`) | Fully populated sales-demo tenant; `--reset` guard refuses non-`isDemo` schools (`:900-903`). This is the school to use. |
| Demo accounts (Auth + Firestore) | `seed_demo_school.js:157-215` | `demo.admin@lumidemo.school` (schoolAdmin), `demo.teacher@lumidemo.school`, `demo.parent@lumidemo.school` (+ demo.teacher2/parent2/ghosts). Shared **hardcoded** password `LumiDemo!2026` (`:151`) — in the repo, effectively public. The rolling rotation fixes this. |
| Demo playbook | `docs/demo-playbook.md` | 300-line runbook incl. logins table and pipeline flow; must be updated at the end (§9). |
| Marketing demo form → pipeline | `marketing-site/src/app/book-a-demo/page.tsx` → callable `submitDemoRequest` (`functions/src/marketing_leads.ts:56-113`) | Writes a `schoolOnboarding` doc: `status:"demo"`, `contactEmail`, `contactPerson`, `schoolName`, extras packed into `metadata.notes`. **No email is sent** on this path today. |
| Kanban board + demo column | `admin/src/app/(auth)/onboarding/onboarding-pipeline.tsx:13-20` (STAGES, `demo` is first, cyan) | Cards route to `/onboarding/{id}`; the only board action is drag-to-change-status. All real actions live on the detail page. |
| Detail page + demo prose | `admin/src/app/(auth)/onboarding/[id]/onboarding-detail.tsx:49-55` | When `status === "demo"` shows text: "Demos run as a live call on the shared Lumi Demo school — reset it before each demo." **This block is what the new panel replaces.** |
| Real-school provision flow (the template to mirror) | `admin/src/lib/onboarding/provision.ts:43-141` + `admin/src/app/api/onboarding/[id]/provision/route.ts` + `provision-panel.tsx` | Pattern: client panel → `fetch` Next API route → `verifySession()` → server-ops primitives → audit log → `router.refresh()`. |
| Portal→backend pattern | Next API routes + `firebase-admin` (`admin/src/lib/firebase-admin.ts`), server-ops in `packages/server-ops/` | NOT callables. Super-admin gate is at login (`admin/src/app/api/auth/route.ts:20` → `isSuperAdminViaFirestore`, backed by `/superAdmins/{uid}`); per-route handlers re-verify only the `__session` cookie. |
| Email infra | SendGrid only (`@sendgrid/mail`), secrets `SENDGRID_API_KEY` / `SENDGRID_SENDER_EMAIL` (`functions/src/index.ts:12-13`) | Live pattern = Firestore **queue-doc triggers**: `processStaffOnboardingEmail` on `schools/{id}/staffOnboardingEmails/*` (`index.ts:2211`, send at `:2330`), templates in `functions/src/email_templates.ts`, mascot inline image in `email_assets.ts`. No Trigger Email extension, no nodemailer. |
| Temp-password generator | `functions/src/temp_password.ts:18` `generateTempPassword(length=12)` (crypto, unambiguous alphabet, guaranteed classes); mirror at `school-admin-web/src/lib/utils/temp-password.ts` | The staff-onboarding flow already does `admin.auth().updateUser(uid, {password})` (`index.ts:2303`) and stores the plaintext in Admin-SDK-only `staffCredentials` (`firestore.rules:659`). Same precedent for us. |
| Cron pattern | v2 `onSchedule` from `firebase-functions/v2/scheduler`; region auto-inherited from `functions/src/global_options.ts`; `timeZone` per function. Precedents: `cleanupExpiredLinkCodes` (`0 2 * * *`), `topReaderAward` (Sydney tz) | `DEFAULT_TIMEZONE = "Australia/Sydney"` in `functions/src/access.ts:16`. |
| Portal login URL + marketing login link | Portal: `https://lumi-school-admin-au.web.app/login` (`.firebaserc:13-15`). Marketing nav **already links to it**: `marketing-site/src/components/landing/Nav.tsx:83-88` | **No marketing-site work required** for "lumi-reading.com has a login link" — verify only. |
| School-portal login/MFA | `school-admin-web/src/app/login/page.tsx`; session `api/auth/session/route.ts` (schoolId claim cache `:101-105`); signed-JWT `__session` cookie, **5-day expiry** (`lib/auth/session.ts:44-68`) | MFA is only challenged if a phone factor is *enrolled* — demo accounts have none, so email+password just works. Portal requires the user doc `role` be `teacher`/`schoolAdmin`; middleware gates admin routes to `schoolAdmin` (`middleware.ts:120-128`). |
| Flutter app login | `lib/screens/auth/login_screen.dart:248-445` | Email+password only; school resolved via `userSchoolIndex` email hash — **no school/class code needed at login** (codes are registration-only). Parent app is **mobile-only** (web redirects). |
| App Review accounts (DO NOT TOUCH) | `scripts/seed_demo_review_account.js` — school `demo-review-school`, `review.teacher@`/`review.parent@lumi-reading.com` | Separate school for Apple review. The rotation/scramble must NEVER include these — Apple can re-review at any time. |

Key gaps this feature fills: no `support+demo@` account exists anywhere yet; the portal sends no
email of any kind today; there is no scheduled password rotation; nothing reads `isDemo`.

---

## 3. Architecture decisions (recommended; alternatives noted)

### D1 — Where rotation runs: **portal-side (server-ops)**, not a callable
Matches every other onboarding mutation (Next API route → `verifySession()` → Admin SDK).
`manageParentAccount`/`manageSchoolUserAuth` already do `updateUser` from server-ops.
Alternative (rejected): a Cloud Functions callable — inconsistent with the portal pattern and
functions deploys are manual/slow to iterate.

### D2 — "Only works that day" enforcement: **nightly scramble cron + refresh-token revocation**
- New scheduled function `scrambleDemoPasswords`, `schedule: "5 0 * * *"`, `timeZone: Australia/Sydney`
  (00:05 gives a small grace past midnight). Unconditionally, for each configured demo account:
  `updateUser(uid, { password: <random 40+ chars, never stored> })` + `revokeRefreshTokens(uid)`,
  then stamp `scrambledAt` on the state doc.
- Unconditional daily scramble is idempotent, needs no state to be correct, and permanently
  neutralises the hardcoded `LumiDemo!2026` from the seed script.
- App sessions die ≤ ~1h after revocation (ID tokens expire, refresh is revoked).
- **Portal session tail:** the school portal's cookie is a locally-verified JWT (5 days), so a
  session opened on demo day would otherwise outlive the password. Fix in workstream PR-4:
  cap the session cookie for the demo school to end-of-day Sydney.
- Alternative (rejected): GCIP blocking `beforeSignIn` checking a validity doc — no blocking
  functions exist in the repo today; more infra for the same outcome.

### D3 — Password scope: **one password per calendar day, shared by admin+teacher+parent**
- First "Provision" of the day generates it; later clicks the same day **reuse** it (idempotent).
  This prevents demo #2 invalidating demo #1 mid-call, and matches "a password on demo day".
- Same password for all three accounts — far easier to read out over Zoom.
- Generate with `generateTempPassword(12)` (port into server-ops; see D6).

### D4 — Accounts covered
All three shared accounts use `@lumi-reading.com` plus-aliases (decision: Nic controls that
mailbox, so Firebase password-reset emails for these accounts are actually receivable —
plus-addressing to this domain is already proven working, cf. `support+student0@lumi-reading.com`
in `docs/fcm-push-debug-handoff.md:154`).

- **Admin (shared with prospects):** `support+demo@lumi-reading.com` — NEW schoolAdmin in
  `lumi_demo_primary_school`. Find-or-create Auth user + `schools/{id}/users/{uid}` doc with
  `role: "schoolAdmin"` (reuse `createSchoolUser` semantics). No MFA enrolment, ever.
- **Teacher (shared):** `support+demo.teacher@lumi-reading.com` — **RENAME** of the existing
  `demo.teacher@lumidemo.school` account (see migration note below).
- **Parent (shared):** `support+demo.parent@lumi-reading.com` — **RENAME** of the existing
  `demo.parent@lumidemo.school` account (mobile app only — say so in the email).
- **Rotated-but-not-shared:** `demo.admin@lumidemo.school` (kept as internal/backup admin, never
  shared), `demo.teacher2@`, `demo.parent2@` (any Auth-bearing demo account) — included in the
  nightly scramble so no account in this school keeps a known password; only the three shared
  accounts get the day password on Provision.
- **Excluded always:** anything in `demo-review-school` (`review.*@lumi-reading.com`).
- Safety rule: rotation/scramble resolves accounts from config **and verifies each uid has a user
  doc under `schools/lumi_demo_primary_school`** before touching it. Never rotate by query.

**Rename migration (teacher + parent), part of PR-2:** rename **by uid**, do NOT delete/recreate
(Firestore docs are keyed by uid; recreating would orphan classes, logs, linked children):
1. `getUserByEmail(old)` → `admin.auth().updateUser(uid, { email: new, emailVerified: true })`.
2. Update the `email` field inside the corresponding `schools/{id}/users/{uid}` / parents doc.
3. Write new `userSchoolIndex` email-hash entries for the new addresses and **delete the old
   entries** (the Flutter app resolves school membership via this index at login —
   `lib/screens/auth/login_screen.dart:248-445`; a stale/missing entry breaks app login).
4. Keep the seed script idempotent: find-or-create must look up by NEW email first, falling back
   to the old email + rename, so re-runs don't create duplicate accounts.
5. Side effect (desirable): the super-admin Parents page test-account heuristic
   (`parents-table.tsx:20-28`) matches `support+`/`@lumi-reading.com`, so these accounts are
   correctly bucketed as test accounts.
6. Check `docs/demo-playbook.md` and any seeded in-app content for hardcoded old addresses.

### D5 — Email delivery: **new top-level queue collection + Firestore-trigger function**
- Portal writes `demoAccessEmails/{autoId}` (Admin SDK); new function `processDemoAccessEmail`
  (onDocumentCreated) renders the template and sends via SendGrid with the existing secrets,
  updating `status: queued → processing → sent/failed` exactly like `processStaffOnboardingEmail`.
- The queue doc carries recipient + onboarding context but **not the password**; the trigger reads
  the live state doc and **refuses to send if the state's dayKey ≠ today (Sydney) or already
  scrambled** — impossible to email a stale password.
- **The queue docs double as the permanent paper trail** (decision: Nic wants send history
  visible in the portal, not buried in an email inbox): docs are never deleted, and the trigger
  writes back `sentAt`, `status`, and the rendered `subject` so each doc fully describes what was
  sent, to whom, when, by which operator, and for which onboarding request. A history panel on
  the demo school's detail page renders this collection (see D7). Every send also BCCs
  `support@lumi-reading.com` as an exact-content backup.
- Alternative (rejected): SendGrid directly from the Next server — spreads the API key into the
  admin portal's env/CI; queue-doc keeps the secret in functions and gives a visible send status.

### D6 — Config & state homes
- **Config (non-secret), editable without a functions deploy:** `platformConfig/demoAccess`:
  ```
  { schoolId: "lumi_demo_primary_school",
    adminEmail: "support+demo@lumi-reading.com",
    teacherEmail: "support+demo.teacher@lumi-reading.com",
    parentEmail: "support+demo.parent@lumi-reading.com",
    scrambleOnlyEmails: ["demo.admin@lumidemo.school", "demo.teacher2@lumidemo.school", "demo.parent2@lumidemo.school"],
    portalLoginUrl: "https://lumi-school-admin-au.web.app/login",
    marketingUrl: "https://lumi-reading.com",
    appStoreUrl: null, playStoreUrl: null }   // null ⇒ email omits/replaces that line, see §5
  ```
  (platformConfig docs are client-`get`-able per `firestore.rules:911-914`; nothing here is secret.)
- **State (contains plaintext day password → Admin-SDK-only):** `demoAccess/state` (single doc,
  new top-level collection, explicit deny-all rules like `superAdmins` at `firestore.rules:921-923`):
  ```
  { dayKey: "2026-07-11",            // Sydney YYYY-MM-DD
    password: "Xk7mPq9RtW2c",        // plaintext, staffCredentials precedent (rules:659)
    issuedAt, issuedBy: {uid,email},
    accounts: [{role, email, uid}],  // the 3 shared accounts as rotated
    scrambledAt: null,
    lastEmail: {to, onboardingId, sentAt, status} }
  ```
- **Queue:** `demoAccessEmails/{id}` — also explicit deny-all in rules.
- `generateTempPassword`: add a third copy in `packages/server-ops/src/utils/tempPassword.ts`
  (port of `functions/src/temp_password.ts`). Yes, that's a 3rd mirror; hoisting all three into a
  shared package is out of scope — leave a TODO comment referencing the other two.

### D7 — UI placement
- **Primary:** new `DemoAccessPanel` on the onboarding **detail page**, rendered when
  `status === "demo"`, replacing the prose block at `onboarding-detail.tsx:49-55`. The real
  ProvisionPanel stays available below it (schools that convert still get provisioned later,
  unchanged). The panel also shows the send history **for this request** (its own
  `demoAccessEmails` docs: recipient, sent time, status).
- **Paper-trail history panel (required, decision #3):** a "Demo access emails" section on the
  demo school's detail page — `admin/src/app/(auth)/schools/[schoolId]/` — rendered **only** when
  `schoolId === platformConfig/demoAccess.schoolId` (or `school.isDemo`). Table of ALL
  `demoAccessEmails` docs, newest first: sent date, recipient, contact/school name from the
  originating request, status (sent/failed), requested-by, and a link to the onboarding request.
  Read via a server fetch like the rest of the page (Admin SDK; the collection is deny-all to
  clients). This is the canonical "who has been given demo access" view.
- **Optional (nice-to-have, cut if time):** a small "Demo access →" affordance on kanban cards in
  the demo column linking to the detail page — the board has no per-card actions today and the
  detail page is 1 click away, so no board-level mutation buttons.

---

## 4. Detailed behaviour spec

### "Provision today's demo password" (button 1)
`POST /api/onboarding/[id]/demo-access` `{ action: "provision" }`
1. `verifySession()`; load onboarding doc (must exist; any status, but UI only shows for `demo`).
2. Compute `dayKey` = today in `Australia/Sydney`.
3. If `demoAccess/state` has same `dayKey` and `scrambledAt == null` → return existing state
   (idempotent; UI shows "issued earlier today at HH:mm by X").
4. Else: `password = generateTempPassword(12)`. For each of admin/teacher/parent config emails:
   - admin: find-or-create Auth user + ensure `schools/{demoSchoolId}/users/{uid}` doc with
     `role:"schoolAdmin"`, `isActive:true` (mirror `createSchoolUser`).
   - teacher/parent: `getUserByEmail`; **verify** their user/parent doc lives under the demo
     school; fail loudly if missing (means seed drifted — do not create app accounts here).
   - `updateUser(uid, { password })`.
5. Write `demoAccess/state` (full replace) with `scrambledAt: null`.
6. Update the onboarding doc: `demoAccessProvisionedAt: serverTimestamp()`, `lastUpdatedAt`.
7. Audit log `onboarding.demoProvision` (mirror `onboarding.provision` at `provision.ts:123-138`).
8. Return `{ password, accounts, expiresAtLabel }` → panel displays credentials with copy buttons.

### "Email demo details" (button 2)
`POST /api/onboarding/[id]/demo-access` `{ action: "sendEmail" }`
1. `verifySession()`; load onboarding doc → `to = contactEmail`, `contactPerson`, `schoolName`.
2. Require an active (today, unscrambled) `demoAccess/state`; else 409 "Provision first".
3. Write `demoAccessEmails/{autoId}`:
   `{ onboardingId, to, contactPerson, schoolName, dayKey, requestedBy, status: "queued", createdAt }`.
4. Update onboarding doc `demoEmailLastSentAt` (optimistic; trigger writes real status to the
   queue doc, which the panel surfaces after `router.refresh()`), audit `onboarding.demoEmail`.
5. UI: **ConfirmDialog before sending** (`src/components/shared/confirm-dialog.tsx`) — this emails
   an external party. Show recipient address in the dialog.

### `processDemoAccessEmail` (functions trigger)
- `onDocumentCreated("demoAccessEmails/{id}")`, secrets `SENDGRID_API_KEY`/`SENDGRID_SENDER_EMAIL`.
- Claim doc (`status: "processing"`), re-read `demoAccess/state`; abort→`failed` with reason if
  `state.dayKey !== todaySydney` or `scrambledAt != null`.
- Render `buildDemoAccessEmail` (new, in `email_templates.ts`, follow `buildStaffOnboardingEmail`
  incl. mascot asset), send with **BCC `support@lumi-reading.com`** (decision #3), set
  `status: "sent" | "failed"` + `sentAt`/`error`/`subject` on the queue doc (it is the permanent
  paper-trail record — never delete these docs), and mirror into `demoAccess/state.lastEmail`.

### `scrambleDemoPasswords` (functions cron)
- `onSchedule({ schedule: "5 0 * * *", timeZone: "Australia/Sydney" })`.
- Read `platformConfig/demoAccess`; resolve every email in {admin, teacher, parent,
  scrambleOnlyEmails}; verify school membership; `updateUser(uid, {password: cryptoRandom(40)})`
  (throwaway, never stored) + `revokeRefreshTokens(uid)`.
- Set `demoAccess/state.scrambledAt = now` if state exists. Log per-account results; never throw
  on a single-account failure (continue, report at end).

---

## 5. Email content (draft for `buildDemoAccessEmail`)

Subject: `Your Lumi demo access for {weekday d MMM}`

- Hi {contactPerson|there}, thanks for booking a Lumi demo — here's everything you need for
  today's session ({schoolName}).
- **School admin portal** (works in any browser):
  - Go to {marketingUrl} and click **Log in** (top right), or go straight to {portalLoginUrl}.
  - Email: `support+demo@lumi-reading.com` · Password: `{password}`
- **The Lumi app** (how teachers & parents use Lumi day-to-day):
  - Download from the App Store: {appStoreUrl} / Google Play: {playStoreUrl}
    *(if a URL is null in config: replace the line with "search for "Lumi Reading" in the
    App Store / Google Play" — do NOT ship dead `#` links; see Open Q1)*
  - Teacher login: `support+demo.teacher@lumi-reading.com` · same password
  - Parent login: `support+demo.parent@lumi-reading.com` · same password (parent experience is in
    the mobile app only)
- These logins are live **today only** and expire at midnight (AEST/AEDT). Ask us for fresh
  access any time.
- This is a shared demo environment with sample students — please don't enter real student data.
- Reply-to: `support@lumi-reading.com`. From: `SENDGRID_SENDER_EMAIL` secret.
- HTML-escape ALL interpolated request fields (`escapeHtml` precedent in `marketing_leads.ts:35`) —
  `contactPerson`/`schoolName` are attacker-controlled via the public form. The password comes
  from our generator (safe alphabet) but escape it anyway.

---

## 6. Security notes

- Blast radius: `support+demo@` is schoolAdmin of the demo school only; portal binds sessions to
  that `schoolId`. It can never see another tenant.
- The **schoolId custom-claim cache** (`session/route.ts:101-105`): fine — the claim just points
  at the demo school. Do not put demo state in claims.
- Plaintext day-password storage: same precedent as `staffCredentials` (`firestore.rules:659`);
  both new collections get explicit deny-all rules + tests in
  `functions/test/firestore.rules.test.js` (existing convention).
- The queue collection is only writable via Admin SDK (deny-all rules) → the trigger can trust
  queue docs, but still validates state freshness before sending.
- The public `submitDemoRequest` callable stays unauthenticated/App-Check-off (existing state).
  Nothing here auto-triggers off it — a super-admin click is always in the loop, so no new abuse
  surface. (App Check enforcement remains a separate backlog item.)
- Never enrol MFA on demo accounts; never touch `demo-review-school` accounts.
- Demo data hygiene is unchanged: `scripts/seed_demo_school.js --reset` before demos, per
  playbook. (A portal "Reset demo data" button is a possible follow-up, NOT in this scope.)

---

## 7. Workstreams / PR plan (implement in this order)

Branch naming `feat/demo-day-*`, squash-merge each. **Merge order matters** because the admin
portal auto-deploys via CI on merge, while functions/rules/school-portal deploys are MANUAL.
Merging the portal UI before the functions are deployed would ship an email button whose queue has
no consumer — so backend first.

### PR-1 `feat/demo-day-backend` — functions + rules
- `functions/src/demo_access.ts`: `processDemoAccessEmail` trigger + `scrambleDemoPasswords` cron
  (spec §4), config/state readers, Sydney `dayKey` helper (reuse existing tz utilities in
  `access.ts` if suitable).
- `functions/src/email_templates.ts`: `buildDemoAccessEmail` (§5).
- `functions/src/index.ts`: export both (keep `global_options` import-order convention).
- `firestore.rules`: explicit deny-all for `demoAccess/{doc}` and `demoAccessEmails/{doc}`;
  rules tests in `functions/test/firestore.rules.test.js`.
- Gate: `cd functions && npm run lint && npx tsc --noEmit` (predeploy runs eslint+tsc — a
  non-lint-clean merge blocks ALL future functions deploys) + rules tests via emulator.

### PR-2 `feat/demo-day-seed` — seed script + config + renames (parallel with PR-1)
- `scripts/seed_demo_school.js`:
  - Add `support+demo@lumi-reading.com` schoolAdmin (Auth user + `schools/{id}/users/{uid}` doc +
    `userSchoolIndex` entry for consistency).
  - **Rename** teacher/parent shared accounts to `support+demo.teacher@` /
    `support+demo.parent@lumi-reading.com` per the D4 migration steps (rename by uid, update doc
    email fields, rewrite + clean `userSchoolIndex` entries, new-email-first idempotent lookup).
  - Seed/refresh `platformConfig/demoAccess` (§D6). Keep idempotent; keep the `isDemo` reset guard.
- Update `docs/demo-playbook.md` login table + flow (or defer doc update to PR-5 if preferred).

### PR-3 `feat/demo-day-portal` — admin portal (after PR-1 is MERGED **and DEPLOYED**)
- `packages/server-ops/src/provisionDemoAccess.ts` (+ `utils/tempPassword.ts` port, + export).
- `packages/types/src/demo-access.ts`: `DemoAccessState`, `DemoAccessEmailDoc`,
  `PlatformDemoAccessConfig` (+ export); functions may keep local mirrors per existing convention.
- `admin/src/lib/onboarding/demo-access.ts`: orchestration (provision, sendEmail, getState).
- `admin/src/app/api/onboarding/[id]/demo-access/route.ts`: POST `{action}` dispatch, Zod schema
  in `admin/src/lib/validations/onboarding.ts`.
- `admin/src/app/(auth)/onboarding/[id]/demo-access-panel.tsx`: panel per §D7/§4 — state display
  (issued/expiry/scrambled/last-email-status), Provision button, Email button behind
  ConfirmDialog, credential rows with copy buttons (mirror `provision-panel.tsx` result card),
  `toast` + `router.refresh()` on completion, plus this request's send history.
- `onboarding-detail.tsx`: swap the `:49-55` prose block for the panel when `status === "demo"`.
- **Demo-emails history section** on the demo school's detail page
  (`admin/src/app/(auth)/schools/[schoolId]/`), per D7: server-fetched table of all
  `demoAccessEmails`, shown only for the demo school. Follow the page's existing data-fetch and
  `DataTable`/Card patterns.
- Gate: `tsc` + `next build` for `admin/` (never against a running dev server).

### PR-4 `feat/demo-day-session-ttl` — school portal hardening (IN SCOPE, decision #5)
- `school-admin-web/src/app/api/auth/session/route.ts` + `lib/auth/session.ts`: if resolved
  `schoolId === <demo school id>` (const or env), cap the `__session` JWT/cookie maxAge at
  end-of-day Sydney instead of 5 days. Closes the "session outlives the password" tail (§D2).
- Optional extra: a small "Demo environment" banner in the portal shell when
  `schoolId === demo` — cut if noisy.
- Gate: `tsc` + `next build` (same dev-server caveat). Requires a manual portal deploy.

### PR-5 `docs` — finish `docs/demo-playbook.md` updates + this plan's STATUS table if not folded
into PR-2.

---

## 8. Deployment & ops runbook (all prod steps: confirm with Nic first)

1. Merge PR-1 → **manual** `firebase deploy --only functions:processDemoAccessEmail,functions:scrambleDemoPasswords,firestore:rules`.
   (Watch for the known orphaned-functions deploy gotcha.)
2. Merge PR-2 → **manual** one-time run of the updated seed script against prod
   (`lumi-ninc-au`) to create `support+demo@` + `platformConfig/demoAccess`. Verify:
   `support+demo@` can log into `https://lumi-school-admin-au.web.app/login` after a manual
   password set/rotation.
3. Merge PR-3 → admin portal auto-deploys via CI. Feature is now live.
4. Merge PR-4 → **manual** school-portal deploy
   (`FIREBASE_CLI_EXPERIMENTS=webframeworks firebase deploy --only hosting:school`; run
   `pnpm install --ignore-workspace` in `school-admin-web` first if deps changed).
5. Fill in `appStoreUrl`/`playStoreUrl` in `platformConfig/demoAccess` when the store listings are
   live (no deploy needed — that's why it's config).

## 9. End-to-end verification (after deploys)

1. Marketing site: submit a Book-a-Demo with a test email you control → card appears in the demo
   column.
2. Detail page → Provision → password displayed; incognito login to the school portal as
   `support+demo@lumi-reading.com` works; app login as `support+demo.teacher@lumi-reading.com`
   and `support+demo.parent@lumi-reading.com` with the same password works (proves the
   `userSchoolIndex` rehash from the rename migration is correct).
3. Provision again same day → same password returned (idempotent), no rotation.
4. Email button → confirm dialog shows your test address → email arrives (with BCC copy at
   `support@lumi-reading.com`); all links resolve; no `#` placeholders; credentials correct.
   The send appears in the history panel on the demo school's detail page AND on the onboarding
   request's panel, with status `sent`.
5. Force-run the cron (`gcloud scheduler jobs run ...` or temporarily reschedule) → old password
   rejected on portal AND app; app session dies within ~1h; state doc `scrambledAt` set;
   attempting Email now returns the stale-state failure.
6. Next day Provision issues a fresh password.
7. Confirm `review.teacher@`/`review.parent@` (App Review school) still log in with
   `LumiReview2026!` — proves the scramble scope is correct.
8. Rules check: unauthenticated + authed non-admin clients cannot read `demoAccess/*` or
   `demoAccessEmails/*` (covered by rules tests, spot-check live).

---

## 10. Decisions (resolved by Nic, 2026-07-11) — already baked into the spec above

1. **Store URLs**: ship with `appStoreUrl/playStoreUrl = null` + the "search for Lumi Reading"
   fallback line in the email; paste real URLs into `platformConfig/demoAccess` once the store
   listings are live (config-only, no deploy). No TestFlight mention.
2. **`demo.admin@lumidemo.school`**: KEEP as internal/backup admin — never shared with prospects,
   included in the nightly scramble.
3. **Paper trail**: yes to BCC `support@lumi-reading.com`, AND (the primary record) an in-portal
   send-history view so Nic never has to search an inbox: the `demoAccessEmails` docs are kept
   forever and rendered as a table on the demo school's detail page
   (`schools/[schoolId]`) + per-request on the onboarding panel. See D5/D7.
4. **Teacher/parent demo emails**: RENAME to `support+demo.teacher@lumi-reading.com` and
   `support+demo.parent@lumi-reading.com` — Nic controls the lumi-reading.com mailbox, so
   password-reset emails for these accounts are actually receivable. Migration spec in D4
   (rename by uid, rewrite `userSchoolIndex`, update doc email fields).
5. **PR-4 session TTL**: IN SCOPE for this release — demo-school portal sessions are cut off at
   end of the Sydney day, matching the password expiry.
6. **Multiple demos/day share the day password** (D3): accepted.

---

## 11. Notes for the implementing session

- Workflow: branch → PR → squash-merge per repo convention; verify staged diff matches PR title.
- `functions` predeploy runs eslint+tsc — keep PR-1 lint-clean or you block all functions deploys.
- Do NOT run `dart format`/whole-file reformatting anywhere; keep diffs surgical (no Flutter
  changes are needed in this feature at all).
- Admin portal (`admin/`) deploys via CI on merge; functions/rules/school-portal/seed are all
  manual, prod, confirm-first.
- `Date`/timezone: compute Sydney dayKey with `Intl.DateTimeFormat` or the repo's existing tz
  helpers — do not hand-roll UTC+10 offsets (DST).
- The three status-enum copies (`onboarding-pipeline.tsx:13`, `onboarding-actions.tsx:20`,
  `validations/onboarding.ts:3`) are NOT touched — this feature adds no new pipeline status.
- Never touch `demo-review-school` / `review.*@lumi-reading.com`.
