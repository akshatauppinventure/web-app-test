// Fails when the installed `next` is older than the floor (ADR-0007; enforced in CI, T11).
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import process from "node:process";

export const NEXT_VERSION_FLOOR = "16.3.3";

/** Strict semver "x.y.z" (no pre-release) compared against a floor of the same form. */
export function satisfiesFloor(version: string, floor: string): boolean {
  const parse = (v: string): [number, number, number] | null => {
    const m = /^(\d+)\.(\d+)\.(\d+)$/.exec(v);
    return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
  };
  const a = parse(version);
  const b = parse(floor);
  if (!a || !b) return false;
  for (let i = 0; i < 3; i += 1) {
    const x = a[i] ?? 0;
    const y = b[i] ?? 0;
    if (x !== y) return x > y;
  }
  return true;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const require = createRequire(import.meta.url);
  const { version } = require("next/package.json") as { version: string };
  if (!satisfiesFloor(version, NEXT_VERSION_FLOOR)) {
    console.error(`next@${version} is below the required floor ${NEXT_VERSION_FLOOR}`);
    process.exit(1);
  }
  console.log(`next@${version} satisfies floor ${NEXT_VERSION_FLOOR}`);
}
