/** RP-initiated logout URL for Keycloak (OIDC RP-Initiated Logout 1.0; ADR-0011 §1). */
export function buildEndSessionUrl(params: {
  issuer: string;
  idToken: string;
  postLogoutRedirectUri: string;
  clientId: string;
}): string {
  const issuer = params.issuer.replace(/\/$/, "");
  const url = new URL(`${issuer}/protocol/openid-connect/logout`);
  url.searchParams.set("id_token_hint", params.idToken);
  url.searchParams.set("post_logout_redirect_uri", params.postLogoutRedirectUri);
  url.searchParams.set("client_id", params.clientId);
  return url.toString();
}

/** State-changing route handlers accept only same-origin requests (ADR-0011 §2). */
export function isSameOrigin(originHeader: string | null, expectedUrl: string): boolean {
  if (!originHeader || originHeader === "null") return false;
  try {
    return new URL(originHeader).origin === new URL(expectedUrl).origin;
  } catch {
    return false;
  }
}
