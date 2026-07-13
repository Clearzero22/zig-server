# 高级功能

## Resource 路由

通过 `router.resource()` 一键生成 RESTful CRUD 路由：

```zig
try router.resource("/posts", .{
    .list    = PostCtrl.list,      // GET    /posts
    .show    = PostCtrl.show,      // GET    /posts/:id
    .create  = PostCtrl.create,    // POST   /posts
    .update  = PostCtrl.update,    // PUT    /posts/:id
    .destroy = PostCtrl.destroy,   // DELETE /posts/:id
});
```

各字段可选，只传需要的即可：

```zig
try router.resource("/posts", .{
    .list = PostCtrl.list,
    .create = PostCtrl.create,
});
```

完整的控制器示例：

```zig
const PostCtrl = struct {
    fn list(ctx: *fw.Context) !void { ... }
    fn show(ctx: *fw.Context) !void {
        const id = ctx.params.get("id") orelse "unknown";
        // 根据 id 查询并返回
    }
    fn create(ctx: *fw.Context) !void {
        const body = try ctx.readBody();
        defer ctx.allocator.free(body);
        // 解析 body，创建资源
    }
    fn update(ctx: *fw.Context) !void { ... }
    fn destroy(ctx: *fw.Context) !void { ... }
};
```

参考 `examples/01_resource.zig` (端口 8001)。

## 子路由挂载

通过 `router.mount()` 将一个完整路由器挂载到路径前缀下，子路由的全局中间件自动生效：

```zig
// 创建管理后台子路由器
var admin = fw.Router.init(allocator);
defer admin.deinit();
try admin.use(adminAuth);              // 子路由器全局中间件
try admin.resource("/users", .{ ... });
try admin.resource("/posts", .{ ... });

// 挂载到主路由器
try router.mount("/admin", &admin);
// 结果：
// GET  /admin/users       (带 adminAuth 中间件)
// GET  /admin/users/:id   (带 adminAuth 中间件)
// GET  /admin/posts       (带 adminAuth 中间件)
// ...
```

挂载时，子路由器的全局中间件会合并到每条路由的中间件列表中。

参考 `examples/02_mount.zig` (端口 8002)。

## 自定义匹配器

通过 `RouteOptions` 可以添加 host 和 header 匹配条件，只有满足条件的请求才会命中路由：

### Host 匹配

```zig
try router.getOpts("/admin", adminHandler, .{
    .host = "admin.example.com",
});
// 只有在 Host: admin.example.com 时才会匹配
```

### Header 匹配

```zig
try router.getOpts("/internal", internalHandler, .{
    .headers = &.{
        .{ .name = "X-Internal", .value = "true" },
        .{ .name = "X-API-Key", .value = "secret" },
    },
});
// 必须同时满足所有 header 条件
```

### Host + Header 组合

```zig
try router.getOpts("/debug", debugHandler, .{
    .host = "dev.example.com",
    .headers = &.{ .{ .name = "X-Debug", .value = "1" } },
});
```

参考 `examples/10_custom_matchers.zig` (端口 8010)。

## 速率限制

```zig
try router.getOpts("/api/data", dataHandler, .{
    .rate_limit = .{
        .max_requests = 30,       // 30 次请求
        .window_ms = 60_000,      // 每个窗口 60 秒
    },
});
```

- 基于请求 URL 的计数器
- 超限后返回 HTTP 429

参考 `examples/05_rate_limit.zig` (端口 8005)。

## CORS 路由级配置

路由级 CORS 覆盖全局 CORS 配置：

```zig
try router.getOpts("/api/public", publicHandler, .{
    .cors_origin = "*",
});

try router.postOpts("/api/internal", internalHandler, .{
    .cors_origin = "https://dashboard.example.com",
});
```

参考 `examples/04_cors.zig` (端口 8004)。

## 路由版本控制

通过路由组实现 API 版本控制：

```zig
var v1 = router.group("/v1");
v1.get("/users", v1UsersHandler);

var v2 = router.group("/v2");
v2.get("/users", v2UsersHandler);
v2.getOpts("/posts", v2PostsHandler, .{
    .rate_limit = .{ .max_requests = 100, .window_ms = 60_000 },
});
```

参考 `examples/06_version.zig` (端口 8006)。

## 综合示例

`examples/07_comprehensive.zig` (端口 8007) 同时演示了：

- 公开路由
- Resource 路由 + Admin 中间件（通过 mount）
- 版本组 + CORS + 速率限制
- 线程池服务器
