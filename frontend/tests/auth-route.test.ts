import { describe, expect, it } from "vitest";

import { isBlockedAuthPath } from "../lib/auth-routes";

describe("Auth.js HTTP surface (no token is readable from client JS)", () => {
  it.each([
    ["/api/auth/session", true],
    ["/api/auth/session/", true],
    ["/api/auth/csrf", false],
    ["/api/auth/callback/keycloak", false],
    ["/api/auth/signin", false],
    ["/api/auth/signin/keycloak", false],
    ["/api/auth/signout", false],
    ["/api/auth/providers", false],
  ])("%s blocked=%s", (path, blocked) => {
    expect(isBlockedAuthPath(path)).toBe(blocked);
  });
});
