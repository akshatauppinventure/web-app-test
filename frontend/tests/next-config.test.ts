import { describe, expect, it } from "vitest";

import nextConfig from "../next.config";

describe("next.config.ts hardening (ADR-0007)", () => {
  it("produces a standalone build for the container", () => {
    expect(nextConfig.output).toBe("standalone");
  });
  it("does not advertise the framework", () => {
    expect(nextConfig.poweredByHeader).toBe(false);
  });
  it("locks down the image optimizer", () => {
    expect(nextConfig.images?.remotePatterns).toEqual([]);
    expect(nextConfig.images?.dangerouslyAllowSVG).toBe(false);
    expect(nextConfig.images?.formats).toEqual(["image/webp"]);
  });
});
