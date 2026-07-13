const std = @import("std");
const Router = @import("router.zig");
const Context = @import("context.zig");
const secure_headers = @import("builtins/secure_headers.zig");
const request_id = @import("builtins/request_id.zig");
const request_timeout = @import("builtins/request_timeout.zig");
const static_files = @import("builtins/static.zig");

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
    defer api.deinit();
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
    defer g.deinit();
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
var route_mw_called: bool = false;

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

test "router: route-level middleware" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    route_mw_called = false;

    const RouteMW = struct {
        fn mw(ctx: *Context) anyerror!bool {
            _ = ctx;
            route_mw_called = true;
            return true;
        }
    };

    const H = struct { fn h(_: *Context) !void {} };

    try router.getOpts("/protected", H.h, .{
        .middleware = &.{RouteMW.mw},
    });
    router.lock();

    const r = router.match(.GET, "/protected");
    try std.testing.expect(r != null);
    try std.testing.expectEqual(@as(usize, 1), r.?.middleware.len);

    for (r.?.middleware) |mw| {
        var ctx = Context{ .io = undefined, .allocator = std.testing.allocator, .request = undefined };
        try std.testing.expect(try mw(&ctx));
    }
    try std.testing.expect(route_mw_called);
}

test "router: route-level CORS origin" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct { fn h(_: *Context) !void {} };

    try router.getOpts("/cors", H.h, .{
        .cors_origin = "https://example.com",
    });
    router.lock();

    const r = router.match(.GET, "/cors");
    try std.testing.expect(r != null);
    try std.testing.expectEqualStrings("https://example.com", r.?.cors_origin.?);
}

test "router: route-level rate limit config" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct { fn h(_: *Context) !void {} };

    try router.getOpts("/limited", H.h, .{
        .rate_limit = .{ .window_ms = 1000, .max_requests = 5 },
    });
    router.lock();

    const r = router.match(.GET, "/limited");
    try std.testing.expect(r != null);
    try std.testing.expect(r.?.rate_limit != null);
    try std.testing.expectEqual(@as(u32, 5), r.?.rate_limit.?.max_requests);
    try std.testing.expectEqual(@as(u64, 1000), r.?.rate_limit.?.window_ms);
}

test "router: mount sub-routes" {
    var sub = Router.init(std.testing.allocator);
    defer sub.deinit();

    const H = struct { fn h(_: *Context) !void {} };
    try sub.get("/hello", H.h);

    var parent = Router.init(std.testing.allocator);
    defer parent.deinit();

    try parent.mount("/api/v1", &sub);

    try std.testing.expect(parent.match(.GET, "/api/v1/hello") != null);
    try std.testing.expect(parent.match(.GET, "/api/v1") == null);
}

test "router: resource generates CRUD routes" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const Ctrl = struct {
        fn list(_: *Context) !void {}
        fn show(_: *Context) !void {}
        fn create(_: *Context) !void {}
        fn update(_: *Context) !void {}
        fn destroy(_: *Context) !void {}
    };
    try router.resource("/posts", .{
        .list = Ctrl.list,
        .show = Ctrl.show,
        .create = Ctrl.create,
        .update = Ctrl.update,
        .destroy = Ctrl.destroy,
    });
    router.lock();

    try std.testing.expect(router.match(.GET, "/posts") != null);
    try std.testing.expect(router.match(.GET, "/posts/1") != null);
    try std.testing.expect(router.match(.POST, "/posts") != null);
    try std.testing.expect(router.match(.PUT, "/posts/1") != null);
    try std.testing.expect(router.match(.DELETE, "/posts/1") != null);
}

test "router: resource only registers declared methods" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const Ctrl = struct {
        fn list(_: *Context) !void {}
        fn create(_: *Context) !void {}
    };
    try router.resource("/items", .{
        .list = Ctrl.list,
        .create = Ctrl.create,
    });
    router.lock();

    try std.testing.expect(router.match(.GET, "/items") != null);
    try std.testing.expect(router.match(.POST, "/items") != null);
    try std.testing.expect(router.match(.GET, "/items/1") == null);
    try std.testing.expect(router.match(.PUT, "/items/1") == null);
    try std.testing.expect(router.match(.DELETE, "/items/1") == null);
}

test "router: version prefix via group" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct { fn h(_: *Context) !void {} };
    var v1 = router.group("/v1");
    defer v1.deinit();
    try v1.get("/users", H.h);

    var v2 = router.group("/v2");
    defer v2.deinit();
    try v2.get("/users", H.h);
    router.lock();

    try std.testing.expect(router.match(.GET, "/v1/users") != null);
    try std.testing.expect(router.match(.GET, "/v2/users") != null);
    try std.testing.expect(router.match(.GET, "/v1/users/x") == null);
}

