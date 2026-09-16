import type { NextFetchEvent, NextRequest } from "next/server";

import { auth } from "@/auth";

// Convenience redirect only: unauthenticated visitors of /hello are sent to the sign-in page by
// Auth.js (the `authorized` callback in auth.ts). This is NOT the authorization boundary
// (ADR-0007 §4); pages and FastAPI enforce it. Running Auth.js here also lets it persist a
// refreshed session cookie on the response. With a lazy config, `auth(handler)` returns a
// Promise, so the inline form is used; its middleware overload is missing from the lazy typings.
type AuthMiddleware = (req: NextRequest, event: NextFetchEvent) => Promise<Response | undefined>;
const authMiddleware = auth as unknown as AuthMiddleware;

export function proxy(req: NextRequest, event: NextFetchEvent) {
  return authMiddleware(req, event);
}

export const config = { matcher: ["/hello/:path*"] };
