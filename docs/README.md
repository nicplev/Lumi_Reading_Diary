# Lumi — Docs

Internal documentation for the Lumi reading tracker. Source code lives at the repo root; this folder is for written artifacts (research, runbooks, migration notes).

## Index

- **[go-to-market.md](go-to-market.md)** — Landing page, pricing, and onboarding strategy. Covers the retail (public, self-serve) vs wholesale (KAKA-connected, sales-assisted) channels, school + family (B2C) segments, per-student/year pricing, what to advertise publicly, a section-by-section landing-page content spec, the three onboarding flows, and a phased implementation roadmap. Strategy/content only — no code.

- **[demo-playbook.md](demo-playbook.md)** — Sales demo playbook: the 18-minute golden-path demo (parent → teacher → leader → close), video-call and in-person rig checklists, live-moment choreography with fallbacks, objection handling, guardrails, and the scale path for training future demo runners. Built around the demo tenant created by [`scripts/seed_demo_school.js`](../scripts/seed_demo_school.js).

- **[parent-ux-research.md](parent-ux-research.md)** — Research synthesis, baseline review of the parent-logging flow, and the phased implementation roadmap (Recs 1–10). Most of Phases 0–3 are now built on the mobile app; see the roadmap for what each recommendation covers and the cross-cutting risks.

- **[impersonation-runbook.md](impersonation-runbook.md)** — Operations runbook for the super-admin read-only impersonation flow (mobile + web portal). Covers MFA gates, audit trail, and incident response.

- **[MONOREPO_MIGRATION.md](MONOREPO_MIGRATION.md)** — Step-by-step migration log for folding the standalone `lumi-admin` repo into this monorepo as `./admin/`, including the shared `@lumi/*` packages and CI/CD changes.

- **[MONOREPO_OVERLAP.md](MONOREPO_OVERLAP.md)** — Inventory of code/config overlap between the Flutter mobile app, the Next.js admin/web portal, and the Cloud Functions backend, with notes on what was deduplicated.

## Conventions

- Use Markdown with relative links (so the files render the same in GitHub and in editors).
- Keep each doc focused on one concern; if a doc grows beyond ~500 lines, split it and update this index.
