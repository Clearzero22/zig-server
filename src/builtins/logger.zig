const std = @import("std");
const Context = @import("../context.zig");

pub fn handler(ctx: *Context) !bool {
    var buf: [128]u8 = undefined;
    var fw = std.Io.File.stdout().writer(ctx.io, &buf);
    const w = &fw.interface;
    w.print("[{s}] {s}\n", .{
        @tagName(ctx.request.head.method),
        ctx.request.head.target,
    }) catch {};
    w.flush() catch {};
    return true;
}
