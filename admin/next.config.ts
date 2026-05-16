import path from "path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: ["@lumi/types", "@lumi/server-ops"],
  // Pin Turbopack to the monorepo root. Without this, Next walks upward and
  // can pick up an unrelated lockfile in /Users/nicplev/ as the workspace
  // root, breaking @lumi/* package resolution.
  turbopack: {
    root: path.resolve(__dirname, ".."),
  },
};

export default nextConfig;
