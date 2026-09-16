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

.PHONY: frontend-image frontend-image-test
frontend-image: ## Build the frontend image (T08)
	$(call not_yet,frontend-image,T08)
frontend-image-test: ## Run hardening checks against the frontend image (T08)
	$(call not_yet,frontend-image-test,T08)

.PHONY: test-db-up test-db-down
test-db-up: ## Start the throwaway Postgres for integration tests (127.0.0.1:55432)
	docker compose -f compose.test.yaml up -d --wait
test-db-down: ## Stop the throwaway test Postgres (+ Keycloak) and delete volumes
	docker compose -f compose.test.yaml --profile keycloak down -v

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

.PHONY: dev-up dev-down dev-logs dev-reset
dev-up: ## Start the local full stack (T09)
	$(call not_yet,dev-up,T09)
dev-down: ## Stop the local full stack (T09)
	$(call not_yet,dev-down,T09)
dev-logs: ## Tail local stack logs (T09)
	$(call not_yet,dev-logs,T09)
dev-reset: ## Stop the local stack and delete its volumes (T09)
	$(call not_yet,dev-reset,T09)
