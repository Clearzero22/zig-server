const std = @import("std");
const Context = @import("context.zig");
const Router = @import("router.zig");

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

    for (router.middleware.items) |mw| {
        if (!try mw(ctx)) return;
    }

    try match_result.handler(ctx);
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
        if (query.len >= 8) return;
        if (std.mem.indexOfScalar(u8, pair, '=')) |i| {
            query.items[query.len] = .{ .key = pair[0..i], .value = pair[i + 1 ..] };
            query.len += 1;
        } else {
            query.items[query.len] = .{ .key = pair, .value = "" };
            query.len += 1;
        }
    }
}
