const std = @import("std");
const Context = @import("../context.zig");

var config: Config = .{};

pub const Config = struct {
    timeout_ms: u64 = 30_000,
};

fn milliTimestamp() i64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    const sec: i64 = @intCast(ts.sec);
    const nsec: i64 = @intCast(ts.nsec);
    return sec * 1000 + @divTrunc(nsec, 1000000);
}

pub fn init(cfg: Config) void {
    config = cfg;
}

pub fn handler(ctx: *Context) !bool {
    ctx.deadline = milliTimestamp() + @as(i64, @intCast(config.timeout_ms));
    return true;
}
