const std = @import("std");
const fw = @import("zig-server");

const H = struct {
    pub fn dashboard(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"page\":\"admin/dashboard\"}"); }
    pub fn settings(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"page\":\"admin/settings\"}"); }
    pub fn users(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"page\":\"api/users\",\"users\":[]}"); }
    pub fn posts(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"page\":\"api/posts\",\"posts\":[]}"); }
    pub fn postShow(ctx: *fw.Context) !void {
        const id = ctx.params.get("id") orelse "?";
        try ctx.json(.ok, try std.fmt.allocPrint(ctx.allocator, "{{\"page\":\"api/posts\",\"id\":{s}}}", .{id}));
    }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    var admin = fw.Router.init(allocator);
    defer admin.deinit();
    try admin.get("/dashboard", H.dashboard);
    try admin.get("/settings", H.settings);
    try router.mount("/admin", &admin);

    var api = fw.Router.init(allocator);
    defer api.deinit();
    try api.get("/users", H.users);
    try api.get("/posts", H.posts);
    try api.get("/posts/:id", H.postShow);
    try router.mount("/api", &api);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌─────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 02_mount — 子路由挂载                        │\n", .{});
    std.debug.print("├─────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                             │\n", .{});
    std.debug.print("│  Admin 子路由 (/admin/*)                     │\n", .{});
    std.debug.print("│   GET /admin/dashboard                       │\n", .{});
    std.debug.print("│   GET /admin/settings                        │\n", .{});
    std.debug.print("│                                             │\n", .{});
    std.debug.print("│  API 子路由 (/api/*)                         │\n", .{});
    std.debug.print("│   GET /api/users                             │\n", .{});
    std.debug.print("│   GET /api/posts                             │\n", .{});
    std.debug.print("│   GET /api/posts/:id                         │\n", .{});
    std.debug.print("│                                             │\n", .{});
    std.debug.print("│  curl http://localhost:8002/admin/dashboard  │\n", .{});
    std.debug.print("│  curl http://localhost:8002/api/users        │\n", .{});
    std.debug.print("│  curl http://localhost:8002/api/posts/5      │\n", .{});
    std.debug.print("│                                             │\n", .{});
    std.debug.print("└─────────────────────────────────────────────┘\n", .{});
    std.debug.print("\n", .{});

    try server.listen("0.0.0.0:8002");
}
