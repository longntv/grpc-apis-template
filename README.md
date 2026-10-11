# grpc-apis-template

[![proto](https://github.com/longntv/grpc-apis-template/actions/workflows/ci.yml/badge.svg)](https://github.com/longntv/grpc-apis-template/actions/workflows/ci.yml)

Template for a central gRPC API repository. Protos follow the
[Google AIPs](https://google.aip.dev) (enforced by `buf lint` + Google `api-linter`),
and **pre-generated stubs are committed** for Go, Node.js/TypeScript and Python.
Services pin a git tag (e.g. `v1.0.0`) and import the stubs directly: no `protoc`,
no `buf`, no codegen step on the consumer side.

## Use this template

1. Click **Use this template** on GitHub (or clone), then:

   ```bash
   make rename OWNER=my-org REPO=my-apis   # replaces longntv / grpc-apis-template everywhere
   make init generate                      # build toolchain image, regenerate gen/
   go mod tidy                             # optional, needs a local Go toolchain
   ```

2. Update the copyright holder in `LICENSE` (`rename` already updated CODEOWNERS),
   replace the sample `user/v1` API with your own, commit, then
   `make release VERSION=1.0.0`. `make rename` also turns the resource type prefix
   `user.longntv.github.io` into `user.<owner>.github.io` (see
   [Resource types](#resource-types-and-cross-service-references)).
3. On GitHub: enable **Settings → Template repository** if you want to share it, and
   protect `main` with the `check` and `consumers` CI jobs as required status checks
   (otherwise nothing actually blocks a bad PR).

```
grpc-apis-template/
├── buf.yaml               # buf lint (STANDARD + COMMENTS) / breaking (FILE) rules, deps
├── buf.lock               # Pinned googleapis (google/api/*.proto)
├── api-linter.yaml        # Google api-linter (AIP) config
├── buf.gen.go.yaml        # Go: protoc-gen-go + protoc-gen-go-grpc  -> gen/go
├── buf.gen.ts.yaml        # Node/TS: protoc-gen-es v2 (js + d.ts)   -> gen/es
├── scripts/
│   ├── gen-python.sh      # Python: grpcio-tools (pb2, pyi, grpc)   -> gen/python
│   ├── lint-aip.sh        # api-linter + AIP-122 `id` check
│   └── rename.sh          # one-time template rename
├── Dockerfile             # Pinned toolchain image used by every make target
├── Makefile
├── go.mod                 # Go module      github.com/longntv/grpc-apis-template
├── package.json           # npm package    @longntv/grpc-apis-template
├── pyproject.toml         # pip package    longntv-grpc-apis-template
├── proto/longntv/user/v1/
│   ├── user.proto         # User resource            users/{user}
│   ├── address.proto      # Address child resource   users/{user}/addresses/{address}
│   └── user_service.proto # UserService: AIP standard methods for both resources
└── gen/                   # GENERATED, committed, never edit by hand
```

## Consuming the API (other services)

Replace `v1.0.0` with the tag you need.

### Go

```bash
go get github.com/longntv/grpc-apis-template@v1.0.0
```

```go
import userv1 "github.com/longntv/grpc-apis-template/gen/go/longntv/user/v1"

conn, _ := grpc.NewClient("user-service:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
client := userv1.NewUserServiceClient(conn)
user, err := client.GetUser(ctx, &userv1.GetUserRequest{Name: "users/alice"})

// Server side: embed userv1.UnimplementedUserServiceServer and
// register with userv1.RegisterUserServiceServer(grpcServer, impl).
```

### Node.js / TypeScript

```bash
npm install github:longntv/grpc-apis-template#v1.0.0 @bufbuild/protobuf@^2.16.0
# client/server runtime (Connect speaks gRPC, gRPC-Web and Connect protocols):
npm install @connectrpc/connect @connectrpc/connect-node
```

```ts
import { createClient } from "@connectrpc/connect";
import { createGrpcTransport } from "@connectrpc/connect-node";
import { UserService } from "@longntv/grpc-apis-template/longntv/user/v1/user_service_pb";

const client = createClient(UserService, createGrpcTransport({ baseUrl: "http://user-service:50051" }));
const user = await client.getUser({ name: "users/alice" });
```

Stubs ship as `.js` + `.d.ts` (ESM), so they work from plain JS and TS with no build step.
The package is ESM-only: TypeScript needs `"moduleResolution": "node16"`, `"nodenext"` or
`"bundler"`, and CommonJS code needs Node ≥ 20.19 / 22.12 (`require(esm)`) or `import()`.
Import paths have no extension (`.../user_service_pb`).

### Python

```bash
pip install "git+https://github.com/longntv/grpc-apis-template@v1.0.0"
# requirements.txt: longntv-grpc-apis-template @ git+https://github.com/longntv/grpc-apis-template@v1.0.0
```

```python
import grpc
from longntv.user.v1 import user_service_pb2, user_service_pb2_grpc

stub = user_service_pb2_grpc.UserServiceStub(grpc.insecure_channel("user-service:50051"))
user = stub.GetUser(user_service_pb2.GetUserRequest(name="users/alice"))
```

Type hints (`.pyi`) are included. `googleapis-common-protos` is pulled in automatically
for the `google.api` annotations.

## Working on the protos (this repo)

### Prerequisites

Only **Docker**, **git** and **GNU make**. Every tool (buf, protoc-gen-go,
protoc-gen-go-grpc, protoc-gen-es, grpcio-tools, api-linter) is pinned in the
`Dockerfile`, so every developer and CI run generates the same code. The image tag
is derived from the Dockerfile content: after changing the Dockerfile, `make` asks
you to run `make init` again instead of using a stale image.

```bash
make init        # build the toolchain image (once, and after Dockerfile changes)
make help        # list all targets
```

### Daily workflow

| Command             | What it does                                                 |
|---------------------|--------------------------------------------------------------|
| `make format`       | Rewrite `.proto` files with `buf format`                      |
| `make lint`         | `lint-buf` + `lint-aip` (buf lint and Google api-linter)      |
| `make deps`         | Update pinned googleapis in `buf.lock`                        |
| `make format-check` | Fail if any `.proto` is not formatted                         |
| `make breaking`     | `buf breaking` against local `main` (run `git fetch origin main:main` first; `BREAKING_AGAINST=...` to override) |
| `make generate`     | Lint, then generate Go + Node + Python                        |
| `make gen-go` / `gen-ts` / `gen-python` | Generate a single language                |
| `make verify`       | CI check: format + lint + regenerate, fail if `gen/` is stale |
| `make clean`        | Delete `gen/`                                                 |
| `make release`      | Verify, bump versions, commit and tag (`VERSION=1.x.y`)       |
| `make rename`       | One-time template rename (`OWNER=... REPO=...`)               |

`LOCAL=1 make <target>` runs with tools from your `PATH` instead of Docker.

**Always commit `gen/` together with the `.proto` change.** CI (`.github/workflows/ci.yml`)
runs `make verify`, `make breaking` on pull requests, and a `consumers` job that installs
the Go module, the pip package and the npm package and imports every generated module,
exactly like a consuming service would.

### Lint rules / API design conventions

Two linters run on every `make lint` / CI build:

- **`buf lint`** (`buf.yaml`): `STANDARD` + `COMMENTS`. Versioned packages
  (`longntv.<domain>.v1`), directory matches package, naming conventions, every element
  documented, `// buf:lint:ignore` disabled. Three `STANDARD` rules that contradict the
  AIPs are turned off, with the reasons in `buf.yaml`.
- **Google `api-linter`** (`api-linter.yaml`): AIP semantics. Resource names
  ([AIP-122](https://google.aip.dev/122)), resource annotations (123), standard methods
  (131–135), HTTP mapping (127), time fields (142), field behavior (203), and others.
  `scripts/lint-aip.sh` also rejects `string id` fields: AIP-122 identifies resources by
  `name`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the design rules in one table.

### Resource types and cross-service references

These APIs are meant for service-to-service gRPC. Every resource declares a
**resource type** ([AIP-123](https://google.aip.dev/123)):

```proto
option (google.api.resource) = {
  type: "user.longntv.github.io/User"   // {service-name}/{Kind}
  pattern: "users/{user}"
};
```

Resource names are hierarchical paths of alternating collection IDs and resource IDs
([AIP-122](https://google.aip.dev/122)), like `publishers/123/books/les-miserables`.
The sample shows both levels:

| Resource | Pattern | Example name | Collection methods take |
|----------|---------|--------------|-------------------------|
| `User`    | `users/{user}`                     | `users/alice`               | none (top level) |
| `Address` | `users/{user}/addresses/{address}` | `users/alice/addresses/home` | `parent: "users/alice"` |

The type is a **globally unique identifier, not an address**: no service ever connects
to `user.longntv.github.io`. Services find each other through your usual discovery
(Kubernetes DNS, service mesh, config, e.g. `user-service:50051`). The type lets other
APIs declare which resource a field points to, so the contract is explicit and linted.
Fields hold the **relative** name (`users/alice`); the **full** name
`//user.longntv.github.io/users/alice` is only needed when a field can point to
resources of several APIs and would otherwise be ambiguous:

```proto
// proto/longntv/order/v1/order.proto
message Order {
  // Resource name of the user who placed the order. Format: `users/{user}`.
  string user = 2 [(google.api.resource_reference) = {type: "user.longntv.github.io/User"}];
}
```

`<owner>.github.io` is used as the prefix because GitHub reserves it for your account,
so it can never collide with someone else's types. If you own a domain, you can use it
instead, but only before the first release: the type is part of the API contract.

The `google.api.http` options on each RPC are not used for gRPC calls. They document the
REST mapping (required by AIP-127 lint) and let you expose the same API over HTTP later
through grpc-gateway or Envoy transcoding without changing the protos.

### Adding a new service

```bash
mkdir -p proto/longntv/order/v1
# write proto/longntv/order/v1/order.proto and order_service.proto with
#   package longntv.order.v1;
#   option go_package = "github.com/longntv/grpc-apis-template/gen/go/longntv/order/v1;orderv1";
# copy user/v1 as a starting point: resource annotation, name field, standard methods.
make format generate
git add proto gen && git commit
```

## Versioning & releases

Two independent version axes:

1. **API version, in the proto package** (`longntv.user.v1`). Inside `v1` only
   backward-compatible changes are allowed (`make breaking` enforces it). A breaking
   redesign goes into a new package `longntv.user.v2` **next to** `v1`, so services
   migrate at their own pace.
2. **Repo release, as a git tag** (`vMAJOR.MINOR.PATCH`). One tag versions the Go module,
   the npm package and the pip package together.
   - `MINOR`: new RPCs, fields, services or API versions.
   - `PATCH`: comment/doc fixes, toolchain bumps without API change.
   - Keep the repo on `v1.x`: a Go module tagged `v2+` would need a `/v2` import path.
     That is why breaking API changes go into a new proto package instead.

```bash
make release VERSION=1.1.0     # on main: verify, bump package.json + pyproject.toml, commit, tag v1.1.0
git push origin main v1.1.0
```

## Upgrading the toolchain

Bump the `ARG` versions in `Dockerfile`, then keep the runtime floors in sync:
`PROTOC_GEN_ES_VERSION` ↔ `@bufbuild/protobuf` in `package.json`,
`GRPCIO_TOOLS_VERSION` ↔ `grpcio`/`protobuf` in `pyproject.toml`,
`protoc-gen-go(-grpc)` ↔ `google.golang.org/{protobuf,grpc}` in `go.mod`. The `go`
directive in `go.mod` is the minimum Go version for consumers (kept low on purpose)
and is independent of `GO_VERSION` in the Dockerfile. Then `make init generate` and commit.

## License

[MIT](LICENSE)
