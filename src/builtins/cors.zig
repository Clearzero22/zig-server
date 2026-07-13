const std = @import("std");
const Context = @import("../context.zig");
const http = std.http;

var config: Config = .{};

pub const Config = struct {
    allow_origins: []const []const u8 = &.{"*"},
    allow_methods: []const []const u8 = &.{"GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"},
    allow_headers: []const []const u8 = &.{"content-type", "authorization"},
    allow_credentials: bool = false,
    max_age: ?usize = null,
};

pub fn init(cfg: Config) void {
    config = cfg;
}

pub fn handler(ctx: *Context) !bool {
    const req_origin = h: {
        var it = ctx.request.iterateHeaders();
        while (it.next()) |hdr| {
            if (std.ascii.eqlIgnoreCase(hdr.name, "origin")) break :h hdr.value;
        }
        break :h null;
    };

    const origin = req_origin orelse return true;

    const matched = for (config.allow_origins) |ao| {
        if (std.mem.eql(u8, ao, "*") or std.mem.eql(u8, ao, origin)) break true;
    } else false;

    if (!matched) return true;

    if (ctx.request.head.method != .OPTIONS) {
        ctx.cors_origin = if (config.allow_origins.len > 0 and std.mem.eql(u8, config.allow_origins[0], "*")) "*" else origin;
        return true;
    }

    var hdrs: [6]http.Header = undefined;
    var n: usize = 0;

    hdrs[n] = .{ .name = "access-control-allow-origin", .value = if (config.allow_origins.len > 0 and std.mem.eql(u8, config.allow_origins[0], "*")) "*" else origin };
    n += 1;

    if (config.allow_credentials) {
        hdrs[n] = .{ .name = "access-control-allow-credentials", .value = "true" };
        n += 1;
    }

    {
        var buf: [256]u8 = undefined;
        var pos: usize = 0;
        for (config.allow_methods, 0..) |m, i| {
            if (i > 0) { buf[pos] = ','; pos += 1; buf[pos] = ' '; pos += 1; }
            @memcpy(buf[pos..][0..m.len], m);
            pos += m.len;
        }
        hdrs[n] = .{ .name = "access-control-allow-methods", .value = buf[0..pos] };
        n += 1;
    }

    {
        var buf: [256]u8 = undefined;
        var pos: usize = 0;
        for (config.allow_headers, 0..) |h, i| {
            if (i > 0) { buf[pos] = ','; pos += 1; buf[pos] = ' '; pos += 1; }
            @memcpy(buf[pos..][0..h.len], h);
            pos += h.len;
        }
        hdrs[n] = .{ .name = "access-control-allow-headers", .value = buf[0..pos] };
        n += 1;
    }

    if (config.max_age) |ma| {
        var age_buf: [16]u8 = undefined;
        hdrs[n] = .{ .name = "access-control-max-age", .value = try std.fmt.bufPrint(&age_buf, "{d}", .{ma}) };
        n += 1;
    }

    try ctx.request.respond("", .{
        .status = .no_content,
        .keep_alive = false,
        .extra_headers = hdrs[0..n],
    });
    return false;
}
