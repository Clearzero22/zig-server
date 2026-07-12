const std = @import("std");
const Router = @import("router.zig");
const Context = @import("context.zig");

test "router: static path match" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try std.testing.expect(router.match(.GET, "/hello") == null);

    try router.get("/hello", struct {
        fn h(_: *Context) !void {}
    }.h);

    try std.testing.expect(router.match(.GET, "/hello") != null);
    try std.testing.expect(router.match(.POST, "/hello") == null);
    try std.testing.expect(router.match(.GET, "/world") == null);
}

test "router: path params" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.get("/users/:id", struct {
        fn h(_: *Context) !void {}
    }.h);

    const r = router.match(.GET, "/users/42");
    try std.testing.expect(r != null);
    try std.testing.expectEqualStrings("42", r.?.params.get("id").?);
    try std.testing.expect(r.?.params.get("nonexistent") == null);
}

test "router: multiple path params" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.get("/users/:id/posts/:pid", struct {
        fn h(_: *Context) !void {}
    }.h);

    const r = router.match(.GET, "/users/5/posts/10");
    try std.testing.expect(r != null);
    try std.testing.expectEqualStrings("5", r.?.params.get("id").?);
    try std.testing.expectEqualStrings("10", r.?.params.get("pid").?);
}

test "router: method mismatch" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.get("/only-get", struct {
        fn h(_: *Context) !void {}
    }.h);

    try std.testing.expect(router.match(.POST, "/only-get") == null);
    try std.testing.expect(router.match(.PUT, "/only-get") == null);
    try std.testing.expect(router.match(.DELETE, "/only-get") == null);
    try std.testing.expect(router.match(.PATCH, "/only-get") == null);
    try std.testing.expect(router.match(.GET, "/only-get") != null);
}

test "router: root path" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.get("/", struct {
        fn h(_: *Context) !void {}
    }.h);

    try std.testing.expect(router.match(.GET, "/") != null);
}

test "router: HEAD mapped to GET" {
    try std.testing.expectEqual(Router.Method.GET, Router.Method.fromHttp(.HEAD));
    try std.testing.expectEqual(Router.Method.GET, Router.Method.fromHttp(.GET));
    try std.testing.expectEqual(Router.Method.POST, Router.Method.fromHttp(.POST));
    try std.testing.expectEqual(Router.Method.PUT, Router.Method.fromHttp(.PUT));
    try std.testing.expectEqual(Router.Method.DELETE, Router.Method.fromHttp(.DELETE));
    try std.testing.expectEqual(Router.Method.PATCH, Router.Method.fromHttp(.PATCH));
    try std.testing.expectEqual(null, Router.Method.fromHttp(.OPTIONS));
    try std.testing.expectEqual(null, Router.Method.fromHttp(.CONNECT));
    try std.testing.expectEqual(null, Router.Method.fromHttp(.TRACE));
}

test "router: group prefix" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    var api = router.group("/api");
    try api.get("/users", struct {
        fn h(_: *Context) !void {}
    }.h);
    try api.get("/posts", struct {
        fn h(_: *Context) !void {}
    }.h);

    try std.testing.expect(router.match(.GET, "/api/users") != null);
    try std.testing.expect(router.match(.GET, "/api/posts") != null);
    try std.testing.expect(router.match(.GET, "/api") == null);
}

test "router: group all methods" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    var g = router.group("/prefix");
    try g.get("/get", struct { fn h(_: *Context) !void {} }.h);
    try g.post("/post", struct { fn h(_: *Context) !void {} }.h);
    try g.put("/put", struct { fn h(_: *Context) !void {} }.h);
    try g.delete("/del", struct { fn h(_: *Context) !void {} }.h);
    try g.patch("/patch", struct { fn h(_: *Context) !void {} }.h);

    try std.testing.expect(router.match(.GET, "/prefix/get") != null);
    try std.testing.expect(router.match(.POST, "/prefix/post") != null);
    try std.testing.expect(router.match(.PUT, "/prefix/put") != null);
    try std.testing.expect(router.match(.DELETE, "/prefix/del") != null);
    try std.testing.expect(router.match(.PATCH, "/prefix/patch") != null);
}

test "router: match not found" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.get("/a", struct {
        fn h(_: *Context) !void {}
    }.h);

    try std.testing.expect(router.match(.GET, "/b") == null);
    try std.testing.expect(router.match(.GET, "/a/b") == null);
    try std.testing.expect(router.match(.GET, "/") == null);
}

test "router: params overflow" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.get("/:a/:b/:c/:d/:e/:f/:g/:h/:i", struct {
        fn h(_: *Context) !void {}
    }.h);

    const r = router.match(.GET, "/1/2/3/4/5/6/7/8/9");
    try std.testing.expect(r == null);
}

