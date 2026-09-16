import "server-only";

/** Error raised for non-2xx API responses. Carries the status only, never the upstream body. */
export class ApiError extends Error {
  readonly status: number;
  constructor(status: number) {
    super(`API request failed with status ${status}`);
    this.name = "ApiError";
    this.status = status;
  }
}

export interface ApiFetchOptions {
  method?: "GET" | "POST" | "PUT" | "DELETE";
  body?: unknown;
  baseUrl?: string;
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
}

/**
 * Calls the FastAPI backend from server code only (ADR-0011 §2). The browser never reaches the
 * API; this runs in route handlers / server components with the user's access token.
 */
export async function apiFetch<T>(path: string, accessToken: string, opts: ApiFetchOptions = {}): Promise<T> {
  if (!path.startsWith("/")) throw new Error("path must start with '/'");
  if (!accessToken) throw new Error("access token is required");
  const baseUrl = (opts.baseUrl ?? process.env.API_BASE_URL ?? "http://localhost:8000").replace(/\/$/, "");
  const fetchImpl = opts.fetchImpl ?? fetch;
  const headers: Record<string, string> = {
    authorization: `Bearer ${accessToken}`,
    accept: "application/json",
  };
  const init: RequestInit = {
    method: opts.method ?? "GET",
    headers,
    credentials: "omit",
    cache: "no-store",
    redirect: "error",
    signal: AbortSignal.timeout(opts.timeoutMs ?? 5000),
  };
  if (opts.body !== undefined) {
    headers["content-type"] = "application/json";
    init.body = JSON.stringify(opts.body);
  }
  const res = await fetchImpl(`${baseUrl}${path}`, init);
  if (!res.ok) throw new ApiError(res.status);
  return (await res.json()) as T;
}
