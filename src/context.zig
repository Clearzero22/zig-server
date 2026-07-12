const std = @import("std");
const http = std.http;

pub const Param = struct { key: []const u8, value: []const u8 };

pub const Params = struct {
    items: [8]Param = undefined,
    len: usize = 0,

    pub fn get(self: *const Params, key: []const u8) ?[]const u8 {
        for (self.items[0..self.len]) |p| {
            if (std.mem.eql(u8, p.key, key)) return p.value;
        }
        return null;
    }
};

io: std.Io,
request: *http.Server.Request,
params: Params = .{},

pub fn json(ctx: *@This(), status: http.Status, data: []const u8) !void {
    try ctx.request.respond(data, .{
        .status = status,
        .keep_alive = false,
        .extra_headers = &.{
            http.Header{ .name = "content-type", .value = "application/json" },
        },
    });
}

pub fn text(ctx: *@This(), status: http.Status, body: []const u8) !void {
    try ctx.request.respond(body, .{
        .status = status,
        .keep_alive = false,
    });
}

pub fn html(ctx: *@This(), status: http.Status, body: []const u8) !void {
    try ctx.request.respond(body, .{
        .status = status,
        .keep_alive = false,
        .extra_headers = &.{
            http.Header{ .name = "content-type", .value = "text/html; charset=utf-8" },
        },
    });
}

pub fn internalError(ctx: *@This(), _: anyerror) !void {
    try ctx.request.respond("{\"error\":\"Internal Server Error\"}", .{
        .status = .internal_server_error,
        .keep_alive = false,
        .extra_headers = &.{
            http.Header{ .name = "content-type", .value = "application/json" },
        },
    });
}

pub fn readBody(ctx: *@This(), allocator: std.mem.Allocator) ![]const u8 {
    var transfer_buf: [8192]u8 = undefined;
    const body_reader = ctx.request.server.reader.bodyReader(
        &transfer_buf,
        ctx.request.head.transfer_encoding,
        ctx.request.head.content_length,
    );
    const len = ctx.request.head.content_length orelse return error.BodyRequired;
    return try body_reader.readAlloc(allocator, len);
}
