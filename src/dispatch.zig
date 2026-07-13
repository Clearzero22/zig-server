const std = @import("std");
const Context = @import("context.zig");
const Router = @import("router.zig");

fn milliTimestamp() i64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    const sec: i64 = @intCast(ts.sec);
    const nsec: i64 = @intCast(ts.nsec);
    return sec * 1000 + @divTrunc(nsec, 1000000);
}

var rate_counters: ?*std.StringHashMap(u32) = null;
var rate_alloc: ?std.mem.Allocator = null;

fn rateLimitCheck(ctx: *Context, config: Router.RateLimitConfig) !void {
    const target = ctx.request.head.target;

    if (rate_alloc == null) rate_alloc = ctx.allocator;
    const alloc = rate_alloc.?;

    if (rate_counters == null) {
        const m = try alloc.create(std.StringHashMap(u32));
        m.* = std.StringHashMap(u32).init(alloc);
        rate_counters = m;
    }
    const counters = rate_counters.?;

    const entry = counters.getPtr(target);
    if (entry) |e| {
        e.* += 1;
        if (e.* > config.max_requests) {
            try ctx.text(.too_many_requests, "Rate limit exceeded");
            return error.RateLimited;
        }
    } else {
        const key = try alloc.dupe(u8, target);
        try counters.put(key, 1);
    }
}

pub fn handleConnection(io: std.Io, router: *Router, conn: std.Io.net.Stream) void {
    defer conn.close(io);

    var read_buf: [8192]u8 = undefined;
    var write_buf: [4096]u8 = undefined;

    var reader = conn.reader(io, &read_buf);
    var writer = conn.writer(io, &write_buf);

    var http_server = std.http.Server.init(&reader.interface, &writer.interface);

    while (true) {
        var request = http_server.receiveHead() catch return;

        var ctx = Context{
            .io = io,
            .allocator = router.allocator,
            .request = &request,
        };

        dispatch(&ctx, router);
    }
}

pub fn dispatch(ctx: *Context, router: *Router) void {
    if (router.error_handler) |on_err| {
        dispatchInner(ctx, router) catch {
            on_err(ctx) catch {};
        };
    } else {
        dispatchInner(ctx, router) catch {};
    }
}

pub fn handle(ctx: *Context, router: *Router) void {
    dispatch(ctx, router);
}

pub fn dispatchInner(ctx: *Context, router: *Router) !void {
    const target = ctx.request.head.target;
    const path = pathOnly(target);
    parseQuery(target, &ctx.query);

    const method = Router.Method.fromHttp(ctx.request.head.method) orelse {
        try ctx.text(.method_not_allowed, "Method Not Allowed");
        return;
    };

    const match_result = router.match(method, path) orelse {
        try ctx.text(.not_found, "Not Found");
        return;
    };

    ctx.params = match_result.params;
    ctx.db = router.db;

    if (match_result.cors_origin) |origin| {
        ctx.cors_origin = origin;
    }

    for (router.middleware.items) |mw| {
        if (!try mw(ctx)) return;
    }

    for (match_result.middleware) |mw| {
        if (!try mw(ctx)) return;
    }

    if (match_result.rate_limit) |rl| {
        try rateLimitCheck(ctx, rl);
    }

    if (ctx.deadline > 0 and milliTimestamp() > ctx.deadline) {
        try ctx.text(.request_timeout, "Request Timeout");
        return;
    }

    {
        defer {
            for (router.after_middleware.items) |mw| {
                mw(ctx);
            }
            for (match_result.after_middleware) |mw| {
                mw(ctx);
            }
        }
        try match_result.handler(ctx);
    }
}

pub fn pathOnly(target: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, target, '?')) |i| return target[0..i];
    return target;
}

pub fn parseQuery(target: []const u8, query: *Context.QueryParams) void {
    const qs = if (std.mem.indexOfScalar(u8, target, '?')) |i| target[i + 1 ..] else return;
    var it = std.mem.splitScalar(u8, qs, '&');
    while (it.next()) |pair| {
        if (pair.len == 0) continue;
        if (query.len >= Context.MAX_PARAMS) return;
        if (std.mem.indexOfScalar(u8, pair, '=')) |i| {
            query.items[query.len] = .{ .key = pair[0..i], .value = pair[i + 1 ..] };
            query.len += 1;
        } else {
            query.items[query.len] = .{ .key = pair, .value = "" };
            query.len += 1;
        }
    }
}
