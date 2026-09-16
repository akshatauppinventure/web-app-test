import "server-only";

import { auth } from "@/auth";

export interface ServerSession {
  accessToken: string;
  idToken: string | undefined;
  name: string | null | undefined;
  email: string | null | undefined;
}

/** The signed-in user's tokens for server code, or null when signed out / refresh failed. */
export async function getServerSession(): Promise<ServerSession | null> {
  const session = await auth();
  if (!session?.accessToken || session.error) return null;
  return {
    accessToken: session.accessToken,
    idToken: session.idToken,
    name: session.user?.name,
    email: session.user?.email,
  };
}
