import NextAuth from "next-auth";
import Keycloak from "next-auth/providers/keycloak";

import { getAuthEnv } from "./lib/auth-config";
import { jwtCallback } from "./lib/token-refresh";

/**
 * Auth.js v5 BFF configuration (ADR-0011 §1). Config is built lazily so that secrets are read at
 * request time, not at build time. The browser is sent to the public Keycloak URL; the server
 * exchanges codes and refreshes tokens over the internal network (no discovery needed).
 */
export const { handlers, auth, signIn, signOut } = NextAuth(() => {
  const env = getAuthEnv();
  const secure = env.authUrl.startsWith("https://");
  return {
    trustHost: true,
    secret: env.authSecret,
    useSecureCookies: secure,
    session: { strategy: "jwt", maxAge: 10 * 60 * 60 },
    pages: { signIn: "/", error: "/" },
    providers: [
      Keycloak({
        clientId: env.clientId,
        clientSecret: env.clientSecret,
        issuer: env.issuer,
        authorization: {
          url: `${env.issuer}/protocol/openid-connect/auth`,
          params: { scope: "openid profile email" },
        },
        token: { url: `${env.internalIssuer}/protocol/openid-connect/token` },
        userinfo: { url: `${env.internalIssuer}/protocol/openid-connect/userinfo` },
        checks: ["pkce", "state", "nonce"],
      }),
    ],
    callbacks: {
      // Used by proxy.ts only (redirect convenience); real authorization lives in pages + API.
      authorized: ({ auth: session }) => Boolean(session?.accessToken) && !session?.error,
      jwt: ({ token, account }) =>
        jwtCallback(
          { token, account },
          {
            tokenEndpoint: `${env.internalIssuer}/protocol/openid-connect/token`,
            clientId: env.clientId,
            clientSecret: env.clientSecret,
          },
        ),
      session: ({ session, token }) => {
        session.accessToken = token.accessToken;
        session.idToken = token.idToken;
        session.error = token.error;
        return session;
      },
    },
  };
});
