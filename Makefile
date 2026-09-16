# Task targets are added as PLAN.md tasks land. Stubs fail loudly until then.
SHELL := /bin/bash
.DEFAULT_GOAL := help

define not_yet
	@echo "$(1) is not implemented yet (PLAN.md task $(2))"; exit 1
endef

.PHONY: help
help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-24s %s\n", $$1, $$2}'

.PHONY: backend-check backend-run
backend-check: ## Backend: locked sync, ruff, pyright, pytest
	cd backend && uv sync --locked && uv run ruff check . && uv run ruff format --check . && uv run pyright && uv run pytest -q
backend-migrate: ## Backend: alembic upgrade head (needs DATABASE_URL for app_migrator)
	cd backend && uv run alembic upgrade head
backend-run: ## Backend: run uvicorn locally with docs enabled
	cd backend && ENVIRONMENT=local uv run uvicorn app.main:app --port 8000 --reload

GIT_SHA ?= $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
BUILD_DATE ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
BACKEND_IMAGE ?= web-app-test/backend:dev

.PHONY: backend-image backend-image-test hadolint
hadolint: ## Lint every Dockerfile
	hadolint --config .hadolint.yaml $$(git ls-files '*Dockerfile*')
backend-image: ## Build the backend image locally (tag $(BACKEND_IMAGE))
	docker build --pull=false -t $(BACKEND_IMAGE) --build-arg GIT_SHA=$(GIT_SHA) --build-arg BUILD_DATE=$(BUILD_DATE) backend/
backend-image-test: ## Hardening checks against the backend image (non-root, read-only, no uv, healthz, labels)
	scripts/test/backend-image.sh $(BACKEND_IMAGE)

.PHONY: frontend-check frontend-run
frontend-check: ## Frontend: frozen install, next-version guard, eslint, tsc, vitest, next build
	cd frontend && pnpm install --frozen-lockfile && pnpm check
frontend-run: ## Frontend: next dev on :3000
	cd frontend && pnpm dev
frontend-e2e: ## Browser-less login/logout flow against running frontend (:3000), backend (:8000) and Keycloak (:18080)
	scripts/test/frontend-e2e.sh http://localhost:3000 http://localhost:18080/auth/realms/app

FRONTEND_IMAGE ?= web-app-test/frontend:dev

.PHONY: frontend-image frontend-image-test
frontend-image: ## Build the frontend image locally (tag $(FRONTEND_IMAGE))
	docker build --pull=false -t $(FRONTEND_IMAGE) --build-arg GIT_SHA=$(GIT_SHA) --build-arg BUILD_DATE=$(BUILD_DATE) frontend/
frontend-image-test: ## Hardening checks against the frontend image (non-root, read-only, no npm, healthz, labels)
	scripts/test/frontend-image.sh $(FRONTEND_IMAGE)

.PHONY: test-db-up test-db-down
test-db-up: ## Start the throwaway Postgres for integration tests (127.0.0.1:55432); conflicts with the dev stack
	@if docker network inspect web-app-test-dev_db >/dev/null 2>&1; then \
	  echo "error: the dev stack is running and uses the db subnet 172.28.1.0/24 (pg_hba). Run 'make dev-down' first."; exit 1; fi
	docker compose -f compose.test.yaml up -d --wait
test-db-down: ## Stop the throwaway test Postgres (+ Keycloak) and delete volumes
	docker compose -f compose.test.yaml --profile keycloak down -v

.PHONY: traefik-image traefik-test traefik-verify-plugins
traefik-image: ## Build the Traefik image (web-app-test/traefik:dev)
	docker compose -f compose.traefik-test.yaml build traefik
traefik-test: ## Start the Traefik test stack (whoami upstreams, 127.0.0.1:18443) and run scripts/test/traefik-routes.sh
	scripts/test/traefik-test-certs.sh
	docker compose -f compose.traefik-test.yaml up -d --build --wait
	scripts/test/traefik-routes.sh
traefik-verify-plugins: ## Re-verify plugin tarball checksums in infra/traefik/plugins.lock against upstream
	infra/traefik/scripts/fetch-plugins.sh
crowdsec-test: ## CrowdSec engine + bouncer checks against the running Traefik test stack
	scripts/test/crowdsec.sh

.PHONY: stacks-check stacks-dryrun
stacks-check: ## Static policy checks for every compose file (config, published ports, hardening baseline)
	scripts/ci/check-compose.sh
	scripts/ci/check-published-ports.sh
	cd backend && uv run --with pyyaml python ../scripts/ci/check-hardening.py
stacks-dryrun: ## Start the real edge/core stack files locally with overlays and verify them
	scripts/test/stacks-dryrun.sh

.PHONY: keycloak-image keycloak-smoke keycloak-verify-checksums
keycloak-image: ## Build the Keycloak image (web-app-test/keycloak:dev)
	docker compose -f compose.test.yaml --profile keycloak build keycloak
keycloak-smoke: ## Start Postgres + Keycloak (127.0.0.1:18080) and run infra/keycloak/scripts/smoke.sh
	docker compose -f compose.test.yaml --profile keycloak up -d --wait
	KC_ADMIN_PASSWORD_FILE=scripts/test/pg-secrets/keycloak_admin_password \
	WEB_BFF_CLIENT_SECRET_FILE=scripts/test/pg-secrets/web_bff_client_secret \
	GOOGLE_CLIENT_ID=test-google-client-id.apps.googleusercontent.com \
	infra/keycloak/scripts/smoke.sh http://localhost:18080/auth
keycloak-verify-checksums: ## Re-verify third-party artifacts in infra/keycloak/checksums.txt against upstream
	infra/keycloak/scripts/verify-checksums.sh

DEV_COMPOSE := docker compose -f compose.dev.yaml

.PHONY: dev-secrets dev-up dev-down dev-logs dev-reset dev-smoke
dev-secrets: ## Generate .dev-secrets/ (kept if present)
	scripts/dev/gen-dev-secrets.sh
dev-up: dev-secrets ## Build images and start the local full stack (http://localhost:3000)
	@test -f .env || cp .env.example .env
	$(DEV_COMPOSE) build
	$(DEV_COMPOSE) up -d --wait
dev-down: ## Stop the local full stack (keeps data)
	$(DEV_COMPOSE) down
dev-logs: ## Tail local stack logs
	$(DEV_COMPOSE) logs -f --tail=100
dev-reset: ## Stop the local stack and delete its volumes (secrets are kept)
	$(DEV_COMPOSE) down -v --remove-orphans
dev-smoke: ## Health checks + full sign-in/sign-out against the local stack
	scripts/dev/smoke.sh
