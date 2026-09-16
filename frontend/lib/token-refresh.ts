import type { Account } from "next-auth";
import type { JWT } from "next-auth/jwt";

/** Refresh when the access token has this many seconds (or fewer) left (ADR-0011 §1). */
export const REFRESH_THRESHOLD_SECONDS = 60;

export interface RefreshDeps {
  tokenEndpoint: string;
  clientId: string;
  clientSecret: string;
  now?: () => number;
  fetchImpl?: typeof fetch;
}

interface RefreshedTokens {
  accessToken: string;
  refreshToken: string;
  idToken: string | undefined;
  expiresAt: number;
}

export function needsRefresh(
  expiresAt: number | undefined,
  nowSeconds: number,
  threshold = REFRESH_THRESHOLD_SECONDS,
): boolean {
  if (expiresAt === undefined) return true;
  return expiresAt - nowSeconds <= threshold;
}

// Keycloak rotates refresh tokens and revokes the old one on first use (max reuse 0). Within a
// single request the proxy and a server component may both run the jwt callback with the same
// (old) cookie, so a refresh result is memoized per refresh token for a short time.
const MEMO_TTL_MS = 120_000;
const refreshMemo = new Map<string, { result: Promise<RefreshedTokens>; storedAt: number }>();

export function _resetRefreshMemoForTests(): void {
  refreshMemo.clear();
}

async function requestRefresh(refreshToken: string, deps: RefreshDeps): Promise<RefreshedTokens> {
  const fetchImpl = deps.fetchImpl ?? fetch;
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: deps.clientId,
    client_secret: deps.clientSecret,
  });
  const res = await fetchImpl(deps.tokenEndpoint, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
    body: body.toString(),
    cache: "no-store",
    signal: AbortSignal.timeout(5000),
  });
  if (!res.ok) throw new Error(`token endpoint responded ${res.status}`);
  const data = (await res.json()) as {
    access_token?: string;
    refresh_token?: string;
    id_token?: string;
    expires_in?: number;
  };
  if (!data.access_token || !data.refresh_token || typeof data.expires_in !== "number") {
    throw new Error("token endpoint returned an incomplete token set");
  }
  const now = deps.now ?? (() => Math.floor(Date.now() / 1000));
  return {
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    idToken: data.id_token,
    expiresAt: now() + data.expires_in,
  };
}

function refreshOnce(refreshToken: string, deps: RefreshDeps): Promise<RefreshedTokens> {
  const nowMs = Date.now();
  const cached = refreshMemo.get(refreshToken);
  if (cached && nowMs - cached.storedAt < MEMO_TTL_MS) return cached.result;
  const result = requestRefresh(refreshToken, deps);
  refreshMemo.set(refreshToken, { result, storedAt: nowMs });
  result.catch(() => refreshMemo.delete(refreshToken));
  return result;
}

/** Auth.js `jwt` callback: store tokens at sign-in, refresh server-side near expiry. */
export async function jwtCallback(
  params: { token: JWT; account?: Account | null | undefined },
  deps: RefreshDeps,
): Promise<JWT> {
  const { token, account } = params;
  if (account) {
    return {
      ...token,
      accessToken: account.access_token,
      refreshToken: account.refresh_token,
      idToken: account.id_token,
      expiresAt: account.expires_at,
      error: undefined,
    };
  }
  const now = deps.now ?? (() => Math.floor(Date.now() / 1000));
  if (!needsRefresh(token.expiresAt, now())) return token;

  const invalidated: JWT = {
    ...token,
    accessToken: undefined,
    refreshToken: undefined,
    idToken: undefined,
    expiresAt: undefined,
    error: "RefreshTokenError",
  };
  if (!token.refreshToken) return invalidated;
  try {
    const refreshed = await refreshOnce(token.refreshToken, deps);
    return {
      ...token,
      accessToken: refreshed.accessToken,
      refreshToken: refreshed.refreshToken,
      idToken: refreshed.idToken ?? token.idToken,
      expiresAt: refreshed.expiresAt,
      error: undefined,
    };
  } catch {
    return invalidated;
  }
}
