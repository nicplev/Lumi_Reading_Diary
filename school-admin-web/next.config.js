// Plain CommonJS config — NOT next.config.ts. firebase-tools' web frameworks
// build adapter loads a .ts config without unwrapping the TS→CJS module
// interop, so Next.js receives `{__esModule, default}` and silently ignores
// every key ("Unrecognized key(s)" warning). CJS `module.exports` is returned
// by require() verbatim, so the config actually applies in the deployed build.

/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'books.google.com' },
      { protocol: 'https', hostname: 'covers.openlibrary.org' },
      { protocol: 'https', hostname: 'firebasestorage.googleapis.com' },
      { protocol: 'https', hostname: 'lumi-ninc-au.firebasestorage.app' },
    ],
  },
  // Inline SESSION_SECRET into the Edge Runtime middleware bundle. Without
  // this, middleware can't read process.env at runtime (only Node.js routes
  // can) and JWT verification fails — every authed request bounces to /login.
  env: {
    SESSION_SECRET: process.env.SESSION_SECRET,
  },
  // firebase-admin must stay a runtime require() from node_modules; the
  // Cloud Run SSR bundle can't resolve a bundled/hash-aliased copy
  // (ERR_MODULE_NOT_FOUND). Mirrors the admin/ portal's config.
  serverExternalPackages: ['firebase-admin'],
};

module.exports = nextConfig;
