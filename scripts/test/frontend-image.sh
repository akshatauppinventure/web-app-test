#!/usr/bin/env bash
# Hardening checks for the frontend image (PLAN T08). Usage: frontend-image.sh <image>
set -euo pipefail
IMAGE="${1:?image reference required}"
HARDEN=(--read-only --cap-drop ALL --security-opt no-new-privileges:true
        --tmpfs "/tmp:rw,noexec,nosuid,size=16m" --tmpfs "/app/.next/cache:rw,nosuid,size=64m,uid=1000,gid=1000")
ENV=(-e AUTH_URL=http://localhost:13000 -e AUTH_SECRET=image-test-secret-0123456789abcdef0123456789
     -e AUTH_KEYCLOAK_SECRET=image-test -e AUTH_KEYCLOAK_ISSUER=http://keycloak:8080/auth/realms/app
     -e API_BASE_URL=http://backend:8000)
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

uid="$(docker run --rm "${HARDEN[@]}" --entrypoint id "$IMAGE" -u)"
[[ "$uid" == "1000" ]] || fail "runs as uid $uid, expected 1000 (node)"
pass "runs as uid 1000 (node)"

for tool in npm npx yarn corepack pnpm; do
  if docker run --rm --entrypoint sh "$IMAGE" -c "command -v $tool" >/dev/null 2>&1; then
    fail "$tool present in runtime image"
  fi
done
pass "no npm/npx/yarn/corepack/pnpm in runtime image"

for path in /app/server.js /app/.next/static /app/public; do
  docker run --rm --entrypoint sh "$IMAGE" -c "test -e $path" || fail "missing $path"
done
pass "standalone server, static assets and public dir present"

writable="$(docker run --rm "${HARDEN[@]}" --entrypoint sh "$IMAGE" -c 'touch /app/x 2>/dev/null && echo yes || echo no')"
[[ "$writable" == "no" ]] || fail "/app is writable at runtime"
pass "/app is not writable"

for label in org.opencontainers.image.source org.opencontainers.image.revision org.opencontainers.image.created; do
  value="$(docker image inspect "$IMAGE" --format "{{ index .Config.Labels \"$label\" }}")"
  [[ -n "$value" ]] || fail "missing OCI label $label"
done
pass "OCI labels present"

cid="$(docker run -d --rm "${HARDEN[@]}" "${ENV[@]}" -p 127.0.0.1:13000:3000 "$IMAGE")"
trap 'docker stop "$cid" >/dev/null 2>&1 || true' EXIT
for _ in $(seq 1 40); do
  if body="$(curl -sf http://127.0.0.1:13000/api/healthz 2>/dev/null)"; then break; fi
  sleep 0.5
done
[[ "${body:-}" == '{"status":"ok"}' ]] || fail "/api/healthz did not answer: '${body:-}'"
pass "/api/healthz answers with a read-only root filesystem"

hdrs="$(curl -sI http://127.0.0.1:13000/api/healthz | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
grep -q '^x-powered-by:' <<<"$hdrs" && fail "X-Powered-By header present" || true
pass "no X-Powered-By header"

home="$(curl -s http://127.0.0.1:13000/)"
grep -q "Sign in with Google" <<<"$home" || fail "landing page did not render the sign-in button"
grep -q "Sign in with Apple" <<<"$home" && fail "Apple button visible although NEXT_PUBLIC_APPLE_LOGIN is unset" || true
pass "landing page renders (Google button shown, Apple hidden)"

code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:13000/hello)"
[[ "$code" == "307" || "$code" == "302" ]] || fail "unauthenticated /hello should redirect, got $code"
pass "unauthenticated /hello redirects"

for _ in $(seq 1 20); do
  status="$(docker inspect --format '{{ .State.Health.Status }}' "$cid")"
  [[ "$status" == "healthy" ]] && break
  sleep 1
done
[[ "$status" == "healthy" ]] || fail "container health is '$status'"
pass "HEALTHCHECK reports healthy"

size="$(docker image inspect "$IMAGE" --format '{{ .Size }}')"
echo "image size: $(( size / 1024 / 1024 )) MiB"
echo "ALL CHECKS PASSED"
