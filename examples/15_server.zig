const std = @import("std");
const fw = @import("zig-server");

const H = struct {
    pub fn hello(ctx: *fw.Context) !void { try ctx.text(.ok, "Hello from thread pool server"); }
    pub fn info(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"server\":\"zig-server\",\"threads\":8}"); }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.get("/hello", H.hello);
    try router.get("/info", H.info);

    const io = std.Io.Threaded.global_single_threaded.io();

    // 8 worker threads
    var server = try fw.Server.initPool(io, &router, 8);
    errdefer server.deinit();

    std.debug.print("\n", .{});
    std.debug.print("┌──────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 15_server — 服务器配置 (线程池+优雅关闭)            │\n", .{});
    std.debug.print("├──────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("│  线程池大小: 8                                       │\n", .{});
    std.debug.print("│  优雅关闭: Ctrl+C → server.shutdown()               │\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("│  curl http://localhost:8015/hello                     │\n", .{});
    std.debug.print("│  curl http://localhost:8015/info                      │\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("└──────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8015");
}
