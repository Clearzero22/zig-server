const std = @import("std");
const fw = @import("framework.zig");
const sqlite = @import("sqlite");
const logger = @import("builtins/logger.zig");
const recovery = @import("builtins/recovery.zig");
const swagger = @import("builtins/swagger.zig");

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    var db = try fw.db.init("app.db");
    defer fw.db.deinit(&db);
    router.db = @ptrCast(&db);

    try router.setOpenApiInfo("Zig Server API", "1.0.0", "A Zig web framework example");

    router.onError(recovery.handler);

    try router.use(logger.handler);
    try router.use(auth);

    try router.get("/", helloHandler);
    try router.get("/json", jsonHandler);
    try router.get("/search", searchHandler);
    try router.get("/admin", adminHandler);
    try router.get("/users/:id", userHandler);
    try router.get("/users/:id/posts/:pid", postHandler);
    try router.post("/echo", echoHandler);
    try router.get("/error", errorHandler);

    try router.post("/db/init", dbInitHandler);
    try router.get("/db/users", dbListHandler);
    try router.get("/db/users/:id", dbGetHandler);
    try router.post("/db/users", dbCreateHandler);

    var api = router.group("/api/v1");
    try api.get("/hello", apiHelloHandler);

    swagger.init(&router);
    try router.get("/docs", swagger.docsHandler);
    try router.get("/openapi.json", swagger.openapiHandler);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);
    try server.listen("0.0.0.0:8080");
}

const User = struct { id: i64, name: []const u8, email: []const u8 };

fn auth(ctx: *fw.Context) !bool {
    const target = ctx.request.head.target;
    if (std.mem.startsWith(u8, target, "/admin") or std.mem.startsWith(u8, target, "/db/")) {
        try ctx.text(.forbidden, "Forbidden");
        return false;
    }
    return true;
}

fn helloHandler(ctx: *fw.Context) !void {
    try ctx.text(.ok, "Hello, World!");
}

fn jsonHandler(ctx: *fw.Context) !void {
    try ctx.json(.ok, "{\"message\": \"Hello, JSON!\"}");
}

fn searchHandler(ctx: *fw.Context) !void {
    const q = ctx.query.get("q") orelse "";
    try ctx.jsonTyped(ctx.allocator, .ok, .{
        .query = q,
        .results = [_]u8{},
    });
}

fn adminHandler(ctx: *fw.Context) !void {
    try ctx.text(.ok, "Admin Panel");
}

fn userHandler(ctx: *fw.Context) !void {
    const id = ctx.params.get("id") orelse "unknown";
    try ctx.jsonTyped(ctx.allocator, .ok, .{ .id = id });
}

fn postHandler(ctx: *fw.Context) !void {
    const id = ctx.params.get("id") orelse "unknown";
    const pid = ctx.params.get("pid") orelse "unknown";
    try ctx.jsonTyped(ctx.allocator, .ok, .{ .id = id, .pid = pid });
}

fn echoHandler(ctx: *fw.Context) !void {
    const body = try ctx.readBody();
    defer ctx.allocator.free(body);
    try ctx.json(.ok, body);
}

fn errorHandler(_: *fw.Context) !void {
    return error.SomethingBad;
}

fn getDb(ctx: *fw.Context) !*sqlite.Db {
    return @as(*sqlite.Db, @ptrCast(@alignCast(ctx.db orelse return error.DBNotSet)));
}

fn dbInitHandler(c: *fw.Context) !void {
    try (try getDb(c)).exec("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, email TEXT NOT NULL)", .{}, .{});
    try c.json(.ok, "{\"status\":\"ok\",\"table\":\"users\"}");
}

fn dbListHandler(c: *fw.Context) !void {
    const d = try getDb(c);
    var stmt = try d.prepare("SELECT id, name, email FROM users");
    defer stmt.deinit();
    const rows = try stmt.all(User, c.allocator, .{}, .{});
    try c.jsonTyped(c.allocator, .ok, rows);
}

fn dbGetHandler(c: *fw.Context) !void {
    const id_str = c.params.get("id") orelse {
        try c.text(.bad_request, "missing id");
        return;
    };
    const id = std.fmt.parseInt(i64, id_str, 10) catch {
        try c.text(.bad_request, "invalid id");
        return;
    };
    var stmt = try (try getDb(c)).prepare("SELECT id, name, email FROM users WHERE id = ?");
    defer stmt.deinit();
    const row = try stmt.oneAlloc(User, c.allocator, .{}, .{ .id = id });
    if (row) |r| {
        try c.jsonTyped(c.allocator, .ok, r);
    } else {
        try c.text(.not_found, "user not found");
    }
}

fn dbCreateHandler(c: *fw.Context) !void {
    const body = try c.readBody();
    defer c.allocator.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, c.allocator, body, .{});
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => {
            try c.text(.bad_request, "expected JSON object");
            return;
        },
    };
    const name_val = obj.get("name") orelse {
        try c.text(.bad_request, "missing name");
        return;
    };
    const email_val = obj.get("email") orelse {
        try c.text(.bad_request, "missing email");
        return;
    };
    const name = switch (name_val) {
        .string => |s| s,
        else => {
            try c.text(.bad_request, "name must be a string");
            return;
        },
    };
    const email = switch (email_val) {
        .string => |s| s,
        else => {
            try c.text(.bad_request, "email must be a string");
            return;
        },
    };
    if (name.len == 0) {
        try c.text(.bad_request, "name cannot be empty");
        return;
    }
    if (email.len == 0) {
        try c.text(.bad_request, "email cannot be empty");
        return;
    }
    if (name.len > 255) {
        try c.text(.bad_request, "name too long");
        return;
    }
    if (email.len > 255) {
        try c.text(.bad_request, "email too long");
        return;
    }
    (try getDb(c)).exec("INSERT INTO users (name, email) VALUES (?, ?)", .{}, .{ .name = name, .email = email }) catch |err| switch (err) {
        error.SQLiteConstraint => {
            try c.text(.conflict, "duplicate entry");
            return;
        },
        error.SQLiteError => {
            try c.text(.bad_request, "database error");
            return;
        },
        else => return err,
    };
    try c.json(.created, "{\"status\":\"created\"}");
}

fn apiHelloHandler(ctx: *fw.Context) !void {
    try ctx.json(.ok, "{\"version\":\"v1\"}");
}
