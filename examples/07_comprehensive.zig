const std = @import("std");
const fw = @import("zig-server");

fn getHeader(req: *const std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = req.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
    }
    return null;
}

fn adminAuth(ctx: *fw.Context) !bool {
    const auth = getHeader(ctx.request, "authorization") orelse {
        try ctx.text(.forbidden, "Forbidden");
        return false;
    };
    if (!std.ascii.eqlIgnoreCase(auth, "Bearer admin-secret")) {
        try ctx.text(.forbidden, "Forbidden");
        return false;
    }
    return true;
}

const H = struct {
    pub fn health(ctx: *fw.Context) !void { try ctx.text(.ok, "OK"); }

    pub fn dlist(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"users\":[{\"id\":1,\"name\":\"alice\"}]}"); }
    pub fn dshow(ctx: *fw.Context) !void {
        const id = ctx.params.get("id") orelse "?";
        try ctx.json(.ok, try std.fmt.allocPrint(ctx.allocator, "{{\"user\":{{\"id\":{s}}}}}", .{id}));
    }
    pub fn dcreate(ctx: *fw.Context) !void {
        const body = try ctx.readBody();
        defer ctx.allocator.free(body);
        try ctx.json(.created, try std.fmt.allocPrint(ctx.allocator, "{{\"created\":{s}}}", .{body}));
    }

    pub fn plist(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"posts\":[]}"); }
    pub fn pcreate(ctx: *fw.Context) !void { try ctx.json(.created, "{\"created\":true}"); }

    pub fn v1data(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"version\":\"v1\"}"); }
    pub fn v2data(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"version\":\"v2\",\"upgraded\":true}"); }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    // 公开
    try router.get("/healthz", H.health);
    try router.get("/api/v1/data", H.v1data);

    // Admin 子路由 + resource + middleware
    var admin = fw.Router.init(allocator);
    defer admin.deinit();
    try admin.use(adminAuth);
    try admin.resource("/users", .{ .list = H.dlist, .show = H.dshow, .create = H.dcreate });
    try router.mount("/admin", &admin);

    // API v2 group + CORS + rate limit
    var v2 = router.group("/api/v2");
    try v2.get("/data", H.v2data);
    try v2.get("/posts", H.plist);
    try v2.postOpts("/posts", H.pcreate, .{
        .cors_origin = "https://blog.example.com",
        .rate_limit  = .{ .max_requests = 5, .window_ms = 60_000 },
    });

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌──────────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 07_comprehensive — 综合演示                                     │\n", .{});
    std.debug.print("├──────────────────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                                  │\n", .{});
    std.debug.print("│  GET  /healthz                   — 公开 / 无认证                  │\n", .{});
    std.debug.print("│  GET  /api/v1/data               — 公开 / v1                     │\n", .{});
    std.debug.print("│  GET  /admin/users               — auth(admin) + resource(list)  │\n", .{});
    std.debug.print("│  GET  /admin/users/:id           — auth(admin) + resource(show)  │\n", .{});
    std.debug.print("│  POST /admin/users               — auth(admin) + resource(create)│\n", .{});
    std.debug.print("│  GET  /api/v2/data               — v2 增强格式                   │\n", .{});
    std.debug.print("│  GET  /api/v2/posts              — v2                            │\n", .{});
    std.debug.print("│  POST /api/v2/posts              — CORS + rate limit(5/60s)      │\n", .{});
    std.debug.print("│                                                                  │\n", .{});
    std.debug.print("│  curl http://localhost:8007/healthz                              │\n", .{});
    std.debug.print("│  curl http://localhost:8007/admin/users                          │\n", .{});
    std.debug.print("│  curl -H 'Authorization: Bearer admin-secret' \\                  │\n", .{});
    std.debug.print("│    http://localhost:8007/admin/users                             │\n", .{});
    std.debug.print("│  curl -X POST -H 'Authorization: Bearer admin-secret' \\          │\n", .{});
    std.debug.print("│    -d '{{\"name\":\"bob\"}}' http://localhost:8007/admin/users        │\n", .{});
    std.debug.print("│                                                                  │\n", .{});
    std.debug.print("└──────────────────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8007");
}
