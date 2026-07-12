const std = @import("std");
const Context = @import("context.zig");
const Router = @import("router.zig");
const ThreadPool = @import("threadpool.zig");
const Dispatch = @import("dispatch.zig");

io: std.Io,
router: *Router,
pool: ?*ThreadPool = null,
running: bool = true,
address: ?std.Io.net.IpAddress = null,

pub fn init(io: std.Io, router: *Router) @This() {
    return .{ .io = io, .router = router };
}

pub fn initPool(io: std.Io, router: *Router, num_threads: usize) !@This() {
    const pool = try ThreadPool.init(router.allocator, num_threads);
    return .{ .io = io, .router = router, .pool = pool };
}

pub fn deinit(self: *@This()) void {
    if (self.pool) |p| p.deinit();
}

pub fn listen(self: *@This(), addr: []const u8) !void {
    const address = try std.Io.net.IpAddress.parseLiteral(addr);
    self.address = address;
    var listener = try address.listen(self.io, .{ .reuse_address = true });
    defer listener.deinit(self.io);

    var buf: [256]u8 = undefined;
    var fw = std.Io.File.stdout().writer(self.io, &buf);
    const w = &fw.interface;
    try w.print("Listening on {s}\n", .{addr});
    try w.flush();

    while (self.running) {
        const conn = listener.accept(self.io) catch |err| {
            if (!self.running) return;
            try w.print("Accept error: {}\n", .{err});
            try w.flush();
            continue;
        };

        if (self.pool) |pool| {
            pool.submit(self.io, self.router, conn);
        } else {
            const thread = try std.Thread.spawn(.{}, handleConnectionThread, .{ self.io, self.router, conn });
            thread.detach();
        }
    }
}

pub fn shutdown(self: *@This()) void {
    self.running = false;
    if (self.address) |addr| {
        const loopback = switch (addr) {
            .ip4 => |ip4| std.Io.net.IpAddress{ .ip4 = std.Io.net.Ip4Address.loopback(ip4.port) },
            .ip6 => |ip6| std.Io.net.IpAddress{ .ip6 = std.Io.net.Ip6Address.loopback(ip6.port) },
        };
        _ = std.Io.net.IpAddress.connect(&loopback, self.io, .{}) catch {};
    }
    self.deinit();
}

fn handleConnectionThread(io: std.Io, router: *Router, conn: std.Io.net.Stream) void {
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

fn dispatch(ctx: *Context, router: *Router) void {
    Dispatch.handle(ctx, router);
}
