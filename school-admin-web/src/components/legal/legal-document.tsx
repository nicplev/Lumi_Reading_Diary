import Link from 'next/link';

const SUPPORT_EMAIL = 'support@lumi-reading.com';

/**
 * Shared chrome for the public legal/support pages (privacy, terms, support).
 * These render under the root layout only (no authenticated sidebar) and are
 * reachable without a session — see the `/legal` + `/support` entries in
 * `src/middleware.ts`. Styling uses the New Lumi design tokens from
 * globals.css (cream/ink/paper) and a calm green accent for legal surfaces.
 *
 * Body content is passed as plain semantic HTML (h2/p/ul/a/strong); the
 * wrapper styles all descendants via arbitrary variants so each page stays
 * readable prose without repeating utility classes on every element.
 */
export function LegalDocument({
  title,
  lastUpdated,
  children,
}: {
  title: string;
  lastUpdated: string;
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen bg-cream text-ink">
      <header className="border-b border-rule bg-paper/70">
        <div className="mx-auto flex max-w-3xl items-center gap-3 px-5 py-4">
          <span className="inline-flex h-9 w-9 items-center justify-center rounded-[var(--radius-md)] bg-lumi-red/10 text-lumi-red">
            <BookMark />
          </span>
          <span className="font-display text-lg font-extrabold tracking-tight">Lumi</span>
        </div>
      </header>

      <main className="mx-auto max-w-3xl px-5 py-10">
        <h1 className="font-display text-[30px] font-extrabold leading-tight tracking-tight">
          {title}
        </h1>
        <p className="mt-2 text-sm text-muted">Last updated {lastUpdated}</p>

        <article
          className="mt-8 space-y-8 text-[15px] leading-relaxed text-ink/80
            [&_h2]:mt-2 [&_h2]:font-display [&_h2]:text-xl [&_h2]:font-extrabold [&_h2]:text-ink
            [&_h3]:mt-1 [&_h3]:font-display [&_h3]:text-base [&_h3]:font-bold [&_h3]:text-ink
            [&_p]:mt-3
            [&_ul]:mt-3 [&_ul]:list-disc [&_ul]:space-y-1.5 [&_ul]:pl-5
            [&_ol]:mt-3 [&_ol]:list-decimal [&_ol]:space-y-1.5 [&_ol]:pl-5
            [&_a]:font-semibold [&_a]:text-lumi-green [&_a]:underline hover:[&_a]:text-lumi-green-dark
            [&_strong]:font-semibold [&_strong]:text-ink"
        >
          {children}
        </article>
      </main>

      <footer className="border-t border-rule">
        <div className="mx-auto max-w-3xl px-5 py-8 text-sm text-muted">
          <div className="flex flex-wrap gap-x-6 gap-y-2">
            <Link href="/legal/privacy" className="font-semibold text-ink hover:text-lumi-green-dark">
              Privacy Policy
            </Link>
            <Link href="/legal/terms" className="font-semibold text-ink hover:text-lumi-green-dark">
              Terms of Use
            </Link>
            <Link href="/support" className="font-semibold text-ink hover:text-lumi-green-dark">
              Support
            </Link>
          </div>
          <p className="mt-4">
            Questions? Email{' '}
            <a href={`mailto:${SUPPORT_EMAIL}`} className="font-semibold text-lumi-green hover:text-lumi-green-dark">
              {SUPPORT_EMAIL}
            </a>
            .
          </p>
          <p className="mt-2">© {new Date().getFullYear()} Lumi. All rights reserved.</p>
        </div>
      </footer>
    </div>
  );
}

function BookMark() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M4 4.5A1.5 1.5 0 0 1 5.5 3H11v16H5.5A1.5 1.5 0 0 0 4 20.5V4.5Z"
        fill="currentColor"
        opacity="0.55"
      />
      <path
        d="M20 4.5A1.5 1.5 0 0 0 18.5 3H13v16h5.5A1.5 1.5 0 0 1 20 20.5V4.5Z"
        fill="currentColor"
      />
    </svg>
  );
}
