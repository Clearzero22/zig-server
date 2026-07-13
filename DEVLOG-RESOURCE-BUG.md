# Resource Routing 调试记录

## 问题

实现 `router.resource(prefix, ctrl)` 方法——传入一个 struct，自动检测其中的 handler 函数并注册 CRUD 路由。

## 调试过程

### 初次实现

使用 `comptime ctrl: anytype` 接收 struct 实例，`@TypeOf(ctrl)` 获取类型，`@hasDecl(T, "list")` 检测函数声明：

```zig
pub fn resource(self, prefix, comptime ctrl: anytype) !void {
    const T = @TypeOf(ctrl);
    if (@hasDecl(T, "list")) try self.get(prefix, T.list);
    if (@hasDecl(T, "create")) try self.post(prefix, T.create);
    // ...
}
```

### 症状

测试中 `router.match(.GET, "/posts")` 返回 null。直接调用 `router.get("/posts", Handler)` 则正常工作。

### 排查清单

| 尝试 | 结果 |
|------|------|
| `ctrl.list` → `T.list` | 无效 |
| 显式 `@as(Handler, T.list)` 转型 | 无效 |
| inline 方式直接写测试里 | **通过** |
| 用 wrapper 函数 `fn wrap(ctx) T.list(ctx)` | 无效 |
| 整个 `resource` 内联展开（`self.routes.append` + `parseSegments` 全写出来） | 无效 |
| 把 struct 定义移到 file-level | 无效 |
| `comptime T: type` 传类型而非实例 | 无效 |

关键线索：同一段逻辑，写在测试函数体内就通过，打包成 generic function 就不通过。

### 根因定位

加 `std.debug.print` 追踪：

```
RESOURCE CALLED: prefix=/posts locked=false
RESOURCE DONE: routes.len=0
```

**没有 "has list" 日志** —— 说明 `@hasDecl(T, "list")` 在编译期返回 `false`，整个 if 分支被编译器丢弃。

写隔离测试验证：

```zig
// test_hasdecl_mod1.zig
const Ctrl = struct { fn list(_: *void) !void {} };
std.debug.print("{}", .{mod2.process(Ctrl)});
// 输出: false
```

```zig
// test_hasdecl_mod2.zig
pub fn process(comptime T: type) bool {
    return @hasDecl(T, "list");
}
```

**结论：这个 Zig 0.16.0 定制版中，`@hasDecl` 和 `@typeInfo` 在跨模块时失效。** 当 inline struct 类型被作为 `comptime T: type` 参数传给另一个文件的函数时，编译器丢失了该类型的 declaration 信息。

### 解决方案

用 `@hasField` 替代 `@hasDecl`。`@hasField` 检查的是 struct 的 field（运行时数据），在跨模块场景下工作正常。

```zig
pub fn resource(self, prefix, handlers: anytype) !void {
    if (@hasField(@TypeOf(handlers), "list")) try self.get(prefix, handlers.list);
    if (@hasField(@TypeOf(handlers), "create")) try self.post(prefix, handlers.create);
    // ...
}
```

调用方式从：

```zig
// 不工作
router.resource("/posts", Ctrl{});
// 也不工作（跨模块 @hasDecl 失效）
router.resource("/posts", Ctrl);
```

改为：

```zig
// 工作
router.resource("/posts", .{
    .list = Ctrl.list,
    .show = Ctrl.show,
    .create = Ctrl.create,
});
```

## 关键教训

1. **`@hasDecl`** 依赖编译器的 declaration 元数据，跨模块传递 comptime 类型时元数据会丢失
2. **`@hasField`** 基于 struct 的 field 信息，跨模块稳定
3. 如果需要在另一个文件中推断一个类型有哪些方法，不要用 `@hasDecl` / `@typeInfo`，而是让调用方显式传递函数指针
4. `std.debug.print` 在调试 comptime 分支是否被排除时极其有效——看不到日志就说明编译期已经把分支裁掉了

## 影响范围

- 该 bug 影响所有跨模块使用 `@hasDecl` / `@typeInfo` 做声明反射的场景
- 任何 Zig 框架库如果依赖调用方传入的 struct 类型的 decl 信息，都可能遇到此问题
- 建议在框架代码中统一使用 `@hasField` + 显式字段传递模式

## 测试结果

最终 79/79 测试全部通过，`resource`, `mount`, `version` 三个新特性全部正常工作。
