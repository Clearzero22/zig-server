const std = @import("std");
const fw = @import("zig-server");

const H = struct {
    pub fn api(_: *fw.Context) !void {}
    pub fn admin(_: *fw.Context) !void {}
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.getOpts("/api", H.api, .{
        .host = "api.example.com",
    });
    try router.getOpts("/admin", H.admin, .{
        .host = "admin.example.com",
    });
    try router.getOpts("/data", H.api, .{
        .headers = &.{.{
            .name = "x-version",
            .value = "2",
        }},
    });

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌──────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 10_custom_matchers — 自定义匹配器                       │\n", .{});
    std.debug.print("├──────────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                          │\n", .{});
    std.debug.print("│  Host 匹配:                                              │\n", .{});
    std.debug.print("│   GET /api    → 仅匹配 Host: api.example.com             │\n", .{});
    std.debug.print("│   GET /admin  → 仅匹配 Host: admin.example.com           │\n", .{});
    std.debug.print("│                                                          │\n", .{});
    std.debug.print("│  Header 匹配:                                            │\n", .{});
    std.debug.print("│   GET /data   → 仅匹配 X-Version: 2                      │\n", .{});
    std.debug.print("│                                                          │\n", .{});
    std.debug.print("│  curl -H 'Host: api.example.com' \\                       │\n", .{});
    std.debug.print("│    http://localhost:8010/api                             │\n", .{});
    std.debug.print("│  curl -H 'Host: admin.example.com' \\                     │\n", .{});
    std.debug.print("│    http://localhost:8010/admin                           │\n", .{});
    std.debug.print("│  curl -H 'X-Version: 2' http://localhost:8010/data       │\n", .{});
    std.debug.print("│                                                          │\n", .{});
    std.debug.print("└──────────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8010");
}
