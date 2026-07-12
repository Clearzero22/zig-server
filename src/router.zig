const std = @import("std");
const Context = @import("context.zig");
const Middleware = @import("middleware.zig").Middleware;

pub const Router = @This();

allocator: std.mem.Allocator,
routes: std.ArrayList(Route),
middleware: std.ArrayList(Middleware),
error_handler: ?Handler = null,
named_routes: std.StringHashMap([]const u8),

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

pub const HeaderMatch = struct {
    name: []const u8,
    value: []const u8,
};

pub const RouteOptions = struct {
    name: ?[]const u8 = null,
    priority: i32 = 0,
    host: ?[]const u8 = null,
    headers: ?[]const HeaderMatch = null,
};

pub const Segment = union(enum) {
    exact: []const u8,
    param: []const u8,
    optional_param: []const u8,
    wildcard: []const u8,
    regex: []const u8,
    multi_param: []const []const u8,
};

pub const Route = struct {
    method: Method,
    path: []const u8,
    handler: Handler,
    name: ?[]const u8 = null,
    priority: i32 = 0,
    host: ?[]const u8 = null,
    headers: ?[]const HeaderMatch = null,
    has_wildcard: bool = false,
    segments: []const Segment = &.{},
};

pub const MatchResult = struct {
    handler: Handler,
    params: Context.Params,
};

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{
        .allocator = allocator,
        .routes = .empty,
        .middleware = .empty,
        .named_routes = std.StringHashMap([]const u8).init(allocator),
    };
}

pub fn deinit(self: *@This()) void {
    for (self.routes.items) |route| {
        self.allocator.free(route.path);
        if (route.name) |n| self.allocator.free(n);
        if (route.host) |h| self.allocator.free(h);
        if (route.headers) |hdrs| {
            for (hdrs) |h| {
                self.allocator.free(h.name);
                self.allocator.free(h.value);
            }
            self.allocator.free(hdrs);
        }
        for (route.segments) |seg| {
            if (seg == .multi_param) {
                self.allocator.free(seg.multi_param);
            }
        }
        self.allocator.free(route.segments);
    }
    self.routes.deinit(self.allocator);
    self.middleware.deinit(self.allocator);
    self.named_routes.deinit();
}

pub fn use(self: *@This(), mw: Middleware) !void {
    try self.middleware.append(self.allocator, mw);
}

pub fn onError(self: *@This(), handler: Handler) void {
    self.error_handler = handler;
}

fn addRoute(self: *@This(), method: Method, path: []const u8, handler: Handler, opts: RouteOptions) !void {
    for (self.routes.items) |r| {
        if (r.method == method and std.mem.eql(u8, r.path, path)) {
            return error.RouteConflict;
        }
    }

    const has_wc = std.mem.indexOfScalar(u8, path, '*') != null;
    const segs = try parseSegments(self.allocator, path);
    errdefer self.allocator.free(segs);

    var hdrs_dup: ?[]HeaderMatch = null;
    if (opts.headers) |hdrs| {
        hdrs_dup = try self.allocator.alloc(HeaderMatch, hdrs.len);
        for (hdrs, 0..) |h, i| {
            hdrs_dup.?[i] = .{
                .name = try self.allocator.dupe(u8, h.name),
                .value = try self.allocator.dupe(u8, h.value),
            };
        }
    }

    try self.routes.append(self.allocator, .{
        .method = method,
        .path = path,
        .handler = handler,
        .name = if (opts.name) |n| try self.allocator.dupe(u8, n) else null,
        .priority = opts.priority,
        .host = if (opts.host) |h| try self.allocator.dupe(u8, h) else null,
        .headers = hdrs_dup,
        .has_wildcard = has_wc,
        .segments = segs,
    });

    if (opts.name) |n| {
        self.named_routes.put(n, path) catch {};
    }
}

fn parseSegments(allocator: std.mem.Allocator, path: []const u8) ![]const Segment {
    var segs = std.ArrayList(Segment).empty;

    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |seg| {
        if (seg.len == 0) {
            try segs.append(allocator, .{ .exact = "" });
        } else if (seg[0] == '*') {
            try segs.append(allocator, .{ .wildcard = seg[1..] });
        } else if (seg[0] == ':') {
            const body = seg[1..];
            if (body.len > 0 and body[body.len - 1] == '?') {
                try segs.append(allocator, .{ .optional_param = body[0 .. body.len - 1] });
            } else if (std.mem.indexOfScalar(u8, body, '+')) |_| {
                const names = try splitParamNames(allocator, body);
                try segs.append(allocator, .{ .multi_param = names });
            } else {
                try segs.append(allocator, .{ .param = body });
            }
        } else if (seg[0] == '(') {
            try segs.append(allocator, .{ .regex = seg });
        } else {
            try segs.append(allocator, .{ .exact = seg });
        }
    }
    return segs.toOwnedSlice(allocator);
}

