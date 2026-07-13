const std = @import("std");
const fw = @import("zig-server");

const H = struct {
    pub fn posts(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"posts\":[]}"); }
    pub fn login(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"token\":\"abc\"}"); }
    pub fn publicPage(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"public\":true}"); }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.getOpts("/api/posts", H.posts, .{ .cors_origin = "https://myapp.com" });
    try router.postOpts("/api/login", H.login, .{ .cors_origin = "https://dashboard.myapp.com" });
    try router.get("/public", H.publicPage);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌──────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 04_cors — 路由级 CORS                                       │\n", .{});
    std.debug.print("├──────────────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                              │\n", .{});
    std.debug.print("│  GET /api/posts  → Access-Control-Allow-Origin: myapp.com    │\n", .{});
    std.debug.print("│  POST /api/login → Access-Control-Allow-Origin: dashboard   │\n", .{});
    std.debug.print("│  GET /public     → 无 CORS 头                               │\n", .{});
    std.debug.print("│                                                              │\n", .{});
    std.debug.print("│  curl -I http://localhost:8004/api/posts        # 看响应头    │\n", .{});
    std.debug.print("│  curl -I -X POST http://localhost:8004/api/login             │\n", .{});
    std.debug.print("│  curl -I http://localhost:8004/public           # 没有 CORS  │\n", .{});
    std.debug.print("│                                                              │\n", .{});
    std.debug.print("└──────────────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8004");
}
