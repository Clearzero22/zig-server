const std = @import("std");
const http = std.http;

pub const Param = struct { key: []const u8, value: []const u8 };

pub const MAX_PARAMS: usize = 16;

pub const Params = struct {
    items: [MAX_PARAMS]Param = undefined,
    len: usize = 0,

    pub fn get(self: *const Params, key: []const u8) ?[]const u8 {
        for (self.items[0..self.len]) |p| {
            if (std.mem.eql(u8, p.key, key)) return p.value;
        }
        return null;
    }
};

pub const QueryParams = Params;

io: std.Io,
allocator: std.mem.Allocator,
request: *http.Server.Request,
params: Params = .{},
query: QueryParams = .{},
cors_origin: ?[]const u8 = null,
max_body_size: usize = 10 * 1024 * 1024,
db: ?*anyopaque = null,

pub fn json(ctx: *@This(), status: http.Status, data: []const u8) !void {
    try respondExtra(ctx, data, .{
        .status = status,
        .keep_alive = false,
    }, &.{
        http.Header{ .name = "content-type", .value = "application/json" },
    });
}

pub fn jsonTyped(ctx: *@This(), allocator: std.mem.Allocator, status: http.Status, value: anytype) !void {
    const data = try std.json.Stringify.valueAlloc(allocator, value, .{});
    defer allocator.free(data);
    try respondExtra(ctx, data, .{
        .status = status,
        .keep_alive = false,
    }, &.{
        http.Header{ .name = "content-type", .value = "application/json" },
    });
}

pub fn text(ctx: *@This(), status: http.Status, body: []const u8) !void {
    try respondExtra(ctx, body, .{
        .status = status,
        .keep_alive = false,
    }, &.{});
}

pub fn html(ctx: *@This(), status: http.Status, body: []const u8) !void {
    try respondExtra(ctx, body, .{
        .status = status,
        .keep_alive = false,
    }, &.{
        http.Header{ .name = "content-type", .value = "text/html; charset=utf-8" },
    });
}

pub fn internalError(ctx: *@This(), _: anyerror) !void {
    try respondExtra(ctx, "{\"error\":\"Internal Server Error\",\"status\":500}", .{
        .status = .internal_server_error,
        .keep_alive = false,
    }, &.{
        http.Header{ .name = "content-type", .value = "application/json" },
    });
}

pub fn readBody(ctx: *@This()) ![]const u8 {
    const len = ctx.request.head.content_length orelse return error.BodyRequired;
    if (len > ctx.max_body_size) return error.BodyTooLarge;
    var transfer_buf: [8192]u8 = undefined;
    const body_reader = ctx.request.server.reader.bodyReader(
        &transfer_buf,
        ctx.request.head.transfer_encoding,
        len,
    );
    return try body_reader.readAlloc(ctx.allocator, len);
}

pub fn redirect(ctx: *@This(), status: http.Status, url: []const u8) !void {
    try respondExtra(ctx, "", .{
        .status = status,
        .keep_alive = false,
    }, &.{
        http.Header{ .name = "location", .value = url },
    });
}

fn respondExtra(ctx: *@This(), data: []const u8, opts: anytype, extra: []const http.Header) !void {
    const has_cors = ctx.cors_origin != null;
    var buf: [24]http.Header = undefined;
    var n: usize = 0;

    if (has_cors) {
        buf[n] = .{ .name = "access-control-allow-origin", .value = ctx.cors_origin.? };
        n += 1;
    }
    for (extra) |h| {
        buf[n] = h;
        n += 1;
    }

    try ctx.request.respond(data, .{
        .status = opts.status,
        .keep_alive = false,
        .extra_headers = buf[0..n],
    });
}
