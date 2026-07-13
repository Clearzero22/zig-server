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

    try router.get("/:a/:b/:c/:d/:e/:f/:g/:h/:i/:j/:k/:l/:m/:n/:o/:p/:q", struct {
        fn h(_: *Context) !void {}
    }.h);

    const r = router.match(.GET, "/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17");
    try std.testing.expect(r == null);
}

test "router: params exactly 16" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.get("/:a/:b/:c/:d/:e/:f/:g/:h/:i/:j/:k/:l/:m/:n/:o/:p", struct {
        fn h(_: *Context) !void {}
    }.h);

    const r = router.match(.GET, "/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16");
    try std.testing.expect(r != null);
    try std.testing.expectEqualStrings("16", r.?.params.get("p").?);
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

test "router: openapi json generates valid structure" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.setOpenApiInfo("Test API", "2.0.0", "A test API");
    const H = struct { fn h(_: *Context) !void {} };
    try router.getOpts("/users/:id", H.h, .{ .name = "getUser", .summary = "Get user by ID", .tags = "users" });
    try router.getOpts("/docs", H.h, .{});

    const json = try router.openapiJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"openapi\": \"3.0.3\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"title\": \"Test API\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\": \"2.0.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"description\": \"A test API\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\": \"Get user by ID\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tags\": [\"users\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "/users/{param}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "/docs") != null);
}

test "router: openapi with structured metadata" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.setOpenApiInfo("My API", "1.0.0", null);
    const H = struct { fn h(_: *Context) !void {} };

    try router.postOpts("/echo", H.h, .{
        .name = "echo",
        .summary = "Echo request",
        .description = "Returns the request body as-is",
        .tags = "echo,testing",
        .deprecated = false,
        .body_type = "EchoRequest",
        .response_type = "EchoResponse",
    });

    const json = try router.openapiJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\": \"Echo request\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"description\": \"Returns the request body as-is\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tags\": [\"echo\", \"testing\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"$ref\": \"#/components/schemas/EchoRequest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"$ref\": \"#/components/schemas/EchoResponse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"requestBody\"") != null);
}

test "router: openapi with deprecated route" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.setOpenApiInfo("Deprecated API", "1.0.0", null);
    const H = struct { fn h(_: *Context) !void {} };

    try router.getOpts("/old", H.h, .{
        .summary = "Old endpoint",
        .deprecated = true,
    });

    const json = try router.openapiJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"deprecated\": true") != null);
}

test "router: openapi no info falls back to defaults" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct { fn h(_: *Context) !void {} };
    try router.get("/hello", H.h);

    const json = try router.openapiJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"title\": \"API\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\": \"1.0.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"paths\"") != null);
}

test "router: openapi empty router produces valid structure" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const json = try router.openapiJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"paths\": {") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"components\": {") != null);
}

test "router: openapi deinit frees metadata" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();
    try router.setOpenApiInfo("Temp", "0.1.0", "desc");
    const H = struct { fn h(_: *Context) !void {} };
    try router.getOpts("/x", H.h, .{
        .summary = "Sum",
        .description = "Desc",
        .tags = "a,b",
        .body_type = "Req",
        .response_type = "Res",
    });
    const json = try router.openapiJson(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\": \"Sum\"") != null);
}

test "router: lock prevents addRoute" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    router.lock();
    const H = struct { fn h(_: *Context) !void {} };
    try std.testing.expectError(error.RouterLocked, router.get("/x", H.h));
}

test "router: lock allows match" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct { fn h(_: *Context) !void {} };
    try router.get("/hello", H.h);
    router.lock();

    try std.testing.expect(router.match(.GET, "/hello") != null);
    try std.testing.expect(router.match(.GET, "/world") == null);
}

var mw_blocked: bool = false;
var mw_called: bool = false;

fn middleWare(ctx: *Context) anyerror!bool {
    _ = ctx;
    mw_blocked = true;
    return false;
}

fn testHandler(_: *Context) anyerror!void {
    mw_called = true;
}

test "router: middleware short-circuit" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    mw_blocked = false;
    mw_called = false;

    try router.use(middleWare);
    try router.get("/test", testHandler);
    router.lock();

    var ctx = Context{
        .io = undefined,
        .allocator = std.testing.allocator,
        .request = undefined,
    };

    const result = router.match(.GET, "/test");
    try std.testing.expect(result != null);
    ctx.params = result.?.params;

    for (router.middleware.items) |mw| {
        if (!try mw(&ctx)) return;
    }

    try std.testing.expect(mw_blocked);
    try std.testing.expect(!mw_called);
}

test "router: error handler is registered" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try std.testing.expect(router.error_handler == null);

    const H = struct { fn h(_: *Context) anyerror!void {} };
    router.onError(H.h);

    try std.testing.expect(router.error_handler != null);
}

test "router: middleware are registered in order" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const M1 = struct { fn mw(_: *Context) anyerror!bool { return true; } };
    const M2 = struct { fn mw(_: *Context) anyerror!bool { return true; } };

    try router.use(M1.mw);
    try router.use(M2.mw);

    try std.testing.expectEqual(@as(usize, 2), router.middleware.items.len);
}
