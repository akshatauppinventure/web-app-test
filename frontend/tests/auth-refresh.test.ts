import type { Account } from "next-auth";
import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  REFRESH_THRESHOLD_SECONDS,
  _resetRefreshMemoForTests,
  jwtCallback,
  needsRefresh,
  type RefreshDeps,
} from "../lib/token-refresh";

const NOW = 1_800_000_000;

type FetchMock = ReturnType<typeof vi.fn<typeof fetch>>;

function deps(overrides: Partial<RefreshDeps> = {}): RefreshDeps & { fetchImpl: FetchMock } {
  const fetchImpl: FetchMock = vi.fn<typeof fetch>(async () =>
    new Response(
      JSON.stringify({
        access_token: "new-access",
        refresh_token: "new-refresh",
        id_token: "new-id",
        expires_in: 300,
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    ),
  );
  return {
    tokenEndpoint: "http://keycloak:8080/auth/realms/app/protocol/openid-connect/token",
    clientId: "web-bff",
    clientSecret: "bff-secret",
    now: () => NOW,
    fetchImpl,
    ...overrides,
  } as RefreshDeps & { fetchImpl: FetchMock };
}

const freshToken = { sub: "u1", accessToken: "a", refreshToken: "r", idToken: "i", expiresAt: NOW + 240 };
const expiringToken = { ...freshToken, expiresAt: NOW + 30 };

beforeEach(() => _resetRefreshMemoForTests());

describe("needsRefresh (ADR-0011 §1: refresh within 60 s of expiry)", () => {
  it("has a 60 second threshold", () => expect(REFRESH_THRESHOLD_SECONDS).toBe(60));
  it.each([
    [NOW + 61, false],
    [NOW + 60, true],
    [NOW + 1, true],
    [NOW - 10, true],
    [undefined, true],
  ])("expiresAt=%s -> %s", (expiresAt, expected) => {
    expect(needsRefresh(expiresAt, NOW)).toBe(expected);
  });
});

describe("jwtCallback", () => {
  it("stores the tokens from the account on initial sign-in", async () => {
    const d = deps();
    const account: Account = {
      provider: "keycloak",
      type: "oidc",
      providerAccountId: "u1",
      access_token: "acc",
      refresh_token: "ref",
      id_token: "idt",
      expires_at: NOW + 300,
    };
    const out = await jwtCallback({ token: { sub: "u1" }, account }, d);
    expect(out).toMatchObject({ accessToken: "acc", refreshToken: "ref", idToken: "idt", expiresAt: NOW + 300 });
    expect(out.error).toBeUndefined();
    expect(d.fetchImpl).not.toHaveBeenCalled();
  });

  it("leaves a fresh token untouched and does not call Keycloak", async () => {
    const d = deps();
    const out = await jwtCallback({ token: freshToken, account: null }, d);
    expect(out).toEqual(freshToken);
    expect(d.fetchImpl).not.toHaveBeenCalled();
  });

  it("refreshes an expiring token with a client-authenticated refresh_token grant", async () => {
    const d = deps();
    const out = await jwtCallback({ token: expiringToken, account: null }, d);
    expect(out).toMatchObject({ accessToken: "new-access", refreshToken: "new-refresh", idToken: "new-id", expiresAt: NOW + 300 });
    expect(out.error).toBeUndefined();
    expect(d.fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = d.fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe(d.tokenEndpoint);
    expect(init.method).toBe("POST");
    const body = new URLSearchParams(init.body as string);
    expect(body.get("grant_type")).toBe("refresh_token");
    expect(body.get("refresh_token")).toBe("r");
    expect(body.get("client_id")).toBe("web-bff");
    expect(body.get("client_secret")).toBe("bff-secret");
    expect(init.cache).toBe("no-store");
  });

  it("invalidates the session when Keycloak rejects the refresh", async () => {
    const d = deps({
      fetchImpl: vi.fn<typeof fetch>(async () => new Response('{"error":"invalid_grant"}', { status: 400 })),
    });
    const out = await jwtCallback({ token: expiringToken, account: null }, d);
    expect(out.error).toBe("RefreshTokenError");
    expect(out.accessToken).toBeUndefined();
    expect(out.refreshToken).toBeUndefined();
    expect(out.idToken).toBeUndefined();
  });

  it("invalidates the session on a network failure", async () => {
    const d = deps({ fetchImpl: vi.fn<typeof fetch>(async () => { throw new Error("ECONNREFUSED"); }) });
    const out = await jwtCallback({ token: expiringToken, account: null }, d);
    expect(out.error).toBe("RefreshTokenError");
  });

  it("invalidates the session when no refresh token is present", async () => {
    const d = deps();
    const out = await jwtCallback({ token: { ...expiringToken, refreshToken: undefined }, account: null }, d);
    expect(out.error).toBe("RefreshTokenError");
    expect(d.fetchImpl).not.toHaveBeenCalled();
  });

  it("memoizes a refresh so a concurrent/second call with the same (now revoked) refresh token reuses it", async () => {
    // Keycloak rotates refresh tokens with max reuse 0; proxy + server component both run the
    // callback for one request, so the second must not present the consumed refresh token again.
    const d = deps();
    const [a, b] = await Promise.all([
      jwtCallback({ token: expiringToken, account: null }, d),
      jwtCallback({ token: expiringToken, account: null }, d),
    ]);
    const c = await jwtCallback({ token: expiringToken, account: null }, d);
    expect(d.fetchImpl).toHaveBeenCalledTimes(1);
    expect(a.accessToken).toBe("new-access");
    expect(b).toEqual(a);
    expect(c).toEqual(a);
  });

  it("does not memoize failures", async () => {
    const failing = vi.fn<typeof fetch>(async () => new Response("{}", { status: 500 }));
    const d = deps({ fetchImpl: failing });
    await jwtCallback({ token: expiringToken, account: null }, d);
    await jwtCallback({ token: expiringToken, account: null }, d);
    expect(failing).toHaveBeenCalledTimes(2);
  });
});
