import { describe, expect, it } from "vitest";

describe("server-only guard (ADR-0007 §4)", () => {
  it("importing a server-only module outside a React Server environment throws", async () => {
    // lib/api-client.ts and lib/session.ts start with `import "server-only"`; this proves the
    // guard is active in a plain (client-like) module environment.
    await expect(import("server-only")).rejects.toThrow();
  });
});
