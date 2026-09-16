import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

import { ApiError, apiFetch } from "../lib/api-client";

function okResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

describe("apiFetch (ADR-0011 §2: server-side calls with a bearer token)", () => {
  it("calls API_BASE_URL + path with Authorization: Bearer and no cookies", async () => {
    const fetchImpl = vi.fn(async () => okResponse({ message: "hi" }));
    const out = await apiFetch<{ message: string }>("/v1/hello", "tok-123", {
      baseUrl: "http://10.10.0.2:8000",
      fetchImpl,
    });
    expect(out).toEqual({ message: "hi" });
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("http://10.10.0.2:8000/v1/hello");
    const headers = new Headers(init.headers);
    expect(headers.get("authorization")).toBe("Bearer tok-123");
    expect(headers.get("accept")).toBe("application/json");
    expect(headers.has("cookie")).toBe(false);
    expect(init.credentials).toBe("omit");
    expect(init.cache).toBe("no-store");
    expect(init.signal).toBeInstanceOf(AbortSignal);
  });

  it("throws ApiError with the status but without the upstream body", async () => {
    const fetchImpl = vi.fn(async () => okResponse({ detail: "secret internals" }, 503));
    await expect(apiFetch("/v1/hello", "t", { baseUrl: "http://api", fetchImpl })).rejects.toMatchObject({
      name: "ApiError",
      status: 503,
    });
    await expect(apiFetch("/v1/hello", "t", { baseUrl: "http://api", fetchImpl })).rejects.not.toThrow(/secret internals/);
  });

  it("rejects paths that do not start with a slash and empty tokens", async () => {
    const fetchImpl = vi.fn();
    await expect(apiFetch("v1/hello", "t", { baseUrl: "http://api", fetchImpl })).rejects.toThrow(/path/);
    await expect(apiFetch("/v1/hello", "", { baseUrl: "http://api", fetchImpl })).rejects.toThrow(/token/);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("ApiError is an Error", () => {
    const e = new ApiError(404);
    expect(e).toBeInstanceOf(Error);
    expect(e.message).toBe("API request failed with status 404");
  });
});
