const std = @import("std");
const fw = @import("zig-server");

const User = struct { id: u32, name: []const u8 };

const H = struct {
    pub fn setCookieHandler(ctx: *fw.Context) !void {
        try ctx.setCookie("session", "abc123");
        try ctx.setCookieOpts("prefs", "theme=dark", .{
            .http_only = true,
            .path = "/",
            .max_age = 86400,
            .same_site = .Lax,
        });
        try ctx.text(.ok, "Cookies set! Check your browser/inspect headers.");
    }

    pub fn getCookieHandler(ctx: *fw.Context) !void {
        const session = ctx.cookie("session") orelse "no-session";
        const prefs = ctx.cookie("prefs") orelse "no-prefs";
        try ctx.jsonTyped(ctx.allocator, .ok, .{
            .session = session,
            .prefs = prefs,
        });
    }

    pub fn formHandler(ctx: *fw.Context) !void {
        var form = try ctx.readForm();
        defer form.deinit(ctx.allocator);
        const name = form.params.get("name") orelse "anonymous";
        const email = form.params.get("email") orelse "none";
        try ctx.jsonTyped(ctx.allocator, .ok, .{
            .name = name,
            .email = email,
        });
    }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.get("/set-cookie", H.setCookieHandler);
    try router.get("/get-cookie", H.getCookieHandler);
    try router.post("/form", H.formHandler);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 16_cookies_form — Cookie & Form 演示                      │\n", .{});
    std.debug.print("├────────────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("│  GET /set-cookie   → 设置 session + prefs cookie           │\n", .{});
    std.debug.print("│  GET /get-cookie   → 读取 cookie 并返回 JSON               │\n", .{});
    std.debug.print("│  POST /form        → 解析 application/x-www-form-urlencoded│\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("│  curl -v http://localhost:8016/set-cookie 2>&1 | grep Set  │\n", .{});
    std.debug.print("│  curl -b 'session=abc123; prefs=theme=dark' \\             │\n", .{});
    std.debug.print("│    http://localhost:8016/get-cookie                        │\n", .{});
    std.debug.print("│  curl -X POST -d 'name=alice&email=alice@test.com' \\      │\n", .{});
    std.debug.print("│    http://localhost:8016/form                              │\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("└────────────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8016");
}
