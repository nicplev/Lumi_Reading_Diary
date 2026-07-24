# Lumi Reading — ST4S Evidence Pack (printable PDFs)

Print-ready, A4, Lumi-branded PDF renderings of the ST4S evidence documents.
Compiled **24 July 2026** for **Lumi Education Pty Ltd** (ABN 45 700 349 015).

## Contents

- **`Lumi_Security_Evidence_Pack.pdf`** — the master bundle: cover + contents +
  all documents in one file (for a single handoff).
- **`NN_*.pdf`** — one file per document (upload against the matching ST4S
  control). The number prefix matches the master's contents order.

Documents are grouped as: Governance & Policy · Secure Operations · People &
Access · Privacy & Data · Assessment Evidence.

## Status labels are honest

Each document's cover badge and the master contents page show the real state at
compilation — `DRAFT`, `Pending signature`, `Completed … · signature pending`,
`First review … · signature pending`, `Template — to populate`, or `Final`.
Nothing is presented as more finished than it is. Re-render after signing to
refresh the badges.

## Provenance / how to regenerate

- **Source of truth:** the Markdown files in this directory's parent
  (`docs/security/evidence/*.md`) plus the two assessment reports
  (`docs/security/VULNERABILITY_ASSESSMENT_REPORT_*.md`,
  security-assessment `TLS_CRYPTO_PROFILE_*.md`). The PDFs are a rendering — the
  Markdown remains authoritative.
- **Renderer:** headless Chrome (DevTools `printToPDF`, A4, backgrounds on,
  branded footer with page numbers). Brand: cream `#F7F5F0` / ink `#1A1A1A`,
  section accents (Class-red, Insights-blue, Library-yellow, Settings-green),
  Nunito, Lumi flame mascot — the same design system as the app and portals.
- Fonts (Nunito, OFL) and the logo are embedded, so each PDF is self-contained.
