const std = @import("std");
const fw = @import("zig-server");

fn noopHandler(_: *fw.Context) !void {}

fn nanos() i64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    return @as(i64, @intCast(ts.sec)) * 1_000_000_000 + @as(i64, @intCast(ts.nsec));
}

fn bench(label: []const u8, path: []const u8, router: *fw.Router, method: fw.Router.Method, iterations: usize) void {
    const p = if (std.mem.indexOfScalar(u8, path, '?')) |i| path[0..i] else path;
    const start = nanos();
    for (0..iterations) |_| {
        _ = router.match(method, p);
    }
    const elapsed = nanos() - start;
    const ns_per_op_i64 = @divTrunc(elapsed, @as(i64, @intCast(iterations)));
    const ns_per_op: usize = @intCast(@max(ns_per_op_i64, 0));
    const rps = if (ns_per_op > 0) 1_000_000_000 / ns_per_op else 0;
    std.debug.print("  {s:>22}  {d:>6} ns/op  {d:>10} req/s\n", .{ label, ns_per_op, rps });
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    const handlers = struct {
        fn h(_: *fw.Context) !void {}
    };

    try router.get("/", handlers.h);
    try router.get("/users", handlers.h);
    try router.get("/users/:id", handlers.h);
    try router.get("/users/:id/posts", handlers.h);
    try router.get("/users/:id/posts/:postId", handlers.h);
    try router.get("/posts/:id/comments/:cid", handlers.h);
    try router.get("/api/v1/products", handlers.h);
    try router.get("/api/v1/products/:id", handlers.h);
    try router.get("/api/v1/products/:id/variants", handlers.h);
    try router.get("/api/v1/products/:id/variants/:vid", handlers.h);
    try router.get("/search", handlers.h);
    try router.get("/static/*path", handlers.h);
    try router.post("/api/v1/products", handlers.h);
    try router.put("/api/v1/products/:id", handlers.h);
    try router.patch("/api/v1/products/:id", handlers.h);
    try router.delete("/api/v1/products/:id", handlers.h);

    const method = fw.Router.Method.GET;
    const N: usize = 1_000_000;

    // warmup
    _ = router.match(method, "/");
    _ = router.match(method, "/users/42");

    std.debug.print("\n  Routing Benchmark (Zig {s})\n", .{"0.16.0"});
    std.debug.print("  {s:>22}  {s:>8}  {s:>10}\n", .{"route", "ns/op", "req/s"});
    std.debug.print("  {s:>22}  {s:>8}  {s:>10}\n", .{"----------------------", "------", "----------"});

    bench("Static '/'", "/", &router, method, N);
    bench("Static '/users'", "/users", &router, method, N);
    bench("Param '/users/42'", "/users/42", &router, method, N);
    bench("Mixed '/u/42/posts'", "/users/42/posts", &router, method, N);
    bench("Deep '/u/42/p/99'", "/users/42/posts/99", &router, method, N);
    bench("Deep '/posts/7/c/3'", "/posts/7/comments/3", &router, method, N);
    bench("Static '/api/v1/products'", "/api/v1/products", &router, method, N);
    bench("Deep '/api/.../456'", "/api/v1/products/123/variants/456", &router, method, N);
    bench("Miss '/not-found'", "/not-found", &router, method, N);
    bench("Wildcard '/static/...'", "/static/css/main.css", &router, method, N);

    std.debug.print("\n", .{});
}
