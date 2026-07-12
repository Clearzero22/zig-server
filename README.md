# Zig Server

A minimal yet expressive web framework for **Zig 0.16.0**, built on `std.http.Server`. Features routing, middleware, CORS, thread pool, and OpenAPI/Swagger documentation.

## Quick Start

```bash
git clone <repo> && cd zig-server
zig build
zig build run
# → Listening on 0.0.0.0:8080
```

## How to Use as a Library

### Option 1: Zig Package Manager (推荐)

在项目根目录运行：

```bash
zig fetch --save https://github.com/Clearzero22/zig-server/archive/master.tar.gz
```

这会自动添加依赖到你的 `build.zig.zon`。然后在 `build.zig` 中：

```zig
const exe = b.addExecutable(.{ .name = "my-app", .root_module = b.createModule(...) });
const zs = b.dependency("zig_server", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zig-server", zs.module("zig-server"));
```

代码中：

```zig
const fw = @import("zig-server");
var router = fw.Router.init(allocator);
```

### Option 2: Git Submodule

```bash
git submodule add https://github.com/Clearzero22/zig-server.git lib/zig-server
```

```zig
// 直接相对路径导入
const fw = @import("lib/zig-server/src/framework.zig");
```

## Example

```zig
const std = @import("std");
const fw = @import("framework.zig");

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.get("/hello", helloHandler);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.init(io, &router);
    try server.listen("0.0.0.0:8080");
}

fn helloHandler(ctx: *fw.Context) !void {
    try ctx.text(.ok, "Hello, World!");
}
```

## Routing

```zig
// Static
router.get("/users", listHandler);

// Path parameters
router.get("/users/:id", userHandler);

// Optional parameters
router.get("/users/:id?", userOptionalHandler);

// Wildcard
router.get("/static/*path", staticHandler);

// Regex
router.get("/users/(\\d+)", userByIdHandler);       // digits only
router.get("/users/(\\w+)", userBySlugHandler);      // word chars

// Multiple params in one segment
router.get("/files/:dir+:name", fileHandler);

// Route groups
var api = router.group("/api/v1");
api.get("/users", apiUsersHandler);
api.post("/users", apiCreateUserHandler);

// Named routes with reverse routing
router.getOpts("/users/:id/posts/:pid", postHandler, .{ .name = "post" });
const url = try router.url("post", .{ .id = "42", .pid = "1" });
// → "/users/42/posts/1"

// Route priorities (higher = checked first)
router.getOpts("/special", specialHandler, .{ .priority = 10 });

// Custom matchers (host, headers)
router.getOpts("/admin", adminHandler, .{
    .host = "admin.example.com",
    .headers = &.{.{"x-api-key", "secret"}},
});

// Conflict detection (same method + path → error.RouteConflict)
```

## HTTP Methods

Each route method accepts an `Opts` variant with `RouteOptions`:

| Shortcut | Opts Variant | Description |
|----------|-------------|-------------|
| `get`    | `getOpts`   | GET        |
| `post`   | `postOpts`  | POST       |
| `put`    | `putOpts`   | PUT        |
| `delete` | `deleteOpts`| DELETE     |
| `patch`  | `patchOpts` | PATCH      |

## RouteOptions

```zig
pub const RouteOptions = struct {
    name: ?[]const u8 = null,
    priority: i32 = 0,
    host: ?[]const u8 = null,
    headers: ?[]const HeaderMatch = null,

    // OpenAPI metadata
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    tags: ?[]const u8 = null,
    deprecated: bool = false,
    body_type: ?[]const u8 = null,
    response_type: ?[]const u8 = null,
};
```

## Middleware

```zig
// Global middleware
try router.use(logger.handler);
try router.use(authMiddleware);

// Error handler
router.onError(recovery.handler);

// Middleware signature: fn(ctx: *Context) anyerror!bool
// Return false to short-circuit the chain.
```

### Built-in Middleware

| Module | File | Description |
|--------|------|-------------|
| Logger | `builtins/logger.zig` | Request logging to stdout |
| Recovery | `builtins/recovery.zig` | Panic recovery with 500 response |
| CORS | `builtins/cors.zig` | Cross-Origin Resource Sharing |

## Context API

```zig
// Response helpers
try ctx.text(.ok, "plain text");
try ctx.json(.ok, "{\"key\": \"value\"}");
try ctx.jsonTyped(allocator, .ok, .{ .name = "Zig" });
try ctx.html(.ok, "<h1>Hello</h1>");
try ctx.redirect(.found, "/new-location");

// Request body
const body = try ctx.readBody();
defer ctx.allocator.free(body);

// Parameters
const id = ctx.params.get("id") orelse "unknown";
const q = ctx.query.get("q") orelse "";
```

## Server

```zig
// Thread-per-connection
var server = try fw.Server.init(io, &router);

// Thread pool (configurable worker count)
var server = try fw.Server.initPool(io, &router, 4);

try server.listen("0.0.0.0:8080");
// Graceful shutdown via server.shutdown()
```

## OpenAPI / Swagger

```zig
const swagger = @import("builtins/swagger.zig");

// Set API info
try router.setOpenApiInfo("My API", "1.0.0", "Description");

// Register endpoints
swagger.init(&router);
try router.get("/docs", swagger.docsHandler);
try router.get("/openapi.json", swagger.openapiHandler);
```

Now visit `http://localhost:8080/docs` for the Swagger UI.

OpenAPI metadata can be attached per route:

```zig
try router.postOpts("/echo", echoHandler, .{
    .summary = "Echo request",
    .description = "Returns the request body as-is",
    .tags = "echo,testing",
    .body_type = "EchoRequest",
    .response_type = "EchoResponse",
});
```

## Project Structure

```
src/
├── framework.zig      — Public API facade
├── router.zig         — Router, Route, Group, RouteOptions, OpenAPI
├── context.zig        — Request context, response helpers
├── server.zig         — TCP server, accept loop, graceful shutdown
├── threadpool.zig     — Thread pool worker pool
├── dispatch.zig       — Shared dispatch logic
├── middleware.zig     — Middleware type definition
├── main.zig           — Example application
├── builtins/
│   ├── cors.zig       — CORS middleware
│   ├── logger.zig     — Request logger middleware
│   ├── recovery.zig   — Panic recovery error handler
│   └── swagger.zig    — Swagger UI + OpenAPI handler
└── *test.zig          — Test files
```

## Build & Test

```bash
zig build            # Build the server
zig build run        # Build & run on 0.0.0.0:8080
zig build test       # Run all tests
zig test src/router.test.zig  # Run router tests only
```

## Requirements

- Zig 0.16.0

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the full feature status.
