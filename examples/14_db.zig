const std = @import("std");
const fw = @import("zig-server");
const sqlite = @import("sqlite");

const User = struct { id: i64, name: []const u8, email: []const u8 };

fn getDb(ctx: *fw.Context) !*sqlite.Db {
    return @as(*sqlite.Db, @ptrCast(@alignCast(ctx.db orelse return error.DBNotSet)));
}

const H = struct {
    pub fn init(ctx: *fw.Context) !void {
        try (try getDb(ctx)).exec("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, email TEXT NOT NULL)", .{}, .{});
        try ctx.json(.ok, "{\"status\":\"ok\",\"table\":\"users\"}");
    }
    pub fn list(ctx: *fw.Context) !void {
        var stmt = try (try getDb(ctx)).prepare("SELECT id, name, email FROM users");
        defer stmt.deinit();
        const rows = try stmt.all(User, ctx.allocator, .{}, .{});
        try ctx.jsonTyped(ctx.allocator, .ok, rows);
    }
    pub fn get(ctx: *fw.Context) !void {
        const id = try std.fmt.parseInt(i64, ctx.params.get("id") orelse return ctx.text(.bad_request, "missing id"), 10);
        var stmt = try (try getDb(ctx)).prepare("SELECT id, name, email FROM users WHERE id = ?");
        defer stmt.deinit();
        const row = try stmt.oneAlloc(User, ctx.allocator, .{}, .{ .id = id });
        if (row) |r| try ctx.jsonTyped(ctx.allocator, .ok, r) else try ctx.text(.not_found, "not found");
    }
    pub fn create(ctx: *fw.Context) !void {
        const body = try ctx.readBody();
        defer ctx.allocator.free(body);
        const parsed = try std.json.parseFromSlice(std.json.Value, ctx.allocator, body, .{});
        defer parsed.deinit();
        const obj = parsed.value.object;
        const name = obj.get("name").?.string;
        const email = obj.get("email").?.string;
        (try getDb(ctx)).exec("INSERT INTO users (name, email) VALUES (?, ?)", .{}, .{ .name = name, .email = email }) catch |err| switch (err) {
            error.SQLiteConstraint => return ctx.text(.conflict, "duplicate"),
            error.SQLiteError => return ctx.text(.bad_request, "db error"),
            else => return err,
        };
        try ctx.json(.created, "{\"status\":\"created\"}");
    }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var db = try fw.db.init("blog.db");
    defer fw.db.deinit(&db);

    var router = fw.Router.init(allocator);
    defer router.deinit();
    router.db = @ptrCast(&db);

    try router.post("/db/init", H.init);
    try router.get("/db/users", H.list);
    try router.get("/db/users/:id", H.get);
    try router.post("/db/users", H.create);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌─────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 14_db — SQLite 数据库 CRUD                             │\n", .{});
    std.debug.print("├─────────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                         │\n", .{});
    std.debug.print("│  POST /db/init      — 创建 users 表                     │\n", .{});
    std.debug.print("│  GET  /db/users     — 列表                              │\n", .{});
    std.debug.print("│  GET  /db/users/:id — 单条                              │\n", .{});
    std.debug.print("│  POST /db/users     — 创建                              │\n", .{});
    std.debug.print("│                                                         │\n", .{});
    std.debug.print("│  curl -X POST http://localhost:8014/db/init              │\n", .{});
    std.debug.print("│  curl -X POST -d '{{\"name\":\"alice\",\"email\":\"a@b\"}}' \\│\n", .{});
    std.debug.print("│    http://localhost:8014/db/users                        │\n", .{});
    std.debug.print("│  curl http://localhost:8014/db/users                     │\n", .{});
    std.debug.print("│  curl http://localhost:8014/db/users/1                   │\n", .{});
    std.debug.print("│                                                         │\n", .{});
    std.debug.print("└─────────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8014");
}
