# grpc-apis-template

[![proto](https://github.com/longntv/grpc-apis-template/actions/workflows/ci.yml/badge.svg)](https://github.com/longntv/grpc-apis-template/actions/workflows/ci.yml)

Template for a central gRPC API repository. Protos are plain proto3 that follow the
[Google AIP](https://google.aip.dev) naming conventions (checked by `buf lint` + Google
`api-linter`), and **pre-generated stubs are committed** for Go, Node.js/TypeScript and
Python. Services pin a git tag (e.g. `v1.0.0`) and import the stubs directly: no `protoc`,
no `buf`, no codegen step on the consumer side.

## Use this template

1. Click **Use this template** on GitHub (or clone), then:

   ```bash
   make rename OWNER=my-org REPO=my-apis   # replaces longntv / grpc-apis-template everywhere
   make init generate                      # build toolchain image, regenerate gen/
   ```

2. Update the copyright holder in `LICENSE`, replace the sample `user/v1` API with your
   own, commit, then `make release VERSION=1.0.0`.
3. On GitHub: enable **Settings → Template repository** if you want to share it, and
   protect `main` with the `check` and `consumers` CI jobs as required status checks.

```
grpc-apis-template/
├── proto/longntv/user/v1/
│   ├── user.proto         # User      users/{user}
│   ├── address.proto      # Address   users/{user}/addresses/{address}
│   └── user_service.proto # UserService: Get/List/Create/Update/Delete for both
├── gen/                   # GENERATED, committed, never edit by hand
├── buf.yaml               # buf lint / breaking rules
├── api-linter.yaml        # Google api-linter (AIP) rules
├── buf.gen.go.yaml        # Go (sets go_package automatically)  -> gen/go
├── buf.gen.ts.yaml        # Node/TS (protobuf-es, js + d.ts)    -> gen/es
├── scripts/               # gen-go.sh, gen-python.sh, lint-aip.sh, rename.sh
├── Dockerfile             # pinned toolchain used by every make target
├── Makefile
├── go.mod                 # Go module   github.com/longntv/grpc-apis-template
├── package.json           # npm package @longntv/grpc-apis-template
└── pyproject.toml         # pip package longntv-grpc-apis-template
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

Generated structs carry [validator](https://github.com/go-playground/validator) tags
(see [Validation tags](#validation-tags-go)):

```go
v := validator.New(validator.WithRequiredStructEnabled())
if err := v.Struct(req); err != nil {
    return nil, status.Error(codes.InvalidArgument, err.Error())
}
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

Stubs ship as ESM `.js` + `.d.ts`, so no build step is needed. TypeScript needs
`"moduleResolution": "node16"`, `"nodenext"` or `"bundler"`. Import paths have no extension.

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

Type hints (`.pyi`) are included.

## Working on the protos (this repo)

Prerequisites: **Docker**, **git** and **GNU make**. All tools (buf, protoc plugins,
grpcio-tools, api-linter, protoc-go-inject-tag) are pinned in the `Dockerfile`.

```bash
make init        # build the toolchain image (once, and after Dockerfile changes)
make help        # list all targets
```

| Command             | What it does                                              |
|---------------------|-----------------------------------------------------------|
| `make format`       | Format `.proto` files                                     |
| `make lint`         | buf lint + Google api-linter                              |
| `make generate`     | Lint, then generate Go + Node + Python                    |
| `make gen-go` / `gen-ts` / `gen-python` | Generate a single language            |
| `make breaking`     | Breaking-change check against local `main`                |
| `make verify`       | CI check: format + lint + regenerate, fail if `gen/` is stale |
| `make release`      | Verify, bump versions, commit and tag (`VERSION=1.x.y`)   |
| `make rename`       | One-time template rename (`OWNER=... REPO=...`)           |
| `make clean`        | Delete `gen/`                                             |

`LOCAL=1 make <target>` uses tools from your `PATH` instead of Docker.
**Always commit `gen/` together with the `.proto` change**; CI fails otherwise.

### Adding a model or service

A proto file only needs `syntax`, `package` and imports; no language options
(`go_package` is set automatically from the package name):

```proto
// proto/longntv/order/v1/order.proto
syntax = "proto3";

package longntv.order.v1;

import "google/protobuf/timestamp.proto";

// An Order placed by a user.
message Order {
  // Resource name, e.g. `orders/123`. Set by the server.
  string name = 1;
  // The user who placed the order, e.g. `users/alice`.
  // @gotags: validate:"required,startswith=users/"
  string user = 2;
  // Time the order was created. Set by the server.
  google.protobuf.Timestamp create_time = 3;
}
```

Then `make format generate` and commit `proto/` + `gen/`. Use `user/v1` as the
reference for request/response shapes.

### Conventions (checked by lint)

- **Resource names** ([AIP-122](https://google.aip.dev/122)): a resource has
  `string name = 1` holding a path like `users/alice` or, for a child resource,
  `users/alice/addresses/home` (like `publishers/123/books/les-miserables`).
  Never use an `id` field. Fields that point to another resource hold its name
  (`string user = 2; // users/alice`).
- **Standard methods** (AIP-131..135): `GetX(name) → X`, `ListXs(parent, page_size,
  page_token) → ListXsResponse`, `CreateX(parent, x, x_id) → X`,
  `UpdateX(x, update_mask) → X`, `DeleteX(name) → google.protobuf.Empty`.
- **Fields**: lower_snake_case, timestamps are `google.protobuf.Timestamp` named
  `*_time`, enums start with `*_UNSPECIFIED = 0`, everything has a comment.
- **Compatibility**: never renumber or reuse a field number (`make breaking`).

Details and reasons for each disabled rule are in `buf.yaml` and `api-linter.yaml`.
See also [CONTRIBUTING.md](CONTRIBUTING.md).

### Validation tags (Go)

Add a `// @gotags:` line to a field comment; `make gen-go` turns it into a Go struct tag
([protoc-go-inject-tag](https://github.com/favadi/protoc-go-inject-tag)):

```proto
// Unique email address used to sign in.
// @gotags: validate:"required,email,max=254"
string email = 2;
```

```go
Email string `protobuf:"..." json:"email,omitempty" validate:"required,email,max=254"`
```

Any tag works (`validate`, `db`, `yaml`, ...). Tags only affect Go; validate in other
languages separately. Note that `UpdateX` requests usually carry a partial resource:
validate only the fields in `update_mask` (e.g. `v.StructPartial(req.User, fields...)`).

## Versioning & releases

1. **API version, in the proto package** (`longntv.user.v1`). Inside `v1` only
   backward-compatible changes are allowed (`make breaking` enforces it). A breaking
   redesign goes into a new package `longntv.user.v2` next to `v1`.
2. **Repo release, as a git tag** (`v1.MINOR.PATCH`), shared by the Go module, the npm
   package and the pip package. Stay on `v1.x`: a Go module `v2+` would need a `/v2`
   import path, so breaking API changes go into a new proto package instead.

```bash
make release VERSION=1.1.0     # on main: verify, bump package.json + pyproject.toml, commit, tag
git push origin main v1.1.0
```

## Upgrading the toolchain

Bump the `ARG` versions in `Dockerfile` and keep runtime floors in sync:
`PROTOC_GEN_ES_VERSION` ↔ `@bufbuild/protobuf` (`package.json`),
`GRPCIO_TOOLS_VERSION` ↔ `grpcio`/`protobuf` (`pyproject.toml`),
`protoc-gen-go(-grpc)` ↔ `go.mod`. The `go` line in `go.mod` is the minimum Go version for
consumers and is kept low on purpose. Then `make init generate` and commit.

## License

[MIT](LICENSE)
