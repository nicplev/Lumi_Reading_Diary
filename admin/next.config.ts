import path from "path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
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

export default nextConfig;
