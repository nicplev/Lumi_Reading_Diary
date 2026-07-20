# Lumi — Penetration Test Scoping Pack

> Prepared 20 July 2026 to brief prospective penetration-testing firms and
> obtain comparable quotes. Purpose: a security assessment whose report
> satisfies the ST4S evidence requirement (EV10/EV11) for Lumi's upcoming
> assessment, and independently strengthens Lumi's security posture before
> pilot. The AI comprehension feature is in scope (built but not enabled).
>
> **This is planning material. Nothing here authorises testing** — testing
> begins only under a signed engagement + the written authorisation in §7.

**Entity:** Lumi Education Pty Ltd (t/a Lumi Reading), ABN 45 700 349 015
**Contact:** Nicholas Plevritis, Director — support@lumi-reading.com — [PHONE]

---

## 1. What Lumi is (context for the tester)

Lumi is a reading-diary service for primary (K-6) schools. It handles
children's personal information (names, class/school, reading activity,
optional short voice recordings, optional messages between teachers and
parents). Three client surfaces sit on a shared Google Cloud / Firebase
backend, all in `australia-southeast1`:

- **Parent & teacher mobile app** (Flutter, iOS + Android) — talks to
  Firebase directly (Auth, Firestore, Storage) under Security Rules, plus
  callable Cloud Functions.
- **School portal** (Next.js) — school-admin web app; server-rendered on
  Firebase App Hosting with its own runtime service account.
- **Super-admin portal** (Next.js) — internal Lumi operations; separate
  runtime service account and a session secret.
- **Marketing site** (static) — public brochure + legal pages + lead forms.

Authorisation is enforced by Firestore/Storage Security Rules (tenant /
class / family binding) and server-owned role fields, not by client trust.
There is no traditional REST API server; the "API" is Firebase SDK access
governed by rules, plus onCall/onRequest Cloud Functions.

## 2. In-scope targets

### 2.1 Web applications
| Target | URL (prod) | Notes |
|---|---|---|
| School portal | `https://lumi-school-admin-au.web.app` | Auth'd school-admin app; login, roster, reading data, messaging, comprehension surfaces, CSV export, legal pages |
| Super-admin portal | (internal; URL provided on engagement — dev host `lumi-dev-admin-au.web.app`) | Privileged ops: entitlements, kill switches, impersonation, audit; session-secret auth |
| Marketing site | `https://lumi-reading.com` | Static + demo-request / contact-sales lead forms |

A **staging/test project** and seeded non-production accounts for each role
(parent, teacher, school-admin, super-admin) will be provided so testing
never touches real child data (§4).

### 2.2 Firebase backend (the core of the engagement)
- **Firestore Security Rules** (`firestore.rules`) — the primary
  authorization boundary. Test for cross-school / cross-class / cross-family
  access, role/ownership forgery, server-owned field tampering, and
  list-query scoping (a query filtered only by studentId must be denied
  where classId is required). A rules unit-test matrix already exists;
  independent adversarial validation is the ask.
- **Storage Security Rules** (`storage.rules`) — audio upload path
  (create-only pending namespace), signed-URL access, cross-tenant object
  access.
- **Cloud Functions** (~60, `functions/src`): onCall callables (auth/roles,
  input validation, injection, IDOR, privilege escalation), onRequest HTTP
  endpoints, and the audio upload-confirmation flow. High-value targets:
  authentication/MFA/SMS-verification flows, parent-child linking & school
  code redemption, impersonation, subscription/entitlement writes,
  notification campaigns, deletion cascade.
- **Firebase Authentication / App Check** — auth flows, MFA enrolment, SMS
  verification rate limits, App Check enforcement posture.

### 2.3 AI comprehension pipeline (built, dark/dev-gated — test as-is)
- The enqueue gate in the audio-confirmation flow and the worker/sweep
  functions (`functions/src/ai_evaluation/`). Test: gate bypass (platform
  kill switch + per-school entitlement both fail-closed), whether a client
  can create/alter job or evaluation documents (should be deny-all), whether
  transcript/identifier data can leak into client-readable docs or logs, and
  **prompt-injection resistance** of the evaluation prompt (a live
  adversarial regression harness exists — `functions/scripts/`; the tester
  is invited to attack the real prompt). The feature will be OFF; the
  tester should assess the code paths and gates as they exist, not report
  "feature unreachable".

