const std = @import("std");
const fw = @import("framework.zig");
const logger = @import("builtins/logger.zig");
const recovery = @import("builtins/recovery.zig");

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    router.onError(recovery.handler);

    try router.use(logger.handler);
    try router.use(auth);

    try router.get("/", helloHandler);
    try router.get("/json", jsonHandler);
    try router.get("/search", searchHandler);
    try router.get("/admin", adminHandler);
    try router.get("/users/:id", userHandler);
    try router.get("/users/:id/posts/:pid", postHandler);
    try router.post("/echo", echoHandler);
    try router.get("/error", errorHandler);

    var api = router.group("/api/v1");
    try api.get("/hello", apiHelloHandler);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = fw.Server.init(io, &router);
    try server.listen("0.0.0.0:8080");
}

fn auth(ctx: *fw.Context) !bool {
    if (std.mem.startsWith(u8, ctx.request.head.target, "/admin")) {
        try ctx.text(.forbidden, "Forbidden");
        return false;
    }
    return true;
}

fn helloHandler(ctx: *fw.Context) !void {
    try ctx.text(.ok, "Hello, World!");
}

fn jsonHandler(ctx: *fw.Context) !void {
    try ctx.json(.ok, "{\"message\": \"Hello, JSON!\"}");
}

fn searchHandler(ctx: *fw.Context) !void {
    const q = ctx.query.get("q") orelse "";
    try ctx.jsonTyped(ctx.allocator, .ok, .{
        .query = q,
        .results = [_]u8{},
    });
}

fn adminHandler(ctx: *fw.Context) !void {
    try ctx.text(.ok, "Admin Panel");
}

fn userHandler(ctx: *fw.Context) !void {
    const id = ctx.params.get("id") orelse "unknown";
    try ctx.jsonTyped(ctx.allocator, .ok, .{ .id = id });
}

fn postHandler(ctx: *fw.Context) !void {
    const id = ctx.params.get("id") orelse "unknown";
    const pid = ctx.params.get("pid") orelse "unknown";
    try ctx.jsonTyped(ctx.allocator, .ok, .{ .id = id, .pid = pid });
}

fn echoHandler(ctx: *fw.Context) !void {
    const body = try ctx.readBody();
    defer ctx.allocator.free(body);
    try ctx.json(.ok, body);
}

fn errorHandler(_: *fw.Context) !void {
    return error.SomethingBad;
}

fn apiHelloHandler(ctx: *fw.Context) !void {
    try ctx.json(.ok, "{\"version\":\"v1\"}");
}