fn splitParamNames(allocator: std.mem.Allocator, body: []const u8) ![]const []const u8 {
    var names = std.ArrayList([]const u8).empty;
    var it = std.mem.splitScalar(u8, body, '+');
    while (it.next()) |name| {
        const cleaned = if (name.len > 0 and name[0] == ':') name[1..] else name;
        try names.append(allocator, cleaned);
    }
    return names.toOwnedSlice(allocator);
}

pub fn get(self: *@This(), path: []const u8, handler: Handler) !void {
    const owned = try self.allocator.dupe(u8, path);
    errdefer self.allocator.free(owned);
    try self.addRoute(.GET, owned, handler, .{});
}

pub fn post(self: *@This(), path: []const u8, handler: Handler) !void {
    const owned = try self.allocator.dupe(u8, path);
    errdefer self.allocator.free(owned);
    try self.addRoute(.POST, owned, handler, .{});
}

pub fn put(self: *@This(), path: []const u8, handler: Handler) !void {
    const owned = try self.allocator.dupe(u8, path);
    errdefer self.allocator.free(owned);
    try self.addRoute(.PUT, owned, handler, .{});
}

pub fn delete(self: *@This(), path: []const u8, handler: Handler) !void {
    const owned = try self.allocator.dupe(u8, path);
    errdefer self.allocator.free(owned);
    try self.addRoute(.DELETE, owned, handler, .{});
}

pub fn patch(self: *@This(), path: []const u8, handler: Handler) !void {
    const owned = try self.allocator.dupe(u8, path);
    errdefer self.allocator.free(owned);
    try self.addRoute(.PATCH, owned, handler, .{});
}

pub fn getOpts(self: *@This(), path: []const u8, handler: Handler, opts: RouteOptions) !void {
    const owned = try self.allocator.dupe(u8, path);
    errdefer self.allocator.free(owned);
    try self.addRoute(.GET, owned, handler, opts);
}

pub fn postOpts(self: *@This(), path: []const u8, handler: Handler, opts: RouteOptions) !void {
    const owned = try self.allocator.dupe(u8, path);
    errdefer self.allocator.free(owned);
    try self.addRoute(.POST, owned, handler, opts);
}

pub fn putOpts(self: *@This(), path: []const u8, handler: Handler, opts: RouteOptions) !void {
    const owned = try self.allocator.dupe(u8, path);
    errdefer self.allocator.free(owned);
    try self.addRoute(.PUT, owned, handler, opts);
}

pub fn deleteOpts(self: *@This(), path: []const u8, handler: Handler, opts: RouteOptions) !void {
    const owned = try self.allocator.dupe(u8, path);
    errdefer self.allocator.free(owned);
    try self.addRoute(.DELETE, owned, handler, opts);
}

pub fn patchOpts(self: *@This(), path: []const u8, handler: Handler, opts: RouteOptions) !void {
    const owned = try self.allocator.dupe(u8, path);
    errdefer self.allocator.free(owned);
    try self.addRoute(.PATCH, owned, handler, opts);
}

pub fn url(self: *@This(), name: []const u8, params: anytype) ![]const u8 {
    const pattern = self.named_routes.get(name) orelse return error.RouteNotFound;
    return try buildURL(self.allocator, pattern, params);
}

