const std = @import("std");
const Context = @import("context.zig");
const Router = @import("router.zig");

const Server = @This();

io: std.Io,
router: *Router,

pub fn init(io: std.Io, router: *Router) Server {
    return .{ .io = io, .router = router };
}

pub fn listen(self: *Server, addr: []const u8) !void {
    const address = try std.Io.net.IpAddress.parseLiteral(addr);
    var listener = try address.listen(self.io, .{ .reuse_address = true });
    defer listener.deinit(self.io);

    var buf: [256]u8 = undefined;
    var fw = std.Io.File.stdout().writer(self.io, &buf);
    const w = &fw.interface;
    try w.print("Listening on {s}\n", .{addr});
    try w.flush();

    while (true) {
        const conn = listener.accept(self.io) catch |err| {
            try w.print("Accept error: {}\n", .{err});
            try w.flush();
            continue;
        };
        const thread = try std.Thread.spawn(.{}, handleConnectionThread, .{ self.io, self.router, conn });
        thread.detach();
    }
}

fn handleConnectionThread(io: std.Io, router: *Router, conn: std.Io.net.Stream) void {
    defer conn.close(io);

    var read_buf: [8192]u8 = undefined;
    var write_buf: [4096]u8 = undefined;

    var reader = conn.reader(io, &read_buf);
    var writer = conn.writer(io, &write_buf);

    var http_server = std.http.Server.init(&reader.interface, &writer.interface);

    var request = http_server.receiveHead() catch {
        return;
    };

    var ctx = Context{
        .io = io,
        .allocator = router.allocator,
        .request = &request,
    };

    dispatch(&ctx, router);
}

fn dispatch(ctx: *Context, router: *Router) void {
    if (router.error_handler) |on_err| {
        dispatchInner(ctx, router) catch {
            on_err(ctx) catch {};
        };
    } else {
        dispatchInner(ctx, router) catch {};
    }
}

fn dispatchInner(ctx: *Context, router: *Router) !void {
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

fn pathOnly(target: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, target, '?')) |i| {
        return target[0..i];
    }
    return target;
}

fn parseQuery(target: []const u8, query: *Context.QueryParams) void {
    const qs = if (std.mem.indexOfScalar(u8, target, '?')) |i| target[i + 1 ..] else return;
    var it = std.mem.splitScalar(u8, qs, '&');
    while (it.next()) |pair| {
        if (pair.len == 0) continue;
        if (query.len >= 8) return;
        if (std.mem.indexOfScalar(u8, pair, '=')) |i| {
            const key = pair[0..i];
            const value = pair[i + 1 ..];
            query.items[query.len] = .{ .key = key, .value = value };
            query.len += 1;
        } else {
            query.items[query.len] = .{ .key = pair, .value = "" };
            query.len += 1;
        }
    }
}
