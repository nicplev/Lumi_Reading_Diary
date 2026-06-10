// Plain CommonJS config — NOT next.config.ts. firebase-tools' web frameworks
// build adapter loads a .ts config without unwrapping the TS→CJS module
// interop, so Next.js receives `{__esModule, default}` and silently ignores
// every key ("Unrecognized key(s)" warning). CJS `module.exports` is returned
// by require() verbatim, so the config actually applies in the deployed build.

// eslint-disable-next-line @typescript-eslint/no-require-imports -- file must stay CJS (see above)
const path = require("path");

/** @type {import('next').NextConfig} */
const nextConfig = {
  transpilePackages: ["@lumi/types", "@lumi/server-ops"],
  // firebase-admin is reached through the transpiled @lumi/server-ops
  // package. Without this, Turbopack hash-aliases it (firebase-admin-<hash>)
  // and the deployed Cloud Run bundle can't resolve that name at runtime
  // (ERR_MODULE_NOT_FOUND). Marking it a server-external keeps it a plain
  // runtime require() from node_modules — never bundled, never aliased.
  serverExternalPackages: ["firebase-admin"],
  // Pin Turbopack to the monorepo root. Without this, Next walks upward and
  // can pick up an unrelated lockfile in /Users/nicplev/ as the workspace
  // root, breaking @lumi/* package resolution.
  turbopack: {
    root: path.resolve(__dirname, ".."),
  },
};

module.exports = nextConfig;
