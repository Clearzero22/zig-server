const std = @import("std");
const Context = @import("../context.zig");

pub var dir: []const u8 = "public";

pub fn handle(ctx: *Context) !void {
    const filepath = ctx.params.get("filepath") orelse return ctx.text(.not_found, "Not Found");
    if (std.mem.indexOf(u8, filepath, "..") != null) {
        return ctx.text(.bad_request, "Invalid path");
    }
    const full = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ dir, filepath });
    defer ctx.allocator.free(full);
    try ctx.sendFile(full);
}
