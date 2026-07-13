const std = @import("std");
const Router = @import("router.zig");
const Dispatch = @import("dispatch.zig");
const c = std.c;

const Job = struct {
    io: std.Io,
    router: *Router,
    conn: std.Io.net.Stream,
};

allocator: std.mem.Allocator,
workers: []std.Thread,
mutex: c.pthread_mutex_t = c.PTHREAD_MUTEX_INITIALIZER,
cond: c.pthread_cond_t = c.PTHREAD_COND_INITIALIZER,
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
    _ = c.pthread_mutex_lock(&self.mutex);
    self.running = false;
    _ = c.pthread_mutex_unlock(&self.mutex);
    _ = c.pthread_cond_broadcast(&self.cond);

    for (self.workers) |w| w.join();
    self.jobs.deinit(self.allocator);
    _ = c.pthread_cond_destroy(&self.cond);
    _ = c.pthread_mutex_destroy(&self.mutex);
    self.allocator.free(self.workers);
    self.allocator.destroy(self);
}

pub fn submit(self: *@This(), job_io: std.Io, router: *Router, conn: std.Io.net.Stream) void {
    _ = c.pthread_mutex_lock(&self.mutex);
    defer _ = c.pthread_mutex_unlock(&self.mutex);
    defer _ = c.pthread_cond_signal(&self.cond);
    self.jobs.append(self.allocator, .{ .io = job_io, .router = router, .conn = conn }) catch {
        conn.close(job_io);
    };
}

fn workerFn(pool: *@This()) void {
    while (true) {
        var job: ?Job = null;
        {
            _ = c.pthread_mutex_lock(&pool.mutex);
            while (pool.jobs.items.len == 0 and pool.running) {
                _ = c.pthread_cond_wait(&pool.cond, &pool.mutex);
            }
            if (!pool.running) {
                _ = c.pthread_mutex_unlock(&pool.mutex);
                return;
            }
            job = pool.jobs.pop();
            _ = c.pthread_mutex_unlock(&pool.mutex);
        }

        if (job) |j| {
            Dispatch.handleConnection(j.io, j.router, j.conn);
        }
    }
}
