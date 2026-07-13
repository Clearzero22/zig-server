const std = @import("std");
const Context = @import("../context.zig");

var config: Config = .{};
var counter: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

pub const Config = struct {
    header_name: []const u8 = "x-request-id",
};

pub fn init(cfg: Config) void {
    config = cfg;
}

pub fn handler(ctx: *Context) !bool {
    const n = counter.fetchAdd(1, .monotonic);
    var buf: [20]u8 = undefined;
    const id = try std.fmt.bufPrint(&buf, "{d:0>6}", .{n});
    const owned = try ctx.allocator.dupe(u8, id);
    ctx.request_id = owned;
    try ctx.header(config.header_name, owned);
    return true;
}