### 2.4 Mobile apps
- Flutter iOS + Android builds (provided). Assess: local data storage,
  secrets/keys in the binary, certificate/transport security, deep-link /
  app-association handling, and client-side trust assumptions that the
  server must not rely on. Full mobile pentest vs. lighter review is a
  quote option (§6).

## 3. Out of scope
- Google/Firebase's own infrastructure (test Lumi's configuration and
  rules, not Google's platform). No load/DoS testing against production.
- Third-party services themselves (SendGrid, Google Books/Open Library);
  only Lumi's use of them.
- Social-engineering of Lumi staff or real schools; physical security.
- Any action against real child data or production tenants (§4).

## 4. Test data and environment (no real child data)
- Testing runs against a **dedicated staging Firebase project** (or isolated
  test tenants) seeded with synthetic students, classes, schools and
  accounts for every role. Any voice clips used are synthetic.
- If a finding can only be confirmed in production, it is confirmed
  read-only, by agreement, with no access to real personal information —
  the rules-of-engagement must state this explicitly.
- Lumi provides: role-scoped test credentials, a staging URL set, the
  Flutter app builds, and read access to `firestore.rules` /
  `storage.rules` for a grey-box test (recommended — rules are the security
  model, so testing them blind wastes budget).

## 5. Approach and standards
- **Grey-box preferred:** provide the tester the rules files, function
  signatures and this pack; keep exploitation realistic. This gives ST4S-
  grade coverage of the authorization model for less budget than black-box.
- Methodology aligned to **OWASP ASVS / Web Security Testing Guide** and
  **OWASP MASVS** for mobile; ST4S references the Australian ISM and OWASP.
- Cloud/Firebase-specific review of IAM, service-account scoping, rules, and
  callable-function authorization (not just generic web scanning).
- **Deliverable:** a written report with an executive summary, per-finding
  risk ratings, evidence/reproduction and remediation advice, **plus a
  redacted/shareable version suitable for sharing with ST4S and schools**,
  and a **re-test** of remediated findings. Please confirm tester
  certifications (e.g. CREST / OSCP) — ST4S may verify these.

## 6. Quote options (please price separately)
1. Backend + web core: Firestore/Storage rules, Cloud Functions, auth/MFA
   flows, both portals, marketing lead forms. **(Required.)**
2. AI pipeline module: gate-bypass + deny-all doc access + prompt-injection
   of the evaluation prompt. **(Required — needed for ST4S AI evidence.)**
3. Mobile apps: full MASVS pentest of iOS + Android. (Option — vs. a lighter
   client-side review.)
4. Re-test of remediated findings. **(Required.)**

## 7. Authorisation & rules of engagement (finalised in the SOW)
Testing is authorised only under a signed statement of work that records:
scope (the targets above), the staging environment, the no-real-child-data
constraint, the testing window and hours, emergency contact + stop
procedure, data-handling/retention/destruction for any Lumi data the tester
touches, and confidentiality. The Director (Nicholas Plevritis) signs as the
authorising owner; Lumi Education Pty Ltd is the authorising entity.

## 8. Attachments to provide on engagement (not committed here)
Staging URLs + seeded credentials · Flutter app builds (or store TestFlight/
internal-track access) · `firestore.rules`, `storage.rules`, function
signature list · this pack · the architecture summary
(`docs/ARCHITECTURE.md`) and AU resource-location audit
(`docs/security/AU_RESOURCE_LOCATION_AUDIT_2026-07-17.md`).

## 9. Status / next steps
- [ ] Send the RFQ (`PENETRATION_TEST_RFQ_EMAIL.md`) to 2–3 CREST-accredited
      AU firms; collect quotes against §6.
- [ ] Stand up the staging project + seed role accounts and a synthetic
      audio clip set.
- [ ] Select firm; sign SOW with §7 rules of engagement.
- [ ] Schedule (allow lead time for booking + report; target a report in
      hand before the ST4S full-assessment nomination comes up).
- [ ] On report: remediate, re-test, file the redacted report in the ST4S
      evidence pack (EV10/EV11) and reference it in the readiness prep doc.
