import Link from "next/link";
import { redirect } from "next/navigation";

import { SignOutButton } from "@/components/sign-out-button";
import { ApiError, apiFetch } from "@/lib/api-client";
import { getServerSession } from "@/lib/session";

export const dynamic = "force-dynamic";

interface HelloResponse {
  message: string;
  visit_count: number;
  last_visit: string | null;
}

// Server component: authorization is enforced here (session required) and again by FastAPI
// (token validation + RLS). The proxy only redirects for convenience (ADR-0007 §4).
export default async function HelloPage() {
  const session = await getServerSession();
  if (!session) redirect("/");

  let data: HelloResponse | null = null;
  let failure: string | null = null;
  try {
    data = await apiFetch<HelloResponse>("/v1/hello", session.accessToken);
  } catch (err) {
    failure = err instanceof ApiError ? `The API answered with status ${err.status}.` : "The API could not be reached.";
  }

  return (
    <>
      <h1>Hello</h1>
      {data ? (
        <>
          <p>{data.message}</p>
          <p>Visit count: {data.visit_count}</p>
        </>
      ) : (
        <p role="alert">{failure}</p>
      )}
      <div className="buttons">
        <Link className="button" href="/">
          Home
        </Link>
        <SignOutButton />
      </div>
    </>
  );
}
