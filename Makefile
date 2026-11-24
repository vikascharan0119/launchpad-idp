# One-command entry points. Targets are added as each part is built.
.DEFAULT_GOAL := help
.PHONY: help

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-14s %s\n", $$1, $$2}'
