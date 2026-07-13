# 中间件

## 中间件类型

中间件是一个能够返回 `bool` 的异步函数。返回 `true` 继续执行链，返回 `false` 则短接：

```zig
pub const Middleware = *const fn (ctx: *Context) anyerror!bool;
```

## 全局中间件

通过 `router.use()` 注册，对所有路由生效：

```zig
try router.use(logger.handler);
try router.use(authMiddleware);
```

执行顺序：按注册顺序，在所有路由级中间件 **之前**。

## 路由级中间件

通过 `RouteOptions.middleware` 对单一路由生效：

```zig
try router.getOpts("/admin", adminHandler, .{
    .middleware = &.{authMiddleware},
});
```

## 组级中间件

通过 `group.use()` 对组内所有路由生效：

```zig
var v1 = router.group("/api/v1");
try v1.use(authMiddleware);
try v1.get("/users", usersHandler);        // 有 auth 中间件
try v1.getOpts("/posts", postsHandler, .{  // 组级 + 路由级中间件合并
    .middleware = &.{corsMiddleware},
});
```

执行顺序：全局 → **组级** → 路由级 → 限速 → Handler。

## 后处理钩子

`router.after()` 注册 handler 执行后的回调，适合添加响应头、记录耗时等：

```zig
fn addTimingHeader(ctx: *fw.Context) void {
    // handler 已执行完毕
}

try router.after(addTimingHeader);
```

后处理通过 `defer` 执行，即使 handler 抛出错误也会运行。

## 错误处理器

`onError` 捕获所有路由处理器中抛出的错误（不捕获中间件的错误）：

```zig
router.onError(recovery.handler);
// 或自定义：
router.onError(myErrorHandler);
```

## 内置中间件

### Logger

记录每个请求的方法和路径到 stdout。

```zig
const fw = @import("zig-server");
try router.use(fw.logger.handler);
```

### Recovery

当路由处理器出错时，返回 500 JSON 响应，避免进程崩溃。

```zig
router.onError(fw.recovery.handler);
```

### CORS

跨域资源共享支持，可在全局或路由级别配置：

```zig
// 全局 CORS
try router.use(fw.cors.handler);

// 路由级 CORS（通过 RouteOptions）
try router.getOpts("/api/data", dataHandler, .{
    .cors_origin = "https://myapp.com",
});
```

## 中间件链执行顺序

1. 全局中间件（`router.middleware`，按注册顺序）
2. 组级中间件（`group.middleware`，按注册顺序）
3. 路由级中间件（`route.middleware`，按数组顺序）
4. 速率限制检查
5. 路由处理器
6. 后处理钩子（`router.after_middleware`，handler 之后执行）

## 自定义全局中间件

```zig
fn authMiddleware(ctx: *fw.Context) !bool {
    // 验证逻辑...
    if (!authorized) {
        try ctx.text(.forbidden, "Forbidden");
        return false;  // 短接链
    }
    return true;  // 继续处理
}
```

## 完整示例

- `examples/03_middleware.zig` (端口 8003) — 路由级中间件
- `examples/04_cors.zig` (端口 8004) — CORS 配置
- `examples/06_version.zig` (端口 8006) — 组级中间件 + 后处理
- `examples/11_global_middleware.zig` (端口 8011) — 全局中间件 + 后处理
