/**
 * Auth.js serves GET /api/auth/session with the output of the `session` callback. We keep
 * tokens server-side only, so that endpoint is disabled (no client-side session is used).
 */
export function isBlockedAuthPath(pathname: string): boolean {
  return /^\/api\/auth\/session\/?$/.test(pathname);
}
