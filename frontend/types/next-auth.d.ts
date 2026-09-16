import type { DefaultSession } from "next-auth";

declare module "next-auth" {
  interface Session {
    user: DefaultSession["user"];
    /** Access token for server-side API calls. Never exposed to the browser (see lib/auth-routes.ts). */
    accessToken?: string | undefined;
    idToken?: string | undefined;
    error?: "RefreshTokenError" | undefined;
  }
}

declare module "next-auth/jwt" {
  interface JWT {
    accessToken?: string | undefined;
    refreshToken?: string | undefined;
    idToken?: string | undefined;
    /** Unix seconds. */
    expiresAt?: number | undefined;
    error?: "RefreshTokenError" | undefined;
  }
}
