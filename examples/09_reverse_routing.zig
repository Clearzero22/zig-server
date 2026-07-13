const std = @import("std");
const fw = @import("zig-server");

const H = struct {
    pub fn user(ctx: *fw.Context) !void {
        try ctx.jsonTyped(ctx.allocator, .ok, .{ .id = ctx.params.get("id"), .action = "show" });
    }
    pub fn createUser(_: *fw.Context) !void {}
    pub fn listPosts(_: *fw.Context) !void {}
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.getOpts("/users/:id", H.user, .{ .name = "user.show" });
    try router.postOpts("/users", H.createUser, .{ .name = "user.create" });
    try router.getOpts("/posts", H.listPosts, .{ .name = "posts.list" });

    var admin = router.group("/admin");
    try admin.getOpts("/users/:id", H.user, .{ .name = "admin.user.show" });

    router.lock();

    const examples = [_]struct { name: []const u8, url: []const u8 }{
        .{ .name = "user.show", .url = try router.url("user.show", .{ .id = "42" }) },
        .{ .name = "user.create", .url = try router.url("user.create", .{}) },
        .{ .name = "posts.list", .url = try router.url("posts.list", .{}) },
        .{ .name = "admin.user.show", .url = try router.url("admin.user.show", .{ .id = "7" }) },
    };
    defer for (examples) |ex| allocator.free(ex.url);

    std.debug.print("\n", .{});
    std.debug.print("┌──────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 09_reverse_routing — 反向路由                │\n", .{});
    std.debug.print("├──────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                              │\n", .{});
    for (examples) |ex| {
        std.debug.print("│  {s:<30} → {s:>20}  │\n", .{ ex.name, ex.url });
    }
    std.debug.print("│                                              │\n", .{});
    std.debug.print("│  curl http://localhost:8009/users/42          │\n", .{});
    std.debug.print("│                                              │\n", .{});
    std.debug.print("└──────────────────────────────────────────────┘\n", .{});

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);
    try server.listen("0.0.0.0:8009");
}
