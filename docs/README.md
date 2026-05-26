# Lumi — Docs

Internal documentation for the Lumi reading tracker. Source code lives at the repo root; this folder is for written artifacts (research, runbooks, migration notes).

## Index

- **[parent-ux-research.md](parent-ux-research.md)** — Research synthesis, baseline review of the parent-logging flow, and the phased implementation roadmap (Recs 1–10). Most of Phases 0–3 are now built on the mobile app; see the roadmap for what each recommendation covers and the cross-cutting risks.

- **[impersonation-runbook.md](impersonation-runbook.md)** — Operations runbook for the super-admin read-only impersonation flow (mobile + web portal). Covers MFA gates, audit trail, and incident response.

- **[MONOREPO_MIGRATION.md](MONOREPO_MIGRATION.md)** — Step-by-step migration log for folding the standalone `lumi-admin` repo into this monorepo as `./admin/`, including the shared `@lumi/*` packages and CI/CD changes.

- **[MONOREPO_OVERLAP.md](MONOREPO_OVERLAP.md)** — Inventory of code/config overlap between the Flutter mobile app, the Next.js admin/web portal, and the Cloud Functions backend, with notes on what was deduplicated.

## Conventions

- Use Markdown with relative links (so the files render the same in GitHub and in editors).
- Keep each doc focused on one concern; if a doc grows beyond ~500 lines, split it and update this index.
