# 路由

## 路径模式

支持 6 种路径匹配模式：

| 模式 | 语法 | 示例 | 匹配 |
|---|---|---|---|
| 静态 | 纯字符串 | `/about` | `/about` |
| 路径参数 | `:name` | `/users/:id` | `/users/42` |
| 可选参数 | `:name?` | `/pages/:name?` | `/pages`, `/pages/contact` |
| 通配符 | `*path` | `/files/*path` | `/files/a/b/c.txt` |
| 正则 | `(\\d+)` | `/items/(\\d+)` | `/items/123` (不匹配 `/items/abc`) |
| 多参数混合 | `:a+:b` | `/file/:dir+:name` | `/file/photos.vacation` （以 `.` 分隔） |

```zig
router.get("/about", staticHandler);           // 静态
router.get("/users/:id", userHandler);          // 路径参数
router.get("/pages/:name?", pageHandler);       // 可选参数
router.get("/files/*path", fileHandler);        // 通配符
router.get("/items/(\\d+)", numericHandler);    // 正则验证
router.get("/file/:dir+:name", multiHandler);   // 多参数混合
```

## HTTP 方法

每个方法都有标准版和 `Opts` 版：

| 快捷方法 | Opts 变体 | HTTP 方法 |
|---|---|---|
| `get` | `getOpts` | GET |
| `post` | `postOpts` | POST |
| `put` | `putOpts` | PUT |
| `delete` | `deleteOpts` | DELETE |
| `patch` | `patchOpts` | PATCH |

```zig
// 标准用法
try router.get("/users", listHandler);
try router.post("/users", createHandler);

// 带选项的用法
try router.getOpts("/users/:id", showHandler, .{
    .name = "user.show",
    .priority = 5,
});
```

## RouteOptions

```zig
pub const RouteOptions = struct {
    name: ?[]const u8 = null,
    priority: i32 = 0,
    host: ?[]const u8 = null,
    headers: ?[]const HeaderMatch = null,
    middleware: ?[]const Middleware = null,
    cors_origin: ?[]const u8 = null,
    rate_limit: ?RateLimitConfig = null,

    // OpenAPI 元数据
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    tags: ?[]const u8 = null,
    deprecated: bool = false,
    body_type: ?[]const u8 = null,
    response_type: ?[]const u8 = null,
};
```

## 路由组

```zig
var api = router.group("/api/v1");
api.get("/users", apiUsersHandler);        // → GET /api/v1/users
api.post("/users", apiCreateHandler);       // → POST /api/v1/users
api.getOpts("/posts", apiPostsHandler, .{  // → GET /api/v1/posts
    .cors_origin = "*",
});
```

## 命名路由与反向路由

```zig
// 注册命名路由
try router.getOpts("/users/:id/posts/:pid", postHandler, .{
    .name = "post",
});

// 反向生成 URL
const url = try router.url("post", .{ .id = "42", .pid = "1" });
// → "/users/42/posts/1"
```

## 路由优先级

通过 `priority` 控制匹配顺序（值越大越靠前）：

```zig
try router.getOpts("/special", specialHandler, .{ .priority = 10 });
try router.getOpts("/catchall", catchAllHandler, .{ .priority = -1 });
```

默认优先级为 `0`。通配符路由会自动排在静态路由之后。

## 冲突检测

相同 HTTP 方法 + 相同路径注册会返回 `error.RouteConflict`：

```zig
try router.get("/users", handlerA);
try router.get("/users", handlerB);  // 返回 error.RouteConflict
```

## 完整示例

参考 `examples/08_path_patterns.zig` (端口 8008) 和 `examples/09_reverse_routing.zig` (端口 8009)。
