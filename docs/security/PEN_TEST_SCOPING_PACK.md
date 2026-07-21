# Penetration Test — Scoping Pack (for RFQ and engagement)

> **Working document — prepared 20 July 2026 for Nic.** Use: send the annex
> RFQ email to 2–3 CREST-accredited firms; share §2–§7 of this pack after an
> NDA is in place. The redacted report this engagement produces is ST4S
> evidence item EV10 (see `docs/privacy/ST4S_READINESS_PREP.md` §4).

**Entity:** Lumi Education Pty Ltd (trading as Lumi Reading), ABN 45 700 349 015
**Engagement sponsor / authorising officer:** Nicholas Plevritis, Director
**Emergency contact during testing:** Nic — [PHONE NUMBER] · support@lumi-reading.com

---

## 1. Why we are testing

Lumi is a children's reading-diary service for Australian primary schools.
We are preparing for the national ST4S security/privacy assessment (Tier 1)
and want an independent penetration test whose redacted report can be
submitted as ST4S evidence. Beyond compliance, our crown-jewel property is
**tenant isolation**: a parent must never reach another family's child, a
teacher must never reach another class or school. That is what we most want
attacked.

## 2. System overview (for scoping)

- **Backend:** Google Cloud / Firebase, project `lumi-ninc-au`, all
  workloads in `australia-southeast1`. Firestore + Cloud Storage with
  security rules; ~77 Cloud Functions/Cloud Run workloads (callable, HTTP,
  scheduled, and event triggers) on dedicated least-privilege service
  accounts; **no API keys/secrets in the AI path — IAM/ADC only**.
- **Mobile apps:** Flutter iOS/Android (parent + teacher roles). Firebase
  Auth (phone/SMS OTP for parents, email for staff), Firebase App Check
  integrated (enforcement staged), FCM push.
- **School portal:** `lumi-school-admin-au.web.app` — Next.js SSR on
  Firebase Hosting/Cloud Run, dedicated runtime service account.
- **Super-admin portal:** `lumi-dev-admin-au.web.app` — Next.js SSR,
  session-cookie auth (Secret Manager session secret), dedicated runtime
  service account; includes an audited read-only impersonation feature.
- **Marketing site:** `lumi-reading.com` (static hosting; demo-request and
  contact-sales lead forms backed by callables).
- **AI comprehension pipeline (built, DARK in production):** audio →
  Speech-to-Text (Sydney) → Gemini on Vertex AI (Sydney) → teacher-only
  evaluation docs. Fail-closed platform kill switch + per-school
  entitlement; currently no school entitled and switch OFF.
- Full architecture, rules test matrices, and audit docs available under
  NDA (`ARCHITECTURE.md`, security audits of 2026-07-15/17, privacy corpus).

## 3. Requested scope

**In scope (grey-box preferred — we will provide source access, test
accounts and rules files to maximise value):**

1. **Authorisation / tenant isolation** (highest priority): cross-family,
   cross-class, cross-school access attempts against Firestore/Storage
   rules and every callable/HTTP function; IDOR hunting on all ID-bearing
   surfaces; privilege escalation parent→teacher→schoolAdmin→super-admin.
2. **School portal + super-admin portal web app testing** (OWASP-style):
   session handling, CSRF, SSRF, injection, access control on API routes,
   the impersonation feature's containment.
3. **Auth flows:** phone-OTP signup/signin (rate limits, enumeration,
   SIM-swap-adjacent flows), staff email auth, school-code join flows,
   parent-child linking codes, App Check bypass attempts.
4. **Cloud configuration review:** IAM bindings, service-account scoping,
   Storage bucket ACLs, exposed endpoints, secret handling.
5. **AI pipeline (code-assisted):** prompt-injection and gate-bypass review
   of the dark pipeline — enqueue gates, transcript-as-data prompt
   construction, schema re-validation, kill-switch fail-closed behaviour.
   Runtime LLM testing can run against a synthetic test school in a
   controlled window (see §5) or via our existing live regression harness.
6. **Mobile app backend interaction** (traffic-level: certificate pinning
   expectations, token handling, endpoint abuse from a hostile client).
   Binary reverse-engineering of the apps is optional/nice-to-have.

**Out of scope:** denial-of-service and volumetric testing; social
engineering/phishing; physical; Google-operated infrastructure itself
(Google Cloud permits customer pen-testing of customer workloads without
prior approval, subject to its Acceptable Use Policy — the firm must stay
within it); any interaction with non-test school/family data (§5).

## 4. Deliverables required

1. Full technical report (findings, evidence, severity, remediation).
2. **A redacted, third-party-shareable report suitable for ST4S submission
   (evidence item EV10)** — ag