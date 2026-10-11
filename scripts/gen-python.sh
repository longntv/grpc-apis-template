#!/usr/bin/env bash
# Generates Python messages (+ .pyi type stubs) and gRPC stubs into gen/python.
# grpc_tools.protoc is used (not a buf plugin) so the generated code matches the
# pinned grpcio-tools / protobuf runtime versions declared in pyproject.toml.
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHON="${PYTHON:-python3}"
OUT=gen/python

rm -rf "$OUT"
mkdir -p "$OUT"

# google/api/*.proto come from the buf.lock-pinned googleapis module. Only our
# own files are compiled; google.api.* is provided at runtime by the
# googleapis-common-protos package (see pyproject.toml).
deps="$(mktemp -d)"
trap 'rm -rf "$deps"' EXIT
buf export . --output "$deps"

protos="$(find proto -name '*.proto' | sed 's|^proto/||' | sort)"
[ -n "$protos" ] || { echo "no .proto files under proto/" >&2; exit 1; }
printf '%s\n' "$protos" | xargs "$PYTHON" -m grpc_tools.protoc \
  -I "$deps" \
  --python_out="$OUT" \
  --pyi_out="$OUT" \
  --grpc_python_out="$OUT"

# The top-level org directory stays an implicit namespace package (no
# __init__.py) so several API repos of one org can be installed together.
# Everything below it is a regular package shipping type hints (PEP 561).
find "$OUT" -mindepth 2 -type d -exec touch {}/__init__.py \;
find "$OUT" -mindepth 2 -type d -exec touch {}/py.typed \;
