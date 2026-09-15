import { describe, expect, it } from "vitest";
import { createRequire } from "node:module";

import { NEXT_VERSION_FLOOR, satisfiesFloor } from "../scripts/check-next-version.mts";

const require = createRequire(import.meta.url);

describe("Next.js version floor (ADR-0007)", () => {
  it("floor is 16.3.3 (first release with the 2026 security fixes)", () => {
    expect(NEXT_VERSION_FLOOR).toBe("16.3.3");
  });

  it.each([
    ["16.3.3", true],
    ["16.3.5", true],
    ["16.4.0", true],
    ["17.0.0", true],
    ["16.3.2", false],
    ["16.2.9", false],
    ["15.9.9", false],
    ["16.3.3-canary.1", false],
    ["garbage", false],
  ])("satisfiesFloor(%s) -> %s", (version, expected) => {
    expect(satisfiesFloor(version, NEXT_VERSION_FLOOR)).toBe(expected);
  });

  it("the installed next package satisfies the floor", () => {
    const { version } = require("next/package.json") as { version: string };
    expect(satisfiesFloor(version, NEXT_VERSION_FLOOR)).toBe(true);
  });
});
