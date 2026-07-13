const std = @import("std");
const Context = @import("../context.zig");

var config: Config = .{};

pub const Config = struct {
    hsts: bool = true,
    hsts_max_age: usize = 31536000,
    hsts_include_subdomains: bool = true,
    x_content_type_options: bool = true,
    x_frame_options: ?[]const u8 = "DENY",
    referrer_policy: ?[]const u8 = "strict-origin-when-cross-origin",
    content_security_policy: ?[]const u8 = null,
    cache_control: bool = true,
};

pub fn init(cfg: Config) void {
    config = cfg;
}

pub fn handler(ctx: *Context) !bool {
    if (config.hsts) {
        var buf: [128]u8 = undefined;
        const val = if (config.hsts_include_subdomains)
            try std.fmt.bufPrint(&buf, "max-age={d}; includeSubDomains", .{config.hsts_max_age})
        else
            try std.fmt.bufPrint(&buf, "max-age={d}", .{config.hsts_max_age});
        try ctx.header("strict-transport-security", val);
    }
    if (config.x_content_type_options) {
        try ctx.header("x-content-type-options", "nosniff");
    }
    if (config.x_frame_options) |val| {
        try ctx.header("x-frame-options", val);
    }
    if (config.referrer_policy) |val| {
        try ctx.header("referrer-policy", val);
    }
    if (config.content_security_policy) |val| {
        try ctx.header("content-security-policy", val);
    }
    if (config.cache_control) {
        try ctx.header("cache-control", "no-store, max-age=0");
    }
    return true;
}
