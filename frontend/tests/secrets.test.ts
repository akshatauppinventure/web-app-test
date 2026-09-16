import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { readSecret } from "../lib/secrets";

const saved = { ...process.env };
afterEach(() => {
  process.env = { ...saved };
});

describe("readSecret (ADR-0016: secrets from files, env fallback for local dev)", () => {
  it("prefers <NAME>_FILE and trims the trailing newline", () => {
    const dir = mkdtempSync(join(tmpdir(), "sec-"));
    const file = join(dir, "auth_secret");
    writeFileSync(file, "s3cret-value\n");
    process.env.AUTH_SECRET_FILE = file;
    process.env.AUTH_SECRET = "env-value";
    expect(readSecret("AUTH_SECRET")).toBe("s3cret-value");
  });

  it("falls back to the environment variable", () => {
    delete process.env.AUTH_SECRET_FILE;
    process.env.AUTH_SECRET = "env-value";
    expect(readSecret("AUTH_SECRET")).toBe("env-value");
  });

  it("throws a message that names the variable but never the value", () => {
    delete process.env.AUTH_SECRET_FILE;
    delete process.env.AUTH_SECRET;
    expect(() => readSecret("AUTH_SECRET")).toThrow(/AUTH_SECRET_FILE or AUTH_SECRET/);
  });

  it("throws when the file does not exist", () => {
    process.env.AUTH_SECRET_FILE = "/nonexistent/secret";
    expect(() => readSecret("AUTH_SECRET")).toThrow(/AUTH_SECRET_FILE/);
  });
});
