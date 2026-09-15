import { describe, expect, it } from "vitest";

import { GET } from "../app/api/healthz/route";

describe("GET /api/healthz", () => {
  it("answers 200 with a JSON status and no caching", async () => {
    const res = await GET();
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: "ok" });
    expect(res.headers.get("cache-control")).toBe("no-store");
  });
});
