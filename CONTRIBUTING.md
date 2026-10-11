# Contributing

Every `.proto` here is a contract used by other services. Treat changes like
public API changes.

## Workflow

1. `make init` once (builds the pinned toolchain image; only Docker + make needed).
2. Edit or add files under `proto/`.
3. `make format generate` (formats, runs both linters, regenerates `gen/`).
4. `make breaking` to compare against `main`.
5. Commit the `.proto` change **and** `gen/` in the same PR.

CI rejects the PR if lint fails, `gen/` is stale, or a breaking change is detected.

## Design rules

Follow the [Google AIPs](https://google.aip.dev). The linters enforce most of them; the
key ones:

| Topic | Rule |
|-------|------|
| Resource identity ([AIP-122](https://google.aip.dev/122)) | `string name = 1` holds the resource name (`users/{user}`), never `id`. |
| Hierarchy ([AIP-122](https://google.aip.dev/122)) | Child resources nest under the parent name (`users/{user}/addresses/{address}`); List/Create take `parent`. Delete of a parent with children takes `bool force` ([AIP-135](https://google.aip.dev/135)). |
| Standard methods ([AIP-131..135](https://google.aip.dev/131)) | `Get/Create/Update` return the resource; `List` returns `ListXxxResponse`; `Delete` returns `google.protobuf.Empty`. |
| Field behavior | Say it in the comment: `Required.`, `Set by the server.` Go validation goes in a `// @gotags: validate:"..."` line. |
| Time ([AIP-142](https://google.aip.dev/142)) | `google.protobuf.Timestamp` named `*_time` (`create_time`). |
| State ([AIP-216](https://google.aip.dev/216)) | Nested `enum State`, set by the server. |
| Pagination ([AIP-158](https://google.aip.dev/158)) | `page_size`, `page_token`, `next_page_token`. |
| Compatibility ([AIP-180](https://google.aip.dev/180)) | Never renumber or reuse a field; `reserved` removed numbers and names. |

Disabling a lint rule needs a written justification in `buf.yaml` or `api-linter.yaml`.

## Releasing

Maintainers: `make release VERSION=1.x.y` then `git push origin main v1.x.y`.
New fields/RPCs/services are a minor release; docs or toolchain-only changes are a patch release.
