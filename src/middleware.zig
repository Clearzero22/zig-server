const Context = @import("context.zig");

pub const Middleware = *const fn (ctx: *Context) anyerror!bool;
