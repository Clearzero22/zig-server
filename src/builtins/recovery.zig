const Context = @import("../context.zig");

pub fn handler(ctx: *Context) !void {
    try ctx.json(.internal_server_error, "{\"error\":\"Internal Server Error\",\"status\":500}");
}
