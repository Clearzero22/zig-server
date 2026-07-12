const std = @import("std");
const Context = @import("context.zig");
const Middleware = @import("middleware.zig").Middleware;

allocator: std.mem.Allocator,
routes: std.ArrayList(Route),
middleware: std.ArrayList(Middleware),
error_handler: ?Handler = null,

pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,

    pub fn fromHttp(m: std.http.Method) ?Method {
        return switch (m) {
            .GET => .GET,
            .HEAD => .GET,
            .POST => .POST,
            .PUT => .PUT,
            .DELETE => .DELETE,
            .PATCH => .PATCH,
            else => null,
        };
    }
};

pub const Handler = *const fn (ctx: *Context) anyerror!void;

pub const Route = struct {
    method: Method,
    path: []const u8,
    handler: Handler,
};

pub const MatchResult = struct {
    handler: Handler,
    params: Context.Params,
};

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{ .allocator = allocator, .routes = .empty, .middleware = .empty };
}

pub fn deinit(self: *@This()) void {
    self.routes.deinit(self.allocator);
    self.middleware.deinit(self.allocator);
}

pub fn use(self: *@This(), mw: Middleware) !void {
    try self.middleware.append(self.allocator, mw);
}

pub fn onError(self: *@This(), handler: Handler) void {
    self.error_handler = handler;
}

pub fn get(self: *@This(), path: []const u8, handler: Handler) !void {
    try self.routes.append(self.allocator, .{ .method = .GET, .path = path, .handler = handler });
}

pub fn post(self: *@This(), path: []const u8, handler: Handler) !void {
    try self.routes.append(self.allocator, .{ .method = .POST, .path = path, .handler = handler });
}

pub fn put(self: *@This(), path: []const u8, handler: Handler) !void {
    try self.routes.append(self.allocator, .{ .method = .PUT, .path = path, .handler = handler });
}

pub fn delete(self: *@This(), path: []const u8, handler: Handler) !void {
    try self.routes.append(self.allocator, .{ .method = .DELETE, .path = path, .handler = handler });
}

pub fn match(self: *@This(), method: Method, target: []const u8) ?MatchResult {
    for (self.routes.items) |route| {
        if (route.method != method) continue;
        var params: Context.Params = .{};
        if (matchPath(route.path, target, &params)) {
            return .{ .handler = route.handler, .params = params };
        }
    }
    return null;
}

fn matchPath(pattern: []const u8, target: []const u8, params: *Context.Params) bool {
    var pat_it = std.mem.splitScalar(u8, pattern, '/');
    var tgt_it = std.mem.splitScalar(u8, target, '/');

    while (true) {
        const p_seg = pat_it.next();
        const t_seg = tgt_it.next();

        if (p_seg == null and t_seg == null) return true;
        if (p_seg == null or t_seg == null) return false;

        const p = p_seg.?;
        const t = t_seg.?;

        if (p.len > 0 and p[0] == ':') {
            if (params.len >= 8) return false;
            params.items[params.len] = .{ .key = p[1..], .value = t };
            params.len += 1;
        } else if (!std.mem.eql(u8, p, t)) {
            return false;
        }
    }
}
