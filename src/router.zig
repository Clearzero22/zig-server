const std = @import("std");
const Context = @import("context.zig");
const Middleware = @import("middleware.zig").Middleware;

pub const Router = @This();

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
    for (self.routes.items) |route| {
        self.allocator.free(route.path);
    }
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
    try self.routes.append(self.allocator, .{ .method = .GET, .path = try self.allocator.dupe(u8, path), .handler = handler });
}

pub fn post(self: *@This(), path: []const u8, handler: Handler) !void {
    try self.routes.append(self.allocator, .{ .method = .POST, .path = try self.allocator.dupe(u8, path), .handler = handler });
}

pub fn put(self: *@This(), path: []const u8, handler: Handler) !void {
    try self.routes.append(self.allocator, .{ .method = .PUT, .path = try self.allocator.dupe(u8, path), .handler = handler });
}

pub fn delete(self: *@This(), path: []const u8, handler: Handler) !void {
    try self.routes.append(self.allocator, .{ .method = .DELETE, .path = try self.allocator.dupe(u8, path), .handler = handler });
}

pub fn patch(self: *@This(), path: []const u8, handler: Handler) !void {
    try self.routes.append(self.allocator, .{ .method = .PATCH, .path = try self.allocator.dupe(u8, path), .handler = handler });
}

pub const Group = struct {
    router: *Router,
    prefix: []const u8,

    pub fn get(self: *Group, path: []const u8, handler: Handler) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.routes.append(self.router.allocator, .{ .method = .GET, .path = full, .handler = handler });
    }

    pub fn post(self: *Group, path: []const u8, handler: Handler) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.routes.append(self.router.allocator, .{ .method = .POST, .path = full, .handler = handler });
    }

    pub fn put(self: *Group, path: []const u8, handler: Handler) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.routes.append(self.router.allocator, .{ .method = .PUT, .path = full, .handler = handler });
    }

    pub fn delete(self: *Group, path: []const u8, handler: Handler) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.routes.append(self.router.allocator, .{ .method = .DELETE, .path = full, .handler = handler });
    }

    pub fn patch(self: *Group, path: []const u8, handler: Handler) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.routes.append(self.router.allocator, .{ .method = .PATCH, .path = full, .handler = handler });
    }
};

pub fn group(self: *@This(), prefix: []const u8) Group {
    return .{ .router = self, .prefix = prefix };
}

fn concat(allocator: std.mem.Allocator, prefix: []const u8, path: []const u8) ![]const u8 {
    if (std.mem.endsWith(u8, prefix, "/")) {
        return if (std.mem.startsWith(u8, path, "/"))
            try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, path[1..] })
        else
            try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, path });
    }
    return if (std.mem.startsWith(u8, path, "/"))
        try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, path })
    else
        try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, path });
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
