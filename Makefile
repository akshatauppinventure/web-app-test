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

.PHONY: backend-image backend-image-test
backend-image: ## Build the backend image (T04)
	$(call not_yet,backend-image,T04)
backend-image-test: ## Run hardening checks against the backend image (T04)
	$(call not_yet,backend-image-test,T04)

.PHONY: frontend-check
frontend-check: ## Frontend: lint, typecheck, tests, build (T06)
	$(call not_yet,frontend-check,T06)

.PHONY: frontend-image frontend-image-test
frontend-image: ## Build the frontend image (T08)
	$(call not_yet,frontend-image,T08)
frontend-image-test: ## Run hardening checks against the frontend image (T08)
	$(call not_yet,frontend-image-test,T08)

.PHONY: test-db-up test-db-down
test-db-up: ## Start the throwaway Postgres for integration tests (127.0.0.1:55432)
	docker compose -f compose.test.yaml up -d --wait
test-db-down: ## Stop the throwaway test Postgres and delete its volume
	docker compose -f compose.test.yaml down -v

.PHONY: dev-up dev-down dev-logs dev-reset
dev-up: ## Start the local full stack (T09)
	$(call not_yet,dev-up,T09)
dev-down: ## Stop the local full stack (T09)
	$(call not_yet,dev-down,T09)
dev-logs: ## Tail local stack logs (T09)
	$(call not_yet,dev-logs,T09)
dev-reset: ## Stop the local stack and delete its volumes (T09)
	$(call not_yet,dev-reset,T09)
