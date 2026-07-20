# Penetration Test — Request for Quote (email draft)

> Draft for Nic to send to 2–3 CREST-accredited Australian penetration-testing
> firms. Replace the phone placeholder before sending. Full technical scope:
> `docs/security/PENETRATION_TEST_SCOPING_PACK.md` (attach or share on reply).

---

> **Subject: Request for quote — penetration test of a children's edtech app (Lumi)**
>
> Hi [FIRM],
>
> I'm the director of Lumi Education Pty Ltd (trading as Lumi Reading), a
> small Australian edtech company. Lumi is a reading-diary app for primary
> schools, hosted entirely on Google Cloud / Firebase in the Sydney region.
> We're preparing for a Safer Technologies 4 Schools (ST4S) assessment and
> need an independent penetration test whose report we can submit as
> evidence, so a redacted/shareable version of the report and confirmation
> of your testers' certifications (e.g. CREST/OSCP) are important to us.
>
> At a high level, the scope is:
>
> 1. Our Firebase backend — Firestore and Storage Security Rules (our main
>    authorization boundary, enforcing school/class/family isolation), and
>    around 60 Cloud Functions (authentication and MFA flows, parent-child
>    linking, subscription/entitlement controls, an admin impersonation
>    feature, and a deletion cascade).
> 2. Two Next.js web portals (a school-admin portal and an internal
>    super-admin portal) and a static marketing site with lead forms.
> 3. An AI comprehension feature (built but not yet enabled): student voice →
>    Google Speech-to-Text → an LLM evaluation → a teacher-only summary. We'd
>    like the access gates and prompt-injection resistance tested.
> 4. Optionally, our Flutter iOS and Android apps.
>
> Testing would run against a dedicated staging environment seeded with
> synthetic data — no real children's data is ever in scope. We can provide
> role-scoped test accounts and our Security Rules files for a grey-box test.
>
> Could you please provide:
>
> - an indicative quote, ideally itemised for (a) backend + web core,
>   (b) the AI feature, (c) mobile apps, and (d) a re-test of remediated
>   findings;
> - your methodology and the standards you test against (we're aligning to
>   OWASP ASVS/MASVS and the Australian ISM, which ST4S references);
> - typical lead time to schedule and to deliver the report; and
> - the certifications your testers hold.
>
> I'm happy to share a detailed scoping document and answer any questions on
> a quick call. Thank you for your time.
>
> Kind regards,
> Nicholas Plevritis
> Director, Lumi Education Pty Ltd (trading as Lumi Reading)
> ABN 45 700 349 015
> support@lumi-reading.com
> [PHONE NUMBER]
