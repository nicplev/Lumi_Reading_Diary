import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: ["@lumi/types", "@lumi/server-ops"],
};

export default nextConfig;
