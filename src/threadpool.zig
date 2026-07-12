const std = @import("std");
const Context = @import("context.zig");
const Router = @import("router.zig");
const Dispatch = @import("dispatch.zig");

const Job = struct {
    io: std.Io,
    router: *Router,
    conn: std.Io.net.Stream,
};

allocator: std.mem.Allocator,
workers: []std.Thread,
mutex: std.atomic.Mutex = .unlocked,
jobs: std.ArrayList(Job),
running: bool = true,

pub fn init(allocator: std.mem.Allocator, num_threads: usize) !*@This() {
    const pool = try allocator.create(@This());
    pool.* = .{
        .allocator = allocator,
        .workers = try allocator.alloc(std.Thread, num_threads),
        .jobs = .empty,
    };
    errdefer allocator.destroy(pool);

    for (0..num_threads) |i| {
        pool.workers[i] = try std.Thread.spawn(.{}, workerFn, .{pool});
    }
    return pool;
}

pub fn deinit(self: *@This()) void {
    self.running = false;
    for (self.workers) |w| w.join();
    self.jobs.deinit(self.allocator);
    self.allocator.free(self.workers);
    self.allocator.destroy(self);
}

pub fn submit(self: *@This(), job_io: std.Io, router: *Router, conn: std.Io.net.Stream) void {
    while (!self.mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer self.mutex.unlock();
    self.jobs.append(self.allocator, .{ .io = job_io, .router = router, .conn = conn }) catch {
        conn.close(job_io);
    };
}

fn workerFn(pool: *@This()) void {
    while (pool.running) {
        var job: ?Job = null;
        {
            while (!pool.mutex.tryLock()) {
                if (!pool.running) return;
                std.Thread.yield() catch {};
            }
            defer pool.mutex.unlock();
            if (pool.jobs.items.len > 0) {
                job = pool.jobs.pop();
            }
        }

        if (job) |j| {
            handleConnection(j.io, j.router, j.conn);
        } else {
            std.Thread.yield() catch {};
        }
    }
}

fn handleConnection(io: std.Io, router: *Router, conn: std.Io.net.Stream) void {
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
    Dispatch.dispatch(ctx, router);
}
