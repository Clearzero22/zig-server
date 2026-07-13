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

test "cookie: parse single cookie" {
    var req = std.http.Server.Request{
        .server = undefined,
        .head = .{
            .method = .GET,
            .target = "/",
            .version = .@"HTTP/1.1",
            .expect = null,
            .content_type = null,
            .content_length = null,
            .transfer_encoding = .none,
            .transfer_compression = .identity,
            .keep_alive = false,
        },
        .head_buffer = "GET / HTTP/1.1\r\nCookie: session=abc123\r\n\r\n",
    };
    var ctx = Context{
        .io = undefined,
        .allocator = std.testing.allocator,
        .request = &req,
    };
    try std.testing.expectEqualStrings("abc123", ctx.cookie("session").?);
    try std.testing.expect(ctx.cookie("nonexistent") == null);
}

test "cookie: parse multiple cookies" {
    var req = std.http.Server.Request{
        .server = undefined,
        .head = .{
            .method = .GET,
            .target = "/",
            .version = .@"HTTP/1.1",
            .expect = null,
            .content_type = null,
            .content_length = null,
            .transfer_encoding = .none,
            .transfer_compression = .identity,
            .keep_alive = false,
        },
        .head_buffer = "GET / HTTP/1.1\r\nCookie: session=abc123; theme=dark; lang=en\r\n\r\n",
    };
    var ctx = Context{
        .io = undefined,
        .allocator = std.testing.allocator,
        .request = &req,
    };
    try std.testing.expectEqualStrings("abc123", ctx.cookie("session").?);
    try std.testing.expectEqualStrings("dark", ctx.cookie("theme").?);
    try std.testing.expectEqualStrings("en", ctx.cookie("lang").?);
    try std.testing.expect(ctx.cookie("missing") == null);
}

test "cookie: parse no cookie header" {
    var req = std.http.Server.Request{
        .server = undefined,
        .head = .{
            .method = .GET,
            .target = "/",
            .version = .@"HTTP/1.1",
            .expect = null,
            .content_type = null,
            .content_length = null,
            .transfer_encoding = .none,
            .transfer_compression = .identity,
            .keep_alive = false,
        },
        .head_buffer = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n",
    };
    var ctx = Context{
        .io = undefined,
        .allocator = std.testing.allocator,
        .request = &req,
    };
    try std.testing.expect(ctx.cookie("anything") == null);
}

test "context: setCookie stores header" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var ctx = Context{
        .io = undefined,
        .allocator = arena.allocator(),
        .request = undefined,
    };
    try ctx.setCookie("session", "tok123");
    try std.testing.expectEqual(@as(usize, 1), ctx.extra_header_count);
    try std.testing.expectEqualStrings("Set-Cookie", ctx.extra_header_buf[0].name);
    try std.testing.expectEqualStrings("session=tok123", ctx.extra_header_buf[0].value);
}

test "context: setCookieOpts with all options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var ctx = Context{
        .io = undefined,
        .allocator = arena.allocator(),
        .request = undefined,
    };
    try ctx.setCookieOpts("token", "val", .{
        .http_only = true,
        .secure = true,
        .path = "/",
        .max_age = 3600,
        .same_site = .Lax,
    });
    var i: usize = 0;
    while (i < ctx.extra_header_count) : (i += 1) {
        const h = ctx.extra_header_buf[i];
        if (std.mem.eql(u8, h.name, "Set-Cookie")) {
            const v = h.value;
            try std.testing.expect(std.mem.indexOf(u8, v, "token=val") != null);
            try std.testing.expect(std.mem.indexOf(u8, v, "HttpOnly") != null);
            try std.testing.expect(std.mem.indexOf(u8, v, "Secure") != null);
            try std.testing.expect(std.mem.indexOf(u8, v, "Path=/") != null);
            try std.testing.expect(std.mem.indexOf(u8, v, "Max-Age=3600") != null);
            try std.testing.expect(std.mem.indexOf(u8, v, "SameSite=Lax") != null);
            return;
        }
    }
    try std.testing.expect(false); // should have found header
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

test "form: parseUrlEncoded basic" {
    var params: Context.FormParams = .{};
    parseFormTest("name=alice&age=30", &params);
    try std.testing.expectEqualStrings("alice", params.get("name").?);
    try std.testing.expectEqualStrings("30", params.get("age").?);
    try std.testing.expectEqual(@as(usize, 2), params.len);
}

test "form: parseUrlEncoded empty value" {
    var params: Context.FormParams = .{};
    parseFormTest("key=&flag", &params);
    try std.testing.expectEqualStrings("", params.get("key").?);
    try std.testing.expectEqualStrings("", params.get("flag").?);
}

test "form: parseUrlEncoded max entries" {
    var params: Context.FormParams = .{};
    parseFormTest("a=1&b=2&c=3&d=4&e=5&f=6&g=7&h=8&i=9&j=10&k=11&l=12&m=13&n=14&o=15&p=16&q=17", &params);
    try std.testing.expectEqual(Context.MAX_PARAMS, params.len);
    try std.testing.expect(params.get("a") != null);
    try std.testing.expect(params.get("p") != null);
    try std.testing.expect(params.get("q") == null);
}

test "form: extractBoundary basic" {
    const ct = "multipart/form-data; boundary=----WebKitFormBoundaryX";
    const b = extractBoundaryTest(ct);
    try std.testing.expect(b != null);
    try std.testing.expectEqualStrings("----WebKitFormBoundaryX", b.?);
}

test "form: extractBoundary quoted" {
    const ct = "multipart/form-data; boundary=\"----12345\"";
    const b = extractBoundaryTest(ct);
    try std.testing.expect(b != null);
    try std.testing.expectEqualStrings("----12345", b.?);
}

test "form: extractBoundary no boundary" {
    const ct = "application/x-www-form-urlencoded";
    try std.testing.expect(extractBoundaryTest(ct) == null);
}

fn parseFormTest(data: []const u8, params: *Context.FormParams) void {
    var it = std.mem.splitScalar(u8, data, '&');
    while (it.next()) |pair| {
        if (pair.len == 0) continue;
        if (params.len >= Context.MAX_PARAMS) return;
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
            params.items[params.len] = .{ .key = pair[0..eq], .value = pair[eq + 1 ..] };
            params.len += 1;
        } else {
            params.items[params.len] = .{ .key = pair, .value = "" };
            params.len += 1;
        }
    }
}

fn extractBoundaryTest(content_type: []const u8) ?[]const u8 {
    const marker = "boundary=";
    const idx = std.mem.indexOf(u8, content_type, marker) orelse return null;
    const start = idx + marker.len;
    var end = start;
    while (end < content_type.len and content_type[end] != ';' and content_type[end] != ' ') {
        end += 1;
    }
    const raw = content_type[start..end];
    if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') {
        return raw[1 .. raw.len - 1];
    }
    return raw;
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