fn buildURL(allocator: std.mem.Allocator, pattern: []const u8, params: anytype) ![]const u8 {
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    var it = std.mem.splitScalar(u8, pattern, '/');
    var first = true;
    while (it.next()) |seg| {
        if (seg.len == 0) continue;
        try result.append(allocator, '/');

        if (seg[0] == ':') {
            const body = seg[1..];
            var name_end = body.len;
            if (body.len > 0 and body[body.len - 1] == '?') {
                name_end = body.len - 1;
            }
            const pname = body[0..name_end];

            var found = false;
            inline for (std.meta.fields(@TypeOf(params))) |field| {
                if (std.mem.eql(u8, field.name, pname)) {
                    const val = @field(params, field.name);
                    try result.appendSlice(allocator, val);
                    found = true;
                }
            }
            if (!found and seg[seg.len - 1] != '?') return error.MissingURLParam;
        } else if (seg[0] == '*') {
            const body = seg[1..];
            if (body.len > 0) {
                var found = false;
                inline for (std.meta.fields(@TypeOf(params))) |field| {
                    if (std.mem.eql(u8, field.name, body)) {
                        const val = @field(params, field.name);
                        try result.appendSlice(allocator, val);
                        found = true;
                    }
                }
                if (!found) return error.MissingURLParam;
            }
        } else {
            try result.appendSlice(allocator, seg);
        }
        first = false;
    }
    return result.toOwnedSlice(allocator);
}

pub fn match(self: *@This(), method: Method, target: []const u8) ?MatchResult {
    self.sortRoutes();

    for (self.routes.items) |route| {
        if (route.method != method) continue;

        if (route.host) |host| {
            if (!std.mem.eql(u8, host, "")) {
                continue;
            }
        }

        var params: Context.Params = .{};
        if (matchSegments(route.segments, target, &params)) {
            return .{ .handler = route.handler, .params = params };
        }
    }
    return null;
}

fn sortRoutes(self: *@This()) void {
    std.mem.sort(Route, self.routes.items, {}, struct {
        fn less(_: void, a: Route, b: Route) bool {
            if (a.priority != b.priority) return a.priority > b.priority;
            if (a.has_wildcard != b.has_wildcard) return !a.has_wildcard;
            return false;
        }
    }.less);
}

fn matchSegments(segments: []const Segment, target: []const u8, params: *Context.Params) bool {
    if (segments.len == 1 and segments[0] == .wildcard) {
        const name = segments[0].wildcard;
        if (name.len > 0) {
            if (params.len >= 8) return false;
            const val = if (target.len > 0 and target[0] == '/') target[1..] else target;
            params.items[params.len] = .{ .key = name, .value = val };
            params.len += 1;
        }
        return true;
    }

    var tgt_it = std.mem.splitScalar(u8, target, '/');

    for (segments) |seg| {
        switch (seg) {
            .exact => |e| {
                const t_seg = tgt_it.next() orelse return false;
                if (!std.mem.eql(u8, e, t_seg)) return false;
            },
            .param => |name| {
                const t_seg = tgt_it.next() orelse return false;
                if (params.len >= 8) return false;
                params.items[params.len] = .{ .key = name, .value = t_seg };
                params.len += 1;
            },
            .optional_param => |name| {
                if (tgt_it.next()) |t_seg| {
                    if (params.len >= 8) return false;
                    params.items[params.len] = .{ .key = name, .value = t_seg };
                    params.len += 1;
                }
            },
            .wildcard => |name| {
                if (tgt_it.next()) |seg_val| {
                    const seg_start = @intFromPtr(seg_val.ptr) - @intFromPtr(target.ptr);
                    const remaining = target[seg_start..];
                    if (name.len > 0) {
                        if (params.len >= 8) return false;
                        params.items[params.len] = .{ .key = name, .value = remaining };
                        params.len += 1;
                    }
                } else if (name.len > 0) {
                    if (params.len >= 8) return false;
                    params.items[params.len] = .{ .key = name, .value = "" };
                    params.len += 1;
                }
                return true;
            },
            .regex => |pattern| {
                const t_seg = tgt_it.next() orelse return false;
                if (!matchRegexSegment(pattern, t_seg)) return false;
            },
            .multi_param => |mp| {
                const t_seg = tgt_it.next() orelse return false;
                var remaining = t_seg;
                for (mp, 0..) |name, j| {
                    if (params.len >= 8) return false;
                    if (j == mp.len - 1) {
                        params.items[params.len] = .{ .key = name, .value = remaining };
                        params.len += 1;
                    } else {
                        if (std.mem.indexOfScalar(u8, remaining, '+')) |plus_pos| {
                            params.items[params.len] = .{ .key = name, .value = remaining[0..plus_pos] };
                            params.len += 1;
                            remaining = remaining[plus_pos + 1 ..];
                        } else {
                            return false;
                        }
                    }
                }
            },
        }
    }

    return tgt_it.next() == null;
}

const RegexClass = enum { digit, word, dot, literal };
const Quantifier = enum { exactly_one, one_or_more, zero_or_more };

