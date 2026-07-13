# 数据库

框架内置 SQLite 封装，基于 [zig-sqlite](https://github.com/vrischmann/zig-sqlite)。

## 初始化

```zig
const fw = @import("zig-server");

// 文件数据库
var db = try fw.db.init("data.db");
defer fw.db.deinit(&db);

// 内存数据库（测试用）
var db = try fw.db.initMemory();
defer fw.db.deinit(&db);
```

SQLite 使用 `Serialized` 线程模式以支持多线程访问。

## CRUD 示例

```zig
// 建表
try db.exec("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)", .{}, .{});

// 插入
try db.exec("INSERT INTO users (name) VALUES ($1)", .{}, .{ .name = "Alice" });

// 查询
var stmt = try db.prepare("SELECT id, name FROM users");
defer stmt.deinit();
try stmt.bind(.{}, .{});
var rows = try stmt.query(.{}, .{});
while (try rows.next(.{})) |row| {
    std.debug.print("id={d} name={s}\n", .{ row.@as(i64, 0), row.@as([]const u8, 1) });
}

// 参数化查询
var stmt2 = try db.prepare("SELECT * FROM users WHERE id = $1");
defer stmt2.deinit();
try stmt2.bind(.{}, .{ @as(i64, 42) });
```

## 与路由结合

参考 `examples/14_db.zig` (端口 8014) 的完整 CRUD 实现：

- `GET /users` — 列表查询
- `GET /users/:id` — 单个查询
- `POST /users` — 创建（JSON body）
- `PUT /users/:id` — 更新
- `DELETE /users/:id` — 删除
