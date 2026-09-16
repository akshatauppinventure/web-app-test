import Link from "next/link";

import { SignInButtons } from "@/components/sign-in-buttons";
import { getServerSession } from "@/lib/session";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const session = await getServerSession();
  return (
    <>
      <h1>web-app-test</h1>
      <p>A hello-world application on a security-first two-VPS deployment.</p>
      {session ? (
        <p>
          Signed in as {session.name ?? session.email ?? "user"}. <Link href="/hello">Go to /hello</Link>
        </p>
      ) : (
        <SignInButtons />
      )}
    </>
  );
}
