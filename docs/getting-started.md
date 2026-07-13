# 快速开始

## 简介

zig-server 是一个基于 `std.http.Server` 构建的 Zig 0.16.0 Web 框架，提供路由、中间件、CORS、线程池和 OpenAPI/Swagger 文档生成。

## 安装

### Zig 包管理器（推荐）

```bash
zig fetch --save https://github.com/Clearzero22/zig-server/archive/master.tar.gz
```

在 `build.zig` 中：

```zig
const exe = b.addExecutable(.{ .name = "my-app", .root_module = b.createModule(...) });
const zs = b.dependency("zig_server", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zig-server", zs.module("zig-server"));
```

### Git Submodule

```bash
git submodule add https://github.com/Clearzero22/zig-server.git lib/zig-server
```

```zig
const fw = @import("lib/zig-server/src/framework.zig");
```

## 最小服务器

```zig
const std = @import("std");
const fw = @import("zig-server");

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.get("/hello", helloHandler);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.init(io, &router);
    try server.listen("0.0.0.0:8080");
}

fn helloHandler(ctx: *fw.Context) !void {
    try ctx.text(.ok, "Hello, World!");
}
```

```bash
zig build run
# 输出: Listening on 0.0.0.0:8080
```

## 示例一览

所有示例都在 `examples/` 目录下，可通过 `zig build ex-<name>` 运行：

| 命令 | 端口 | 功能 |
|---|---|---|
| `zig build ex-resource` | 8001 | RESTful CRUD resource 路由 |
| `zig build ex-mount` | 8002 | 子路由挂载 |
| `zig build ex-middleware` | 8003 | 路由级中间件 |
| `zig build ex-cors` | 8004 | CORS 配置 |
| `zig build ex-rate-limit` | 8005 | 速率限制 |
| `zig build ex-version` | 8006 | 路由版本控制 |
| `zig build ex-comprehensive` | 8007 | 综合演示 |
| `zig build ex-path-patterns` | 8008 | 路径模式 |
| `zig build ex-reverse-routing` | 8009 | 反向路由 |
| `zig build ex-custom-matchers` | 8010 | 自定义匹配器 |
| `zig build ex-global-middleware` | 8011 | 全局中间件 |
| `zig build ex-openapi` | 8012 | OpenAPI/Swagger |
| `zig build ex-context` | 8013 | Context 响应 API |
| `zig build ex-db` | 8014 | SQLite CRUD |
| `zig build ex-server` | 8015 | 服务器配置 |

## 项目结构

```
src/
├── framework.zig      — 公开 API 入口
├── router.zig         — 路由器, Route, Group, RouteOptions, OpenAPI
├── context.zig        — 请求上下文，响应辅助
├── server.zig         — TCP 服务器，优雅关闭
├── threadpool.zig     — 线程池
├── dispatch.zig       — 请求分发调度
├── middleware.zig     — 中间件类型定义
├── builtins/
│   ├── cors.zig       — CORS 中间件
│   ├── logger.zig     — 请求日志
│   ├── recovery.zig   — 500 错误恢复
│   └── swagger.zig    — Swagger UI + OpenAPI 处理器
│   └── db/sqlite.zig  — SQLite 封装
└── *test.zig          — 测试文件
```

## 构建 & 测试

```bash
zig build              # 构建项目
zig build run          # 构建并运行 (0.0.0.0:8080)
zig build test         # 运行全部测试
zig test src/router.test.zig  # 运行特定测试
```
