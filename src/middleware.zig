const Context = @import("context.zig");

pub const Middleware = *const fn (ctx: *Context) anyerror!bool;

pub const AfterMiddleware = *const fn (ctx: *Context) void;
