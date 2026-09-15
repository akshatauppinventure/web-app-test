import type { NextConfig } from "next";

// ADR-0007: standalone output for the container, no framework fingerprinting, images locked down.
const nextConfig: NextConfig = {
  output: "standalone",
  poweredByHeader: false,
  reactStrictMode: true,
  images: {
    remotePatterns: [],
    formats: ["image/webp"],
    dangerouslyAllowSVG: false,
  },
};

export default nextConfig;
