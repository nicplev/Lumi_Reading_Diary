import type { Metadata } from 'next';
import { Nunito } from 'next/font/google';
import './globals.css';
import { Providers } from './providers';

const nunito = Nunito({
  subsets: ['latin'],
  variable: '--font-family-nunito',
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'Lumi School Admin',
  description: 'School administration portal for Lumi Reading Tracker',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={nunito.variable} suppressHydrationWarning>
      <head>
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap"
        />
      </head>
      <body className="font-[family-name:var(--font-family-nunito)] antialiased" suppressHydrationWarning>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
