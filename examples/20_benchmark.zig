const std = @import("std");
const fw = @import("zig-server");

const H = struct {
    pub fn empty(ctx: *fw.Context) !void { try ctx.noContent(); }
    pub fn textHello(ctx: *fw.Context) !void { try ctx.text(.ok, "Hello, World!"); }
    pub fn jsonHello(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"message\":\"ok\"}"); }
    pub fn param(ctx: *fw.Context) !void { try ctx.text(.ok, ctx.params.get("name") orelse ""); }
    pub fn query(ctx: *fw.Context) !void { try ctx.text(.ok, ctx.query.get("q") orelse ""); }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.get("/empty", H.empty);
    try router.get("/text", H.textHello);
    try router.get("/json", H.jsonHello);
    try router.get("/param/hello", H.param);
    try router.get("/query", H.query);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 8);
    defer server.deinit();

    std.debug.print("Benchmark server on 0.0.0.0:9000\n", .{});
    try server.listen("0.0.0.0:9000");
}
