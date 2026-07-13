const std = @import("std");
const fw = @import("zig-server");

const H = struct {
    pub fn login(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"token\":\"abc\"}"); }
    pub fn posts(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"posts\":[]}"); }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    // 3 requests per 60s — easy to test
    try router.postOpts("/login", H.login, .{ .rate_limit = .{ .max_requests = 3, .window_ms = 60_000 } });
    try router.get("/posts", H.posts);
    try router.postOpts("/posts", H.posts, .{ .rate_limit = .{ .max_requests = 5, .window_ms = 60_000 } });

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌─────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 05_rate_limit — 路由级限流                             │\n", .{});
    std.debug.print("├─────────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                         │\n", .{});
    std.debug.print("│  POST /login  → 3 req / 60s                            │\n", .{});
    std.debug.print("│  POST /posts  → 5 req / 60s                            │\n", .{});
    std.debug.print("│  GET  /posts  → 不限流                                 │\n", .{});
    std.debug.print("│                                                         │\n", .{});
    std.debug.print("│  连续请求 4 次看 429 Too Many Requests:                 │\n", .{});
    std.debug.print("│  for i in 1 2 3 4; do                                  │\n", .{});
    std.debug.print("│    curl -s -X POST http://localhost:8005/login -w        │\n", .{});
    std.debug.print("│      ' → HTTP %{{http_code}}\\n'                         │\n", .{});
    std.debug.print("│  done                                                   │\n", .{});

    std.debug.print("│                                                         │\n", .{});
    std.debug.print("└─────────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8005");
}
