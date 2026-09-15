#!/usr/bin/env bash
# Hardening checks for the backend image (PLAN T04). Usage: backend-image.sh <image>
set -euo pipefail
IMAGE="${1:?image reference required}"
HARDEN=(--read-only --cap-drop ALL --security-opt no-new-privileges:true --tmpfs "/tmp:rw,noexec,nosuid,size=16m")
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

uid="$(docker run --rm "${HARDEN[@]}" --entrypoint id "$IMAGE" -u)"
[[ "$uid" == "10001" ]] || fail "runs as uid $uid, expected 10001"
pass "runs as uid 10001"

if docker run --rm --entrypoint sh "$IMAGE" -c 'command -v uv' >/dev/null 2>&1; then
  fail "uv binary present in runtime image"
fi
pass "no uv in runtime image"

if docker run --rm --entrypoint sh "$IMAGE" -c 'command -v gcc || command -v pip' >/dev/null 2>&1; then
  fail "build tooling (gcc/pip) present in runtime image"
fi
pass "no gcc/pip in runtime image"

docker run --rm "${HARDEN[@]}" --entrypoint python "$IMAGE" -c 'import app.main' >/dev/null
pass "app package importable"

writable="$(docker run --rm "${HARDEN[@]}" --entrypoint sh "$IMAGE" -c 'touch /app/x 2>/dev/null && echo yes || echo no')"
[[ "$writable" == "no" ]] || fail "/app is writable at runtime"
pass "/app is not writable"

for label in org.opencontainers.image.source org.opencontainers.image.revision org.opencontainers.image.created; do
  value="$(docker image inspect "$IMAGE" --format "{{ index .Config.Labels \"$label\" }}")"
  [[ -n "$value" ]] || fail "missing OCI label $label"
done
pass "OCI labels present"

cid="$(docker run -d --rm "${HARDEN[@]}" -p 127.0.0.1:18000:8000 "$IMAGE")"
trap 'docker stop "$cid" >/dev/null 2>&1 || true' EXIT
for _ in $(seq 1 30); do
  if body="$(curl -sf http://127.0.0.1:18000/healthz 2>/dev/null)"; then break; fi
  sleep 0.5
done
[[ "${body:-}" == '{"status":"ok"}' ]] || fail "/healthz did not answer: '${body:-}'"
pass "/healthz answers with a read-only root filesystem"

code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18000/docs)"
[[ "$code" == "404" ]] || fail "/docs exposed (HTTP $code) in the default environment"
pass "/docs is 404 by default"

hdrs="$(curl -sI http://127.0.0.1:18000/healthz | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
if grep -q '^server:' <<<"$hdrs"; then fail "Server header present"; fi
pass "no Server header"

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
