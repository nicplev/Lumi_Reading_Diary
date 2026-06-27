import type { Metadata } from 'next';
import { Nunito } from 'next/font/google';
import './globals.css';
import { Providers } from './providers';
import { getSession } from '@/lib/auth/session';

const nunito = Nunito({
  subsets: ['latin'],
  variable: '--font-family-nunito',
  display: 'optional',
});

export const metadata: Metadata = {
  title: 'Lumi School Admin',
  description: 'School administration portal for Lumi Reading Tracker',
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  // Seed the client auth context with the server session so the profile chip and
  // role-gated nav render correctly on first paint (no "Loading…" flash/stall).
  const session = await getSession();
  const initialUser = session
    ? {
        uid: session.uid,
        email: session.email,
        schoolId: session.schoolId,
        role: session.role,
        fullName: session.fullName,
      }
    : null;

  return (
    <html lang="en" className={nunito.variable} suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        {/* display=block: render glyphs invisibly until the icon font loads, so the
            raw ligature text (e.g. "library_books") never flashes on cold starts. */}
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=block"
        />
        <script
          dangerouslySetInnerHTML={{
            __html: `(function(){var d=document.documentElement;function r(){d.classList.add('fonts-ready')}if(document.fonts&&document.fonts.ready){document.fonts.ready.then(r);setTimeout(r,3000)}else{r()}})();`,
          }}
        />
      </head>
      <body className="font-[family-name:var(--font-family-nunito)] antialiased" suppressHydrationWarning>
        <Providers initialUser={initialUser}>{children}</Providers>
      </body>
    </html>
  );
}