test "router: params exactly 8" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.get("/:a/:b/:c/:d/:e/:f/:g/:h", struct {
        fn h(_: *Context) !void {}
    }.h);

    const r = router.match(.GET, "/1/2/3/4/5/6/7/8");
    try std.testing.expect(r != null);
    try std.testing.expectEqualStrings("8", r.?.params.get("h").?);
}

test "router: empty segment not match" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.get("/a/b", struct {
        fn h(_: *Context) !void {}
    }.h);

    try std.testing.expect(router.match(.GET, "/a/b/") == null);
}

test "router: all methods via router" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.get("/g", struct { fn h(_: *Context) !void {} }.h);
    try router.post("/p", struct { fn h(_: *Context) !void {} }.h);
    try router.put("/u", struct { fn h(_: *Context) !void {} }.h);
    try router.delete("/d", struct { fn h(_: *Context) !void {} }.h);
    try router.patch("/pa", struct { fn h(_: *Context) !void {} }.h);

    try std.testing.expect(router.match(.GET, "/g") != null);
    try std.testing.expect(router.match(.POST, "/p") != null);
    try std.testing.expect(router.match(.PUT, "/u") != null);
    try std.testing.expect(router.match(.DELETE, "/d") != null);
    try std.testing.expect(router.match(.PATCH, "/pa") != null);
}

test "router: path encoding literal match" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.get("/literal", struct {
        fn h(_: *Context) !void {}
    }.h);

    try std.testing.expect(router.match(.GET, "/literal") != null);
}

test "router: wildcard match" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.getOpts("/static/*path", struct {
        fn h(_: *Context) !void {}
    }.h, .{});

    const r1 = router.match(.GET, "/static/css/style.css");
    try std.testing.expect(r1 != null);
    try std.testing.expectEqualStrings("css/style.css", r1.?.params.get("path").?);

    const r2 = router.match(.GET, "/static/");
    try std.testing.expect(r2 != null);
    try std.testing.expectEqualStrings("", r2.?.params.get("path").?);

    try std.testing.expect(router.match(.GET, "/other") == null);
}

test "router: wildcard bare star" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.getOpts("/*path", struct {
        fn h(_: *Context) !void {}
    }.h, .{});

    const r = router.match(.GET, "/anything/at/all");
    try std.testing.expect(r != null);
    try std.testing.expectEqualStrings("anything/at/all", r.?.params.get("path").?);
}

test "router: optional param" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.getOpts("/users/:id?", struct {
        fn h(_: *Context) !void {}
    }.h, .{});

    const r1 = router.match(.GET, "/users/42");
    try std.testing.expect(r1 != null);
    try std.testing.expectEqualStrings("42", r1.?.params.get("id").?);

    const r2 = router.match(.GET, "/users");
    try std.testing.expect(r2 != null);
    try std.testing.expect(r2.?.params.get("id") == null);
}

test "router: multi param segment" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.getOpts("/files/:dir+:name", struct {
        fn h(_: *Context) !void {}
    }.h, .{});

    const r = router.match(.GET, "/files/foo+bar");
    try std.testing.expect(r != null);
    try std.testing.expectEqualStrings("foo", r.?.params.get("dir").?);
    try std.testing.expectEqualStrings("bar", r.?.params.get("name").?);
}

test "router: regex digit match" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.getOpts("/posts/(\\d+)", struct {
        fn h(_: *Context) !void {}
    }.h, .{});

    try std.testing.expect(router.match(.GET, "/posts/123") != null);
    try std.testing.expect(router.match(.GET, "/posts/abc") == null);
}

test "router: route priority" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct { fn h(_: *Context) !void {} };

    try router.getOpts("/users/:id", H.h, .{ .priority = 0 });
    try router.getOpts("/users/me", H.h, .{ .priority = 1 });

    const r = router.match(.GET, "/users/me");
    try std.testing.expect(r != null);
    try std.testing.expect(r.?.params.get("id") == null);
}

test "router: conflict detection" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct { fn h(_: *Context) !void {} };
    try router.get("/dup", H.h);
    try std.testing.expectError(error.RouteConflict, router.get("/dup", H.h));
}

test "router: reverse routing" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct { fn h(_: *Context) !void {} };
    try router.getOpts("/users/:id", H.h, .{ .name = "user" });

    const url = try router.url("user", .{ .id = "42" });
    defer std.testing.allocator.free(url);
    try std.testing.expectEqualStrings("/users/42", url);
}

test "router: named route not found" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try std.testing.expectError(error.RouteNotFound, router.url("nonexistent", .{}));
}
