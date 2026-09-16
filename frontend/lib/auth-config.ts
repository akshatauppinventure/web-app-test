import { readSecret } from "./secrets";

export interface AuthEnv {
  authUrl: string;
  authSecret: string;
  clientId: string;
  clientSecret: string;
  /** Public issuer, e.g. https://test-vinayak.duckdns.org/auth/realms/app (matches token `iss`). */
  issuer: string;
  /** Same realm reached over the internal network, e.g. http://10.10.0.2:8080/auth/realms/app. */
  internalIssuer: string;
  apiBaseUrl: string;
}

let cached: AuthEnv | undefined;

/** Reads and validates the auth environment once per process (secrets from files, ADR-0016). */
export function getAuthEnv(): AuthEnv {
  if (cached) return cached;
  const issuer = required("AUTH_KEYCLOAK_ISSUER").replace(/\/$/, "");
  cached = {
    authUrl: required("AUTH_URL").replace(/\/$/, ""),
    authSecret: readSecret("AUTH_SECRET"),
    clientId: process.env.AUTH_KEYCLOAK_ID ?? "web-bff",
    clientSecret: readSecret("AUTH_KEYCLOAK_SECRET"),
    issuer,
    internalIssuer: (process.env.KEYCLOAK_INTERNAL_ISSUER ?? issuer).replace(/\/$/, ""),
    apiBaseUrl: process.env.API_BASE_URL ?? "http://localhost:8000",
  };
  return cached;
}

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable ${name}`);
  return value;
}