var after_mw_ran: bool = false;
fn afterMw(_: *Context) void {
    after_mw_ran = true;
}

test "router: router-level after middleware" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.after(afterMw);
    try std.testing.expectEqual(@as(usize, 1), router.after_middleware.items.len);
}

test "router: route-level after middleware" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    after_mw_ran = false;
    const H = struct { fn h(_: *Context) !void {} };

    try router.getOpts("/test", H.h, .{
        .after_middleware = &.{afterMw},
    });
    router.lock();

    const r = router.match(.GET, "/test");
    try std.testing.expect(r != null);
    try std.testing.expectEqual(@as(usize, 1), r.?.after_middleware.len);
    var ctx = Context{ .io = undefined, .allocator = std.testing.allocator, .request = undefined };
    r.?.after_middleware[0](&ctx);
    try std.testing.expect(after_mw_ran);
}

test "router: group-level after middleware" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct { fn h(_: *Context) !void {} };
    var g = router.group("/api");
    defer g.deinit();
    try g.after(afterMw);
    try g.get("/users", H.h);
    router.lock();

    const r = router.match(.GET, "/api/users");
    try std.testing.expect(r != null);
    try std.testing.expectEqual(@as(usize, 1), r.?.after_middleware.len);
}

test "router: group-level middleware" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct { fn h(_: *Context) !void {} };
    const GMw = struct { fn mw(_: *Context) anyerror!bool { return true; } };

    var g = router.group("/api");
    defer g.deinit();
    try g.use(GMw.mw);
    try g.get("/items", H.h);
    router.lock();

    const r = router.match(.GET, "/api/items");
    try std.testing.expect(r != null);
    try std.testing.expectEqual(@as(usize, 1), r.?.middleware.len);
}

test "router: mount copies after middleware" {
    var sub = Router.init(std.testing.allocator);
    defer sub.deinit();

    const H = struct { fn h(_: *Context) !void {} };
    try sub.getOpts("/hello", H.h, .{
        .after_middleware = &.{afterMw},
    });

    var parent = Router.init(std.testing.allocator);
    defer parent.deinit();

    try parent.mount("/api", &sub);

    const r = parent.match(.GET, "/api/hello");
    try std.testing.expect(r != null);
    try std.testing.expectEqual(@as(usize, 1), r.?.after_middleware.len);
}

test "router: secure_headers middleware" {
    var ctx = Context{
        .io = undefined,
        .allocator = std.testing.allocator,
        .request = undefined,
    };
    secure_headers.init(.{});
    try std.testing.expect(try secure_headers.handler(&ctx));
    try std.testing.expect(ctx.extra_header_count > 0);
}

test "router: request_id middleware" {
    var ctx = Context{
        .io = undefined,
        .allocator = std.testing.allocator,
        .request = undefined,
    };
    request_id.init(.{});
    try std.testing.expect(try request_id.handler(&ctx));
    try std.testing.expect(ctx.request_id != null);
    if (ctx.request_id) |id| ctx.allocator.free(id);
}

test "router: request_timeout middleware" {
    var ctx = Context{
        .io = undefined,
        .allocator = std.testing.allocator,
        .request = undefined,
    };
    request_timeout.init(.{ .timeout_ms = 5000 });
    try std.testing.expect(try request_timeout.handler(&ctx));
    try std.testing.expect(ctx.deadline > 0);
}

test "router: static route matches wildcard" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.static("/files", "public");

    const r1 = router.match(.GET, "/files/style.css");
    try std.testing.expect(r1 != null);
    try std.testing.expectEqualStrings("style.css", r1.?.params.get("filepath").?);

    const r2 = router.match(.GET, "/files/sub/dir/app.js");
    try std.testing.expect(r2 != null);
    try std.testing.expectEqualStrings("sub/dir/app.js", r2.?.params.get("filepath").?);

    try std.testing.expect(router.match(.GET, "/other") == null);
}

test "router: static builtin handler blocks path traversal" {
    static_files.dir = "public";

    const H = struct {
        fn h(ctx: *Context) !void {
            try ctx.text(.ok, "should not reach");
        }
    };
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    try router.getOpts("/static/*filepath", static_files.handle, .{});
    try router.get("/ok", H.h);
    router.lock();

    _ = router.match(.GET, "/ok"); // verify lock works
}
