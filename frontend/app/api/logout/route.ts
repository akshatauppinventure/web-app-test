import { NextResponse, type NextRequest } from "next/server";

import { auth, signOut } from "@/auth";
import { getAuthEnv } from "@/lib/auth-config";
import { buildEndSessionUrl, isSameOrigin } from "@/lib/logout";

// RP-initiated logout (ADR-0011 §1): clear the Auth.js cookie, then end the Keycloak session
// with id_token_hint. POST only, same-origin only.
export async function POST(req: NextRequest) {
  const env = getAuthEnv();
  if (!isSameOrigin(req.headers.get("origin"), env.authUrl)) {
    return new NextResponse("Forbidden", { status: 403 });
  }
  const session = await auth();
  const idToken = session?.idToken;
  await signOut({ redirect: false });
  if (!idToken) return NextResponse.redirect(new URL("/", env.authUrl), 303);
  return NextResponse.redirect(
    buildEndSessionUrl({
      issuer: env.issuer,
      idToken,
      postLogoutRedirectUri: `${env.authUrl}/`,
      clientId: env.clientId,
    }),
    303,
  );
}
