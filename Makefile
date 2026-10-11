# All tooling runs inside a pinned Docker image by default, so the only
# prerequisites are `docker` and `make`. Use LOCAL=1 to run with tools on PATH.
SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help
# Targets depend on each other's output (lint before generate, generate before
# verify); never run them concurrently under `make -j`.
.NOTPARALLEL:

# The image tag is derived from the Dockerfile content, so editing the
# Dockerfile forces `make init` instead of silently reusing a stale image.
IMAGE            ?= proto-tools:$(shell git hash-object Dockerfile 2>/dev/null | cut -c1-12)
LOCAL            ?= 0
BREAKING_AGAINST ?= .git\#branch=main
VERSION          ?=
OWNER            ?=
REPO             ?=

ifeq ($(LOCAL),1)
  RUN   :=
  IMAGE_DEP :=
else
  # --pull=never: never fall back to pulling an unknown image from a registry.
  RUN   := docker run --rm --pull=never -v "$(CURDIR)":/workspace -w /workspace \
           -u "$$(id -u):$$(id -g)" -e BUF_CACHE_DIR=/workspace/.cache/buf $(IMAGE)
  IMAGE_DEP := image
endif

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}'

.PHONY: init
init: ## Build the pinned codegen toolchain image
	docker build -t $(IMAGE) .

.PHONY: image
image:
	@docker image inspect $(IMAGE) >/dev/null 2>&1 || { echo "toolchain image $(IMAGE) not found (Dockerfile new or changed): run 'make init'" >&2; exit 1; }

.PHONY: deps
deps: $(IMAGE_DEP) ## Update pinned proto dependencies (buf.lock)
	$(RUN) buf dep update

.PHONY: lint
lint: lint-buf lint-aip ## Run all linters

.PHONY: lint-buf
lint-buf: $(IMAGE_DEP) ## buf lint (STANDARD + COMMENTS)
	$(RUN) buf lint

.PHONY: lint-aip
lint-aip: $(IMAGE_DEP) ## Google api-linter (AIP rules, e.g. AIP-122 resource names)
	$(RUN) ./scripts/lint-aip.sh

.PHONY: format
format: $(IMAGE_DEP) ## Rewrite protos with canonical formatting
	$(RUN) buf format -w

.PHONY: format-check
format-check: $(IMAGE_DEP) ## Fail if any proto is not formatted
	$(RUN) buf format -d --exit-code

.PHONY: breaking
breaking: $(IMAGE_DEP) ## Detect breaking changes vs BREAKING_AGAINST (default: local main branch)
	$(RUN) buf breaking --against '$(BREAKING_AGAINST)'

.PHONY: gen-go
gen-go: $(IMAGE_DEP) ## Generate Go stubs into gen/go
	$(RUN) buf generate --template buf.gen.go.yaml

.PHONY: gen-ts
gen-ts: $(IMAGE_DEP) ## Generate Node.js/TypeScript stubs into gen/es
	$(RUN) buf generate --template buf.gen.ts.yaml

.PHONY: gen-python
gen-python: $(IMAGE_DEP) ## Generate Python stubs into gen/python
	$(RUN) ./scripts/gen-python.sh

.PHONY: generate
generate: lint gen-go gen-ts gen-python ## Lint, then generate stubs for all languages

.PHONY: verify
verify: format-check generate ## CI: fail if committed gen/ is stale
	@if [ -n "$$(git status --porcelain -- gen)" ]; then \
	  git status --short -- gen; \
	  echo "gen/ is out of date: run 'make generate' and commit the result." >&2; exit 1; \
	fi

.PHONY: release
release: ## Verify, bump package versions, commit and tag: make release VERSION=1.2.0
	@[[ "$(VERSION)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$$ ]] || { echo "usage: make release VERSION=X.Y.Z" >&2; exit 1; }
	@[[ "$(VERSION)" == 1.* ]] || { echo "Stay on 1.x: a Go module v2+ needs a /v2 import path. Version APIs via proto packages (longntv.user.v2) instead." >&2; exit 1; }
	@[ "$$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "release from the main branch" >&2; exit 1; }
	@! git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null || { echo "tag v$(VERSION) already exists" >&2; exit 1; }
	@[ -z "$$(git status --porcelain)" ] || { echo "working tree is dirty" >&2; exit 1; }
	$(MAKE) verify
	sed -i.bak -E 's/^  "version": "[^"]+"/  "version": "$(VERSION)"/' package.json && rm package.json.bak
	sed -i.bak -E 's/^version = "[^"]+"/version = "$(VERSION)"/' pyproject.toml && rm pyproject.toml.bak
	git add package.json pyproject.toml
	git diff --cached --quiet || git commit -m "release: v$(VERSION)"
	git tag -a "v$(VERSION)" -m "v$(VERSION)"
	@echo "Tagged v$(VERSION). Publish with: git push origin main v$(VERSION)"

.PHONY: rename
rename: ## Template setup: make rename OWNER=my-org [REPO=my-apis]
	@[ -n "$(OWNER)" ] || { echo "usage: make rename OWNER=my-org [REPO=my-apis]" >&2; exit 1; }
	./scripts/rename.sh "$(OWNER)" $(REPO)

.PHONY: clean
clean: ## Remove all generated code
	rm -rf gen
