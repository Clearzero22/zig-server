const std = @import("std");
const fw = @import("zig-server");

const Ctrl = struct {
    pub fn v1users(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"version\":\"v1\",\"users\":[\"alice\",\"bob\"]}"); }
    pub fn v2users(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"version\":\"v2\",\"users\":[{\"name\":\"alice\"},{\"name\":\"bob\"}]}"); }
    pub fn v1posts(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"version\":\"v1\",\"posts\":[]}"); }
    pub fn v2posts(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"version\":\"v2\",\"posts\":[],\"total\":0}"); }
    pub fn v2create(ctx: *fw.Context) !void { try ctx.json(.created, "{\"version\":\"v2\",\"created\":true}"); }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    var v1 = router.group("/api/v1");
    try v1.get("/users", Ctrl.v1users);
    try v1.get("/posts", Ctrl.v1posts);

    var v2 = router.group("/api/v2");
    try v2.get("/users", Ctrl.v2users);
    try v2.get("/posts", Ctrl.v2posts);
    try v2.post("/posts", Ctrl.v2create);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌───────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 06_version — API 版本共存                         │\n", .{});
    std.debug.print("├───────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                   │\n", .{});
    std.debug.print("│  v1: /api/v1/users, /api/v1/posts                 │\n", .{});
    std.debug.print("│  v2: /api/v2/users, /api/v2/posts (增强格式)       │\n", .{});
    std.debug.print("│                                                   │\n", .{});
    std.debug.print("│  curl http://localhost:8006/api/v1/users           │\n", .{});
    std.debug.print("│  curl http://localhost:8006/api/v2/users           │\n", .{});
    std.debug.print("│  curl http://localhost:8006/api/v2/posts           │\n", .{});
    std.debug.print("│  curl -X POST http://localhost:8006/api/v2/posts   │\n", .{});
    std.debug.print("│                                                   │\n", .{});
    std.debug.print("└───────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8006");
}
