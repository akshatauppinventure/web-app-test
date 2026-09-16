import { describe, expect, it } from "vitest";

import { buildEndSessionUrl, isSameOrigin } from "../lib/logout";

describe("RP-initiated logout (ADR-0011 §1)", () => {
  it("builds the Keycloak end_session URL with id_token_hint and post_logout_redirect_uri", () => {
    const url = new URL(
      buildEndSessionUrl({
        issuer: "https://test-vinayak.duckdns.org/auth/realms/app",
        idToken: "id.tok.en",
        postLogoutRedirectUri: "https://test-vinayak.duckdns.org/",
        clientId: "web-bff",
      }),
    );
    expect(url.origin + url.pathname).toBe("https://test-vinayak.duckdns.org/auth/realms/app/protocol/openid-connect/logout");
    expect(url.searchParams.get("id_token_hint")).toBe("id.tok.en");
    expect(url.searchParams.get("post_logout_redirect_uri")).toBe("https://test-vinayak.duckdns.org/");
    expect(url.searchParams.get("client_id")).toBe("web-bff");
  });

  it("tolerates a trailing slash on the issuer", () => {
    const url = buildEndSessionUrl({ issuer: "http://localhost:8080/auth/realms/app/", idToken: "x", postLogoutRedirectUri: "http://localhost:3000/", clientId: "web-bff" });
    expect(url.startsWith("http://localhost:8080/auth/realms/app/protocol/openid-connect/logout?")).toBe(true);
  });
});

describe("isSameOrigin (state-changing requests check Origin)", () => {
  it.each([
    ["https://test-vinayak.duckdns.org", "https://test-vinayak.duckdns.org/", true],
    ["https://test-vinayak.duckdns.org", "https://test-vinayak.duckdns.org", true],
    ["https://evil.example", "https://test-vinayak.duckdns.org/", false],
    [null, "https://test-vinayak.duckdns.org/", false],
    ["null", "https://test-vinayak.duckdns.org/", false],
    ["http://test-vinayak.duckdns.org", "https://test-vinayak.duckdns.org/", false],
  ])("origin=%s expected=%s -> %s", (origin, expected, result) => {
    expect(isSameOrigin(origin, expected)).toBe(result);
  });
});
