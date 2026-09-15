# Task targets are added as PLAN.md tasks land. Stubs fail loudly until then.
SHELL := /bin/bash
.DEFAULT_GOAL := help

define not_yet
	@echo "$(1) is not implemented yet (PLAN.md task $(2))"; exit 1
endef

.PHONY: help
help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-24s %s\n", $$1, $$2}'

.PHONY: backend-check
backend-check: ## Backend: lint, format check, typecheck, tests (T01)
	$(call not_yet,backend-check,T01)

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

.PHONY: dev-up dev-down dev-logs dev-reset
dev-up: ## Start the local full stack (T09)
	$(call not_yet,dev-up,T09)
dev-down: ## Stop the local full stack (T09)
	$(call not_yet,dev-down,T09)
dev-logs: ## Tail local stack logs (T09)
	$(call not_yet,dev-logs,T09)
dev-reset: ## Stop the local stack and delete its volumes (T09)
	$(call not_yet,dev-reset,T09)
