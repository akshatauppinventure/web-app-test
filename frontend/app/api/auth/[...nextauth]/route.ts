import type { NextRequest } from "next/server";

import { handlers } from "@/auth";
import { isBlockedAuthPath } from "@/lib/auth-routes";

export async function GET(req: NextRequest) {
  if (isBlockedAuthPath(req.nextUrl.pathname)) return new Response(null, { status: 404 });
  return handlers.GET(req);
}

export const POST = handlers.POST;
