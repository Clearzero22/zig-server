const std = @import("std");
const fw = @import("zig-server");

fn repeatString(allocator: std.mem.Allocator, s: []const u8, n: usize) ![]u8 {
    var list = std.ArrayList(u8).empty;
    errdefer list.deinit(allocator);
    for (0..n) |_| {
        try list.appendSlice(allocator, s);
    }
    return list.items;
}

fn makeJson(allocator: std.mem.Allocator) ![]u8 {
    var list = std.ArrayList(u8).empty;
    errdefer list.deinit(allocator);
    try list.appendSlice(allocator, "{\"message\":\"Hello, World!\",\"items\":[");
    for (0..99) |_| {
        try list.appendSlice(allocator, "0,");
    }
    try list.appendSlice(allocator, "0],\"nested\":{\"foo\":\"bar\",\"count\":42}}");
    return list.items;
}

const H = struct {
    pub fn textHandler(ctx: *fw.Context) !void {
        const body = "Hello, World! This is a plain text response. ";
        const repeated = try repeatString(ctx.allocator, body, 100);
        defer ctx.allocator.free(repeated);
        try ctx.text(.ok, repeated);
    }

    pub fn jsonHandler(ctx: *fw.Context) !void {
        const data = try makeJson(ctx.allocator);
        defer ctx.allocator.free(data);
        try ctx.json(.ok, data);
    }

    pub fn gzipTextHandler(ctx: *fw.Context) !void {
        const body = "Hello, World! This is a plain text response. ";
        const repeated = try repeatString(ctx.allocator, body, 100);
        defer ctx.allocator.free(repeated);
        try ctx.gzipText(.ok, repeated);
    }

    pub fn gzipJsonHandler(ctx: *fw.Context) !void {
        const data = try makeJson(ctx.allocator);
        defer ctx.allocator.free(data);
        try ctx.gzipJson(.ok, data);
    }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.get("/text", H.textHandler);
    try router.get("/json", H.jsonHandler);
    try router.get("/gzip-text", H.gzipTextHandler);
    try router.get("/gzip-json", H.gzipJsonHandler);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 18_compression -- Gzip Compression Demo                   │\n", .{});
    std.debug.print("├────────────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("│  GET /text       -> Uncompressed text (~2.7KB)            │\n", .{});
    std.debug.print("│  GET /json       -> Uncompressed JSON (~2KB)              │\n", .{});
    std.debug.print("│  GET /gzip-text  -> Gzip compressed text                  │\n", .{});
    std.debug.print("│  GET /gzip-json  -> Gzip compressed JSON                  │\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("│  curl -H 'Accept-Encoding: gzip'                           │\n", .{});
    std.debug.print("│    http://localhost:8018/gzip-text --output - | wc -c     │\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("└────────────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8018");
}
