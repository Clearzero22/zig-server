const std = @import("std");
const fw = @import("zig-server");

const H = struct {
    pub fn textPage(ctx: *fw.Context) !void { try ctx.text(.ok, "Hello plain text"); }
    pub fn jsonPage(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"msg\":\"hello json\"}"); }
    pub fn typedPage(ctx: *fw.Context) !void { try ctx.jsonTyped(ctx.allocator, .ok, .{ .id = 1, .name = "alice" }); }
    pub fn htmlPage(ctx: *fw.Context) !void { try ctx.html(.ok, "<h1>Hello</h1><p>HTML response</p>"); }
    pub fn redirectPage(ctx: *fw.Context) !void { try ctx.redirect(.found, "/target"); }
    pub fn targetPage(ctx: *fw.Context) !void { try ctx.text(.ok, "you were redirected!"); }
    pub fn echoBody(ctx: *fw.Context) !void {
        const body = try ctx.readBody();
        defer ctx.allocator.free(body);
        try ctx.json(.ok, try std.fmt.allocPrint(ctx.allocator, "{{\"echo\":{s}}}", .{body}));
    }
    pub fn search(ctx: *fw.Context) !void {
        const q = ctx.query.get("q") orelse "";
        const page = ctx.query.get("page") orelse "1";
        try ctx.json(.ok, try std.fmt.allocPrint(ctx.allocator, "{{\"q\":\"{s}\",\"page\":\"{s}\"}}", .{ q, page }));
    }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.get("/text", H.textPage);
    try router.get("/json", H.jsonPage);
    try router.get("/typed", H.typedPage);
    try router.get("/html", H.htmlPage);
    try router.get("/redirect", H.redirectPage);
    try router.get("/target", H.targetPage);
    try router.post("/echo", H.echoBody);
    try router.get("/search", H.search);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 13_context_responses — 请求/响应 API                      │\n", .{});
    std.debug.print("├────────────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("│  GET  /text       → text/plain 响应                       │\n", .{});
    std.debug.print("│  GET  /json       → 字符串 JSON 响应                      │\n", .{});
    std.debug.print("│  GET  /typed      → Zig struct 自动 JSON                  │\n", .{});
    std.debug.print("│  GET  /html       → text/html 响应                        │\n", .{});
    std.debug.print("│  GET  /redirect   → 302 → /target                         │\n", .{});
    std.debug.print("│  POST /echo       → 读取 Body 并原样返回                   │\n", .{});
    std.debug.print("│  GET  /search?q=hi&page=2 → 查询参数                       │\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("│  curl http://localhost:8013/text                           │\n", .{});
    std.debug.print("│  curl http://localhost:8013/json                           │\n", .{});
    std.debug.print("│  curl http://localhost:8013/typed                          │\n", .{});
    std.debug.print("│  curl http://localhost:8013/html                           │\n", .{});
    std.debug.print("│  curl -v http://localhost:8013/redirect 2>&1 | grep '<'    │\n", .{});
    std.debug.print("│  curl -X POST -d '{{\"title\":\"hi\"}}' \\                     │\n", .{});
    std.debug.print("│    http://localhost:8013/echo                              │\n", .{});
    std.debug.print("│  curl 'http://localhost:8013/search?q=hello&page=2'        │\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("└────────────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8013");
}
