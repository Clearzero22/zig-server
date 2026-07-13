const std = @import("std");
const Context = @import("../context.zig");

var max_bytes: usize = 1024 * 1024;

pub const Config = struct {
    max_body_bytes: usize = 1 * 1024 * 1024,
};

pub fn init(cfg: Config) void {
    max_bytes = cfg.max_body_bytes;
}

pub fn handler(ctx: *Context) !bool {
    if (ctx.request.head.content_length) |len| {
        if (len > max_bytes) {
            try ctx.text(.payload_too_large, "Request body too large");
            return false;
        }
    }
    return true;
}
