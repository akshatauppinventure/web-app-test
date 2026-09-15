import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

// Liveness probe for the container healthcheck and Traefik; no dependencies are checked.
export function GET() {
  return NextResponse.json({ status: "ok" }, { headers: { "cache-control": "no-store" } });
}
