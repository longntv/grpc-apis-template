#!/usr/bin/env bash
# AIP lint (https://google.aip.dev) for every proto in proto/:
#   1. Google's api-linter (https://linter.aip.dev).
#   2. Small checks api-linter does not cover.
# Imports are resolved from a buf-built descriptor set, so api-linter sees
# exactly what buf sees.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
status=0

buf build -o "$tmp/image.binpb"

# 1. api-linter: print the summary; on failure, re-run with file:line details.
lint() {
  (cd proto && find . -name '*.proto' | sed 's|^\./||' | sort | xargs api-linter \
    --config ../api-linter.yaml \
    --descriptor-set-in "$tmp/image.binpb" \
    --set-exit-status "$@")
}
if ! lint --output-format summary; then
  lint --output-format yaml 2>/dev/null | awk '/^- file_path:/{f=$0} /problems: \[\]/{f=""; next} f!=""{print}' || true
  status=1
fi

# 2. AIP-122: a resource is identified by `name`, never by an `id` field.
if grep -rnE '^[[:space:]]*(optional[[:space:]]+)?(string|bytes|u?int(32|64)|s?fixed(32|64))[[:space:]]+id[[:space:]]*=' --include='*.proto' proto; then
  echo "AIP-122: use 'string name' (resource name) instead of 'id' (see https://google.aip.dev/122)" >&2
  status=1
fi

exit "$status"
