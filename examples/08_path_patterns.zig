const std = @import("std");
const fw = @import("zig-server");

const H = struct {
    pub fn static(ctx: *fw.Context) !void { try ctx.text(.ok, "static"); }
    pub fn user(ctx: *fw.Context) !void {
        const id = ctx.params.get("id") orelse "?";
        try ctx.text(.ok, try std.fmt.allocPrint(ctx.allocator, "user {s}", .{id}));
    }
    pub fn page(ctx: *fw.Context) !void {
        const name = ctx.params.get("name") orelse "index";
        try ctx.text(.ok, try std.fmt.allocPrint(ctx.allocator, "page {s}", .{name}));
    }
    pub fn file(ctx: *fw.Context) !void {
        const path = ctx.params.get("path") orelse "";
        try ctx.text(.ok, try std.fmt.allocPrint(ctx.allocator, "file {s}", .{path}));
    }
    pub fn numeric(ctx: *fw.Context) !void {
        try ctx.text(.ok, "matched \\d+");
    }
    pub fn multi(ctx: *fw.Context) !void {
        const dir = ctx.params.get("dir") orelse "?";
        const name = ctx.params.get("name") orelse "?";
        try ctx.text(.ok, try std.fmt.allocPrint(ctx.allocator, "dir={s} name={s}", .{ dir, name }));
    }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.get("/about", H.static);
    try router.get("/users/:id", H.user);
    try router.get("/pages/:name?", H.page);
    try router.get("/files/*path", H.file);
    try router.get("/items/(\\d+)", H.numeric);
    try router.get("/file/:dir+:name", H.multi);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌──────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 08_path_patterns — 路径模式                         │\n", .{});
    std.debug.print("├──────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("│  GET /about           — 静态匹配                     │\n", .{});
    std.debug.print("│  GET /users/:id       — 路径参数                     │\n", .{});
    std.debug.print("│  GET /pages/:name?    — 可选参数 (无 name → /pages)  │\n", .{});
    std.debug.print("│  GET /files/*path     — wildcard 通配符              │\n", .{});
    std.debug.print("│  GET /users/(\\d+)     — 正则匹配 (仅数字)             │\n", .{});
    std.debug.print("│  GET /file/:dir+:name   — 多参数混合 (用 . 分隔)     │\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("│  curl http://localhost:8008/about                    │\n", .{});
    std.debug.print("│  curl http://localhost:8008/users/42                 │\n", .{});
    std.debug.print("│  curl http://localhost:8008/pages                    │\n", .{});
    std.debug.print("│  curl http://localhost:8008/pages/contact            │\n", .{});
    std.debug.print("│  curl http://localhost:8008/files/css/style.css      │\n", .{});
    std.debug.print("│  curl http://localhost:8008/items/123                │\n", .{});
    std.debug.print("│  curl http://localhost:8008/items/abc                │\n", .{});
    std.debug.print("│  curl http://localhost:8008/file/photos.vacation     │\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("└──────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8008");
}
