# syntax=docker/dockerfile:1
# Hermetic codegen toolchain: buf + Go/TS/Python plugins at pinned versions.
# Every developer and CI run produces byte-identical output in gen/.
ARG BUF_VERSION=1.50.0
ARG GO_VERSION=1.24
ARG NODE_VERSION=22
ARG PYTHON_VERSION=3.12

FROM bufbuild/buf:${BUF_VERSION} AS buf

FROM golang:${GO_VERSION}-bookworm AS go-plugins
ARG PROTOC_GEN_GO_VERSION=v1.36.5
ARG PROTOC_GEN_GO_GRPC_VERSION=v1.5.1
# Google's AIP linter (https://linter.aip.dev), complements buf lint.
ARG API_LINTER_VERSION=v1.72.0
# Injects `// @gotags: ...` comments from .proto files as Go struct tags.
ARG PROTOC_GO_INJECT_TAG_VERSION=v1.4.0
RUN CGO_ENABLED=0 go install google.golang.org/protobuf/cmd/protoc-gen-go@${PROTOC_GEN_GO_VERSION} \
 && CGO_ENABLED=0 go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@${PROTOC_GEN_GO_GRPC_VERSION} \
 && CGO_ENABLED=0 go install github.com/googleapis/api-linter/cmd/api-linter@${API_LINTER_VERSION} \
 && CGO_ENABLED=0 go install github.com/favadi/protoc-go-inject-tag@${PROTOC_GO_INJECT_TAG_VERSION}

FROM node:${NODE_VERSION}-bookworm-slim AS es-plugins
# Keep in sync with "@bufbuild/protobuf" in package.json.
ARG PROTOC_GEN_ES_VERSION=2.16.0
WORKDIR /opt/es
RUN npm init -y >/dev/null && npm install --omit=dev --save-exact @bufbuild/protoc-gen-es@${PROTOC_GEN_ES_VERSION} @bufbuild/protobuf@${PROTOC_GEN_ES_VERSION} @bufbuild/protoplugin@${PROTOC_GEN_ES_VERSION}

FROM python:${PYTHON_VERSION}-slim-bookworm
# Keep in sync with "grpcio" in pyproject.toml.
ARG GRPCIO_TOOLS_VERSION=1.70.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends git make \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && pip install --no-cache-dir grpcio-tools==${GRPCIO_TOOLS_VERSION}
COPY --from=buf /usr/local/bin/buf /usr/local/bin/buf
COPY --from=go-plugins /go/bin/protoc-gen-go /go/bin/protoc-gen-go-grpc /go/bin/api-linter /go/bin/protoc-go-inject-tag /usr/local/bin/
COPY --from=es-plugins /usr/local/bin/node /usr/local/bin/node
COPY --from=es-plugins /opt/es /opt/es
RUN printf '#!/bin/sh\nexec node /opt/es/node_modules/@bufbuild/protoc-gen-es/bin/protoc-gen-es "$@"\n' \
      > /usr/local/bin/protoc-gen-es \
 && chmod +x /usr/local/bin/protoc-gen-es
ENV HOME=/tmp BUF_CACHE_DIR=/tmp/buf-cache PYTHON=python
WORKDIR /workspace
