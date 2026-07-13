const std = @import("std");
const Context = @import("context.zig");

test "pathOnly: no query string" {
    try std.testing.expectEqualStrings("/hello", pathOnly("/hello"));
}

test "pathOnly: with query string" {
    try std.testing.expectEqualStrings("/hello", pathOnly("/hello?key=value"));
}

test "pathOnly: empty path" {
    try std.testing.expectEqualStrings("", pathOnly("?key=value"));
}

test "pathOnly: multiple query params" {
    try std.testing.expectEqualStrings("/search", pathOnly("/search?a=1&b=2&c=3"));
}

test "pathOnly: only query, no path" {
    try std.testing.expectEqualStrings("", pathOnly("?a=1"));
}

test "pathOnly: no question mark" {
    try std.testing.expectEqualStrings("/api/v1/users", pathOnly("/api/v1/users"));
}

test "pathOnly: root with query" {
    try std.testing.expectEqualStrings("/", pathOnly("/?debug=true"));
}

test "parseQuery: basic" {
    var query: Context.QueryParams = .{};
    parseQuery("/search?q=zig", &query);
    try std.testing.expectEqualStrings("zig", query.get("q").?);
}

test "parseQuery: multiple" {
    var query: Context.QueryParams = .{};
    parseQuery("/path?a=1&b=2", &query);
    try std.testing.expectEqualStrings("1", query.get("a").?);
    try std.testing.expectEqualStrings("2", query.get("b").?);
}

test "parseQuery: no query returns empty" {
    var query: Context.QueryParams = .{};
    parseQuery("/path", &query);
    try std.testing.expectEqual(@as(usize, 0), query.len);
}

test "parseQuery: only path no question" {
    var query: Context.QueryParams = .{};
    parseQuery("/plain", &query);
    try std.testing.expectEqual(@as(usize, 0), query.len);
}

test "parseQuery: empty query string" {
    var query: Context.QueryParams = .{};
    parseQuery("/?", &query);
    try std.testing.expectEqual(@as(usize, 0), query.len);
}

fn pathOnly(target: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, target, '?')) |i| {
        return target[0..i];
    }
    return target;
}

fn parseQuery(target: []const u8, query: *Context.QueryParams) void {
    const qs = if (std.mem.indexOfScalar(u8, target, '?')) |i| target[i + 1 ..] else return;
    var it = std.mem.splitScalar(u8, qs, '&');
    while (it.next()) |pair| {
        if (pair.len == 0) continue;
        if (query.len >= Context.MAX_PARAMS) return;
        if (std.mem.indexOfScalar(u8, pair, '=')) |i| {
            query.items[query.len] = .{ .key = pair[0..i], .value = pair[i + 1 ..] };
            query.len += 1;
        } else {
            query.items[query.len] = .{ .key = pair, .value = "" };
            query.len += 1;
        }
    }
}
