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
extra_header_buf: [8]http.Header = undefined,
extra_header_count: usize = 0,
request_id: ?[]const u8 = null,
deadline: i64 = 0,

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

pub fn readJson(ctx: *@This(), comptime T: type) !T {
    const body = try ctx.readBody();
    defer ctx.allocator.free(body);
    return try std.json.parseFromSliceLeaky(T, ctx.allocator, body, .{});
}

pub fn redirect(ctx: *@This(), status: http.Status, url: []const u8) !void {
    try respondExtra(ctx, "", .{
        .status = status,
        .keep_alive = false,
    }, &.{
        http.Header{ .name = "location", .value = url },
    });
}

pub fn noContent(ctx: *@This()) !void {
    try respondExtra(ctx, "", .{
        .status = .no_content,
        .keep_alive = false,
    }, &.{});
}

pub fn sendFile(ctx: *@This(), path: []const u8) !void {
    const file = std.Io.Dir.openFile(.cwd(), ctx.io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ctx.text(.not_found, "Not Found"),
        else => return err,
    };
    defer file.close(ctx.io);

    const stat = try file.stat(ctx.io);
    if (stat.size > ctx.max_body_size) {
        const msg = "File too large";
        try respondExtra(ctx, msg, .{
            .status = .payload_too_large,
            .keep_alive = false,
        }, &.{});
        return;
    }
    const data = try ctx.allocator.alloc(u8, @as(usize, @intCast(stat.size)));
    defer ctx.allocator.free(data);
    _ = try file.readPositionalAll(ctx.io, data, 0);

    const mime = mimeType(std.fs.path.extension(path));

    try respondExtra(ctx, data, .{
        .status = .ok,
        .keep_alive = false,
    }, &.{
        http.Header{ .name = "content-type", .value = mime },
    });
}

fn mimeType(ext: []const u8) []const u8 {
    if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
    if (std.mem.eql(u8, ext, ".js")) return "application/javascript";
    if (std.mem.eql(u8, ext, ".json")) return "application/json";
    if (std.mem.eql(u8, ext, ".png")) return "image/png";
    if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, ".gif")) return "image/gif";
    if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, ".ico")) return "image/x-icon";
    if (std.mem.eql(u8, ext, ".woff2")) return "font/woff2";
    if (std.mem.eql(u8, ext, ".woff")) return "font/woff";
    if (std.mem.eql(u8, ext, ".ttf")) return "font/ttf";
    if (std.mem.eql(u8, ext, ".txt")) return "text/plain; charset=utf-8";
    if (std.mem.eql(u8, ext, ".xml")) return "application/xml";
    if (std.mem.eql(u8, ext, ".pdf")) return "application/pdf";
    if (std.mem.eql(u8, ext, ".wasm")) return "application/wasm";
    if (std.mem.eql(u8, ext, ".map")) return "application/json";
    return "application/octet-stream";
}

pub fn header(ctx: *@This(), name: []const u8, value: []const u8) !void {
    if (ctx.extra_header_count >= 8) return error.TooManyHeaders;
    ctx.extra_header_buf[ctx.extra_header_count] = .{ .name = name, .value = value };
    ctx.extra_header_count += 1;
}

fn respondExtra(ctx: *@This(), data: []const u8, opts: anytype, extra: []const http.Header) !void {
    const has_cors = ctx.cors_origin != null;
    var buf: [32]http.Header = undefined;
    var n: usize = 0;

    if (has_cors) {
        buf[n] = .{ .name = "access-control-allow-origin", .value = ctx.cors_origin.? };
        n += 1;
    }
    for (ctx.extra_header_buf[0..ctx.extra_header_count]) |h| {
        buf[n] = h;
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