fn matchRegexSegment(pattern: []const u8, target: []const u8) bool {
    const inner = pattern[1 .. pattern.len - 1];
    return matchRegexInner(inner, target);
}

fn matchRegexInner(inner: []const u8, target: []const u8) bool {
    if (inner.len == 0) return target.len == 0;

    var pi: usize = 0;
    var ti: usize = 0;

    while (pi < inner.len) {
        if (pi + 1 < inner.len and inner[pi] == '\\') {
            const next = inner[pi + 1];
            const class: RegexClass = if (next == 'd') .digit else if (next == 'w') .word else if (next == '.') .dot else .literal;
            const lit_char = if (class == .literal) next else undefined;

            const quant: Quantifier = if (pi + 2 < inner.len and inner[pi + 2] == '+')
                .one_or_more
            else if (pi + 2 < inner.len and inner[pi + 2] == '*')
                .zero_or_more
            else
                .exactly_one;

            const advance: usize = switch (quant) {
                .exactly_one => 2,
                .one_or_more => 3,
                .zero_or_more => 3,
            };

            switch (quant) {
                .exactly_one => {
                    if (ti >= target.len) return false;
                    if (!matchClass(class, target[ti], lit_char)) return false;
                    ti += 1;
                },
                .one_or_more => {
                    if (ti >= target.len or !matchClass(class, target[ti], lit_char)) return false;
                    ti += 1;
                    while (ti < target.len and matchClass(class, target[ti], lit_char)) {
                        ti += 1;
                    }
                },
                .zero_or_more => {
                    while (ti < target.len and matchClass(class, target[ti], lit_char)) {
                        ti += 1;
                    }
                },
            }
            pi += advance;
        } else if (inner[pi] == '.') {
            if (pi + 1 < inner.len and inner[pi + 1] == '+') {
                if (ti >= target.len) return false;
                ti += 1;
                while (ti < target.len) { ti += 1; }
                pi += 2;
            } else if (pi + 1 < inner.len and inner[pi + 1] == '*') {
                while (ti < target.len) { ti += 1; }
                pi += 2;
            } else {
                if (ti >= target.len) return false;
                ti += 1;
                pi += 1;
            }
        } else if (inner[pi] == '+') {
            pi += 1;
        } else if (inner[pi] == '*') {
            pi += 1;
        } else {
            if (ti >= target.len or target[ti] != inner[pi]) return false;
            ti += 1;
            pi += 1;
        }
    }

    return ti == target.len;
}

fn matchClass(class: RegexClass, c: u8, literal: u8) bool {
    return switch (class) {
        .digit => std.ascii.isDigit(c),
        .word => std.ascii.isAlphanumeric(c),
        .dot => true,
        .literal => c == literal,
    };
}

pub const Group = struct {
    router: *Router,
    prefix: []const u8,

    pub fn get(self: *Group, path: []const u8, handler: Handler) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.addRoute(.GET, full, handler, .{});
    }

    pub fn post(self: *Group, path: []const u8, handler: Handler) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.addRoute(.POST, full, handler, .{});
    }

    pub fn put(self: *Group, path: []const u8, handler: Handler) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.addRoute(.PUT, full, handler, .{});
    }

    pub fn delete(self: *Group, path: []const u8, handler: Handler) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.addRoute(.DELETE, full, handler, .{});
    }

    pub fn patch(self: *Group, path: []const u8, handler: Handler) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.addRoute(.PATCH, full, handler, .{});
    }

    pub fn getOpts(self: *Group, path: []const u8, handler: Handler, opts: RouteOptions) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.addRoute(.GET, full, handler, opts);
    }

    pub fn postOpts(self: *Group, path: []const u8, handler: Handler, opts: RouteOptions) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.addRoute(.POST, full, handler, opts);
    }

    pub fn putOpts(self: *Group, path: []const u8, handler: Handler, opts: RouteOptions) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.addRoute(.PUT, full, handler, opts);
    }

    pub fn deleteOpts(self: *Group, path: []const u8, handler: Handler, opts: RouteOptions) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.addRoute(.DELETE, full, handler, opts);
    }

    pub fn patchOpts(self: *Group, path: []const u8, handler: Handler, opts: RouteOptions) !void {
        const full = try concat(self.router.allocator, self.prefix, path);
        try self.router.addRoute(.PATCH, full, handler, opts);
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
