#!/usr/bin/env bash
# Generates Go messages + gRPC stubs into gen/go, then turns
#   // @gotags: validate:"required,email"
# comments on proto fields into Go struct tags (protoc-go-inject-tag).
set -euo pipefail
cd "$(dirname "$0")/.."

buf generate --template buf.gen.go.yaml

find gen/go -name '*.pb.go' ! -name '*_grpc.pb.go' | sort | while IFS= read -r f; do
  protoc-go-inject-tag -input="$f" -remove_tag_comment
done
