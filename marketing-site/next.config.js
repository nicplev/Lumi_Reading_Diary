/** @type {import('next').NextConfig} */
const nextConfig = {
  // Static export: the site is nearly all static content, and the two forms
  // call Cloud Functions callables directly from the client SDK, so there's
  // no need for a Next server (no SSR, no API routes, no Cloud Run instance).
  output: 'export',
  images: {
    // next/image's optimization API needs a server, which a static export
    // doesn't have — assets are already right-sized PNGs anyway.
    unoptimized: true,
  },
};

module.exports = nextConfig;
