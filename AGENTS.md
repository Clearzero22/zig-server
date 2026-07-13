# zig-server

## Build & Test

```bash
zig build
zig build test
zig test src/router.test.zig
```

Zig: `C:\Users\Administrator\zig\0.16.0\zig-x86_64-windows-0.16.0\zig.exe`

## Constraints

- `ArrayList`: `.empty` init, `.append(self, allocator, item)`
- I/O: `std.Io` (capital I), via `global_single_threaded.io()`
- JSON: `std.json.Stringify.valueAlloc(allocator, value, .{})`
- Thread pool: `std.atomic.Mutex` spinlock, `?*ThreadPool` heap-allocated
- Response: always use `respondExtra` with `keep_alive = false`
- Memory: `allocator.dupe` in addRoute, `allocator.free` in deinit
- No comments in source code
- Router owns all memory, freed in deinit

## Known Compiler Quirks

- **`@hasDecl` / `@typeInfo` cross-module bug**: When a struct type is passed as `comptime T: type` to a function in another file, `@hasDecl(T, "name")` and `@typeInfo(T).@"struct".decls` incorrectly return empty. Use `@hasField(@TypeOf(instance), "name")` instead — it works across modules because it checks fields, not declarations.
- **Affected APIs**: `resource()` uses `@hasField` with explicit handler fields (`.list = Ctrl.list, .show = Ctrl.show, ...`). Do NOT attempt to infer declarations with `@hasDecl` / `@typeInfo` across files.

## Workflow

After every code change, run the full test suite:
```bash
zig build test
```
Do not skip tests or run only partial tests unless explicitly asked.

## Structure

| File | Content |
|------|---------|
| `framework.zig` | Public facade |
| `router.zig` | Route, Router, Group, RouteOptions, OpenAPI |
| `context.zig` | Context, response helpers |
| `server.zig` | Listen/accept/shutdown |
| `threadpool.zig` | Worker pool |
| `builtins/` | cors, logger, recovery, swagger |
