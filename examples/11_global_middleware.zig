const std = @import("std");
const fw = @import("zig-server");

fn addTimingHeader(ctx: *fw.Context) void {
    _ = ctx;
}

const H = struct {
    pub fn hello(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"msg\":\"hello\"}"); }
    pub fn crash(_: *fw.Context) !void { return error.SomethingBad; }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    router.onError(fw.recovery.handler);
    try router.use(fw.logger.handler);
    try router.after(addTimingHeader);

    try router.get("/hello", H.hello);
    try router.get("/crash", H.crash);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌──────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 11_global_middleware — 全局中间件 + after 后处理     │\n", .{});
    std.debug.print("├──────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("│  router.use(logger.handler) — 记录所有请求           │\n", .{});
    std.debug.print("│  router.onError(recovery.handler) — panic 恢复       │\n", .{});
    std.debug.print("│  router.after(addTimingHeader) — handler 后执行      │\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("│  GET /hello — 正常返回                               │\n", .{});
    std.debug.print("│  GET /crash — 模拟 panic → 500 + 不崩溃             │\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("│  curl http://localhost:8011/hello                     │\n", .{});
    std.debug.print("│  curl http://localhost:8011/crash                     │\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("└──────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8011");
}
