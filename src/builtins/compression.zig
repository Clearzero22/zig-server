const std = @import("std");
const http = std.http;
const Context = @import("../context.zig");
const Middleware = @import("../middleware.zig").Middleware;
const AfterMiddleware = @import("../middleware.zig").AfterMiddleware;
const flate = std.compress.flate;

pub fn gzipCompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (data.len == 0) return &.{};

    var allocating = try std.Io.Writer.Allocating.initCapacity(allocator, data.len + 64);
    defer allocating.deinit();

    var scratch: [flate.max_window_len]u8 = undefined;
    var compress = try flate.Compress.init(
        &allocating.writer,
        &scratch,
        .gzip,
        .default,
    );
    try compress.writer.writeAll(data);
    try compress.finish();

    var list = allocating.toArrayList();
    const result = try allocator.alloc(u8, list.items.len);
    @memcpy(result, list.items);
    list.deinit(allocator);
    return result;
}

pub fn handler(ctx: *Context) !bool {
    var accepts_gzip = false;
    var it = ctx.request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "accept-encoding")) {
            var parts = std.mem.splitScalar(u8, h.value, ',');
            while (parts.next()) |part| {
                const enc = std.mem.trim(u8, part, " ");
                if (std.mem.eql(u8, enc, "gzip") or std.mem.eql(u8, enc, "*")) {
                    accepts_gzip = true;
                }
            }
        }
    }

    if (accepts_gzip) {
        ctx.response_capture = .{ .data = .empty };
    }
    return true;
}

pub fn afterHandler(ctx: *Context) void {
    const rc = ctx.response_capture orelse return;
    defer {
        rc.data.deinit();
        ctx.response_capture = null;
    }

    if (rc.data.items.len == 0) return;

    const compressed = gzipCompress(ctx.allocator, rc.data.items) catch return;

    var rc_content_type = rc.content_type;
    for (ctx.extra_header_buf[0..ctx.extra_header_count]) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "content-type")) {
            rc_content_type = h.value;
        }
    }

    var hdrs: [3]http.Header = undefined;
    var n: usize = 0;
    hdrs[n] = .{ .name = "content-encoding", .value = "gzip" };
    n += 1;
    if (rc_content_type) |ct| {
        hdrs[n] = .{ .name = "content-type", .value = ct };
        n += 1;
    }
    if (ctx.cors_origin) |origin| {
        hdrs[n] = .{ .name = "access-control-allow-origin", .value = origin };
        n += 1;
    }

    ctx.request.respond(compressed, .{
        .status = rc.status,
        .keep_alive = ctx.request.head.keep_alive,
        .extra_headers = hdrs[0..n],
    }) catch {};
    ctx.allocator.free(compressed);
}
