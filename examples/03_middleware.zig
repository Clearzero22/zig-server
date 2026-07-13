const std = @import("std");
const fw = @import("zig-server");

fn getHeader(req: *const std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = req.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
    }
    return null;
}

fn authMiddleware(ctx: *fw.Context) !bool {
    const auth = getHeader(ctx.request, "authorization") orelse {
        try ctx.text(.forbidden, "Forbidden: missing Authorization header");
        return false;
    };
    if (!std.ascii.eqlIgnoreCase(auth, "Bearer secret-token")) {
        try ctx.text(.forbidden, "Forbidden: invalid token");
        return false;
    }
    try ctx.text(.ok, "Auth OK");
    return true;
}

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    const H = struct {
        pub fn admin(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"page\":\"admin\",\"secret\":\"data\"}"); }
        pub fn publicPage(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"page\":\"public\"}"); }
    };

    try router.get("/public", H.publicPage);
    try router.getOpts("/admin", H.admin, .{ .middleware = &.{authMiddleware} });

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌──────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 03_middleware — 路由级中间件                        │\n", .{});
    std.debug.print("├──────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("│  GET /public — 公开，无需认证                        │\n", .{});
    std.debug.print("│  GET /admin  — 需 Authorization: Bearer secret-token │\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("│  curl http://localhost:8003/public                    │\n", .{});
    std.debug.print("│  curl http://localhost:8003/admin                     │\n", .{});
    std.debug.print("│  curl -H 'Authorization: Bearer secret-token' \\      │\n", .{});
    std.debug.print("│    http://localhost:8003/admin                        │\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("└──────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8003");
}
