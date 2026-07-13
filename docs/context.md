# Context API

`Context` 封装了当前请求的所有信息，包括请求头、路径参数、查询参数、响应辅助方法等。

## 响应辅助

### 纯文本

```zig
try ctx.text(.ok, "Hello, World!");
try ctx.text(.not_found, "Not Found");
```

### JSON

```zig
// 直接传递 JSON 字符串
try ctx.json(.ok, "{\"key\": \"value\"}");

// 从 Zig 结构体自动序列化
try ctx.jsonTyped(ctx.allocator, .ok, .{ .name = "Zig", .version = 1 });
```

### HTML

```zig
try ctx.html(.ok, "<h1>Hello</h1><p>World</p>");
```

### 重定向

```zig
try ctx.redirect(.found, "/new-location");
try ctx.redirect(.moved_permanently, "https://example.com");
```

### 错误响应

```zig
try ctx.internalError(ctx.allocator, someError);
// → {"error":"Internal Server Error","status":500}
```

## 请求数据

### 读取请求体

```zig
const body = try ctx.readBody();
defer ctx.allocator.free(body);
// body 是原始字节数组
```

### 路径参数

```zig
const id = ctx.params.get("id") orelse "unknown";
const name = ctx.params.get("name") orelse "";
```

### 查询参数

```zig
const q = ctx.query.get("q") orelse "";
const page = ctx.query.get("page") orelse "1";
```

### 最大请求体大小

默认 10MB，可通过修改 `ctx.max_body_size` 覆盖。

## CORS 来源

当路由或中间件设置了 CORS 来源时，`ctx.cors_origin` 会自动填充，所有响应都会带上 `access-control-allow-origin` 头。

## 参数限制

路径参数和查询参数最多各 16 个（`MAX_PARAMS` 常量）。

## 完整示例

参考 `examples/13_context_responses.zig` (端口 8013)。
