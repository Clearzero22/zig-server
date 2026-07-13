# OpenAPI / Swagger

框架内置 OpenAPI 3.0.3 规范和 Swagger UI 支持。

## 快速设置

```zig
const fw = @import("zig-server");

// 1. 设置 API 信息
try router.setOpenApiInfo("My API", "1.0.0", "我的 API 描述");

// 2. 注册 Swagger 处理器
try router.get("/docs", fw.swagger.docsHandler);
try router.get("/openapi.json", fw.swagger.openapiHandler);
```

访问 `http://localhost:8080/docs` 查看 Swagger UI。

## 路由元数据

通过 `RouteOptions` 添加每条路由的 API 文档：

```zig
try router.postOpts("/echo", echoHandler, .{
    .summary = "Echo 请求",
    .description = "返回请求体作为响应",
    .tags = "echo,testing",
    .body_type = "EchoRequest",
    .response_type = "EchoResponse",
    .deprecated = false,
});

try router.getOpts("/users", listHandler, .{
    .summary = "用户列表",
    .description = "返回所有用户的列表",
    .tags = "users",
    .response_type = "User[]",
});
```

### OpenAPI 映射

| RouteOptions 字段 | OpenAPI 字段 |
|---|---|
| `summary` | `operation.summary` |
| `description` | `operation.description` |
| `tags` | `operation.tags`（逗号分隔） |
| `deprecated` | `operation.deprecated` |
| `body_type` | `requestBody.content['application/json'].schema.$ref` |
| `response_type` | `responses.200.content['application/json'].schema.$ref` |

## 路径参数

路径参数自动检测并映射到 OpenAPI `parameters`：

- `:id` → path 参数，required: true
- `:name?` → path 参数，required: false
- `*path` → path 参数
- `(\d+)` → path 参数 + pattern 约束
- `:a+:b` → 多个 path 参数

## 自定义 OpenAPI JSON

```zig
const json = try router.openapiJson(ctx.allocator);
defer ctx.allocator.free(json);
// json 是完整的 OpenAPI 3.0.3 规范
```

## 完整示例

参考 `examples/12_openapi_swagger.zig` (端口 8012)。
