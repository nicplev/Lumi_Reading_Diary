import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Lumi — The home reading diary for Australian primary schools",
  description:
    "Lumi replaces the paper reading diary with a tap-only nightly log for parents and a live class dashboard for teachers.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Nunito:wght@500;600;700;800;900&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="font-body text-ink">{children}</body>
    </html>
  );
}
