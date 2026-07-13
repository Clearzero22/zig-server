const std = @import("std");
const Context = @import("context.zig");

test "params: get existing key" {
    var params: Context.Params = .{};
    params.items[0] = .{ .key = "id", .value = "42" };
    params.len = 1;

    try std.testing.expectEqualStrings("42", params.get("id").?);
    try std.testing.expect(params.get("name") == null);
}

test "params: multiple values" {
    var params: Context.Params = .{};
    params.items[0] = .{ .key = "a", .value = "1" };
    params.items[1] = .{ .key = "b", .value = "2" };
    params.len = 2;

    try std.testing.expectEqualStrings("1", params.get("a").?);
    try std.testing.expectEqualStrings("2", params.get("b").?);
}

test "params: empty params" {
    var params: Context.Params = .{};

    try std.testing.expect(params.get("anything") == null);
}

test "params: full params (8 items)" {
    var params: Context.Params = .{};
    params.items[0] = .{ .key = "k0", .value = "v0" };
    params.items[1] = .{ .key = "k1", .value = "v1" };
    params.items[2] = .{ .key = "k2", .value = "v2" };
    params.items[3] = .{ .key = "k3", .value = "v3" };
    params.items[4] = .{ .key = "k4", .value = "v4" };
    params.items[5] = .{ .key = "k5", .value = "v5" };
    params.items[6] = .{ .key = "k6", .value = "v6" };
    params.items[7] = .{ .key = "k7", .value = "v7" };
    params.len = 8;

    try std.testing.expectEqualStrings("v0", params.get("k0").?);
    try std.testing.expectEqualStrings("v7", params.get("k7").?);
}

test "query params: QueryParams is type alias of Params" {
    try std.testing.expectEqual(@typeInfo(Context.QueryParams), @typeInfo(Context.Params));
}

test "context: QueryParams parsing via inline" {
    var query: Context.QueryParams = .{};
    parseQueryTest("?key=value", &query);
    try std.testing.expectEqualStrings("value", query.get("key").?);
    try std.testing.expectEqual(@as(usize, 1), query.len);
}

test "context: QueryParams multiple" {
    var query: Context.QueryParams = .{};
    parseQueryTest("?a=1&b=2&c=3", &query);
    try std.testing.expectEqualStrings("1", query.get("a").?);
    try std.testing.expectEqualStrings("2", query.get("b").?);
    try std.testing.expectEqualStrings("3", query.get("c").?);
    try std.testing.expectEqual(@as(usize, 3), query.len);
}

test "context: QueryParams bool flag" {
    var query: Context.QueryParams = .{};
    parseQueryTest("?flag", &query);
    try std.testing.expectEqualStrings("", query.get("flag").?);
}

test "context: QueryParams empty query string" {
    var query: Context.QueryParams = .{};
    parseQueryTest("?flag=", &query);
    try std.testing.expectEqualStrings("", query.get("flag").?);
}

test "context: QueryParams no query" {
    var query: Context.QueryParams = .{};
    parseQueryTest("/path", &query);
    try std.testing.expectEqual(@as(usize, 0), query.len);
}

test "context: QueryParams max entries" {
    var query: Context.QueryParams = .{};
    parseQueryTest("?a=1&b=2&c=3&d=4&e=5&f=6&g=7&h=8&i=9&j=10&k=11&l=12&m=13&n=14&o=15&p=16&q=17", &query);
    try std.testing.expectEqual(Context.MAX_PARAMS, query.len);
    try std.testing.expect(query.get("a") != null);
    try std.testing.expect(query.get("p") != null);
    try std.testing.expect(query.get("q") == null);
}

test "context: QueryParams empty value after ==" {
    var query: Context.QueryParams = .{};
    parseQueryTest("?a=1&&b=2", &query);
    try std.testing.expectEqualStrings("1", query.get("a").?);
    try std.testing.expectEqualStrings("2", query.get("b").?);
}

test "context: QueryParams special chars" {
    var query: Context.QueryParams = .{};
    parseQueryTest("?search=hello+world&lang=zh-CN", &query);
    try std.testing.expectEqualStrings("hello+world", query.get("search").?);
    try std.testing.expectEqualStrings("zh-CN", query.get("lang").?);
}

test "context: MAX_PARAMS constant value" {
    try std.testing.expectEqual(@as(usize, 16), Context.MAX_PARAMS);
}

test "context: header stores extra headers" {
    var ctx = Context{
        .io = undefined,
        .allocator = std.testing.allocator,
        .request = undefined,
    };
    try ctx.header("x-custom", "value1");
    try ctx.header("x-other", "value2");
    try std.testing.expectEqual(@as(usize, 2), ctx.extra_header_count);
    try std.testing.expectEqualStrings("x-custom", ctx.extra_header_buf[0].name);
    try std.testing.expectEqualStrings("value1", ctx.extra_header_buf[0].value);
    try std.testing.expectEqualStrings("x-other", ctx.extra_header_buf[1].name);
    try std.testing.expectEqualStrings("value2", ctx.extra_header_buf[1].value);
}

test "context: header overflow" {
    var ctx = Context{
        .io = undefined,
        .allocator = std.testing.allocator,
        .request = undefined,
    };
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        try ctx.header("h", "v");
    }
    try std.testing.expectError(error.TooManyHeaders, ctx.header("overflow", "bad"));
}

fn parseQueryTest(target: []const u8, query: *Context.QueryParams) void {
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
