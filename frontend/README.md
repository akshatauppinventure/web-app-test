# frontend

Next.js 16 app (ADR-0007) acting as the browser-facing BFF. Node 24, pnpm (exact version in `package.json`).

```bash
pnpm install --frozen-lockfile
pnpm check            # next-version guard, eslint, tsc, vitest, next build
pnpm dev              # http://localhost:3000
```

- `output: "standalone"`; the container (T08) copies `.next/standalone` + `.next/static` + `public`.
- `scripts/check-next-version.mts` fails when `next` is older than the floor `16.3.3`.
- Supply-chain settings live in `pnpm-workspace.yaml`: lifecycle scripts only for allowlisted packages, `minimumReleaseAge` of 3 days (new versions cannot be installed on release day).
- Routes: `/` (landing, sign-in placeholders until T07), `/hello` (placeholder until T07), `/api/healthz`.
