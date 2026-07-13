# 服务器

## 基本服务器

```zig
const io = std.Io.Threaded.global_single_threaded.io();
var server = try fw.Server.init(io, &router);
try server.listen("0.0.0.0:8080");
```

- 每来一个连接，创建一个新线程处理
- 线程自动 `detach()`，不需手动管理

## 线程池服务器

```zig
var server = try fw.Server.initPool(io, &router, 4);
try server.listen("0.0.0.0:8080");
```

- 启动指定数量的工作线程
- 连接通过无锁环形队列分发给工作者
- 适用于高并发场景

### 线程池配置

```zig
// 4 个工作者
var server = try fw.Server.initPool(io, &router, 4);

// 8 个工作者
var server = try fw.Server.initPool(io, &router, 8);
```

## 优雅关闭

```zig
server.shutdown();
```

- 设置 `running = false`
- 拨入一个虚拟连接以解除 `accept` 阻塞
- 自动清理线程池资源

## 生命周期

```zig
pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.get("/hello", helloHandler);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    // 在信号处理中调用 server.shutdown()
    try server.listen("0.0.0.0:8080");
}
```

## 注意事项

- `router.lock()` 在 `listen()` 内部自动调用，之后不能再添加路由
- 建议使用 `ArenaAllocator`，`router.deinit()` 会释放所有资源
- 线程池服务器和线程-连接服务器二选一

## 完整示例

参考 `examples/15_server.zig` (端口 8015)。
