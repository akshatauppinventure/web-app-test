import { readFileSync } from "node:fs";

/**
 * Reads a secret from `<NAME>_FILE` (a Docker/Compose secret file, ADR-0016) or, for local
 * development only, from the `<NAME>` environment variable. Values are never logged.
 */
export function readSecret(name: string): string {
  const fileVar = `${name}_FILE`;
  const file = process.env[fileVar];
  if (file) {
    try {
      return readFileSync(file, "utf8").replace(/\r?\n$/, "");
    } catch {
      throw new Error(`${fileVar} points to an unreadable file`);
    }
  }
  const value = process.env[name];
  if (value) return value;
  throw new Error(`Missing secret: set ${fileVar} or ${name}`);
}
