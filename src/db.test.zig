const std = @import("std");
const db_mod = @import("builtins/db/sqlite.zig");

const Row = struct { id: i64, label: []const u8 };

const create_items = "CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT NOT NULL)";

fn freeRows(allocator: std.mem.Allocator, rows: []const Row) void {
    for (rows) |r| allocator.free(r.label);
    allocator.free(rows);
}

test "db: init memory and deinit" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try db.exec("CREATE TABLE IF NOT EXISTS ping (v INTEGER)", .{}, .{});
}

test "db: create table and insert" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try db.exec(create_items, .{}, .{});
    try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "hello" });
    try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "world" });
}

test "db: select single row" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try db.exec(create_items, .{}, .{});
    try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "zig" });

    var stmt = try db.prepare("SELECT id, label FROM items WHERE id = ?");
    defer stmt.deinit();
    const row_opt = try stmt.oneAlloc(Row, std.testing.allocator, .{}, .{ .id = @as(i64, 1) });
    if (row_opt) |row| {
        defer std.testing.allocator.free(row.label);
        try std.testing.expectEqual(@as(i64, 1), row.id);
        try std.testing.expectEqualStrings("zig", row.label);
    } else {
        try std.testing.expect(false);
    }
}

test "db: select nonexistent row" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try db.exec(create_items, .{}, .{});
    try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "x" });

    var stmt = try db.prepare("SELECT id, label FROM items WHERE id = ?");
    defer stmt.deinit();
    const row = try stmt.oneAlloc(Row, std.testing.allocator, .{}, .{ .id = @as(i64, 999) });
    try std.testing.expect(row == null);
}

test "db: select all rows" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try db.exec(create_items, .{}, .{});
    try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "a" });
    try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "b" });
    try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "c" });

    var stmt = try db.prepare("SELECT id, label FROM items ORDER BY id");
    defer stmt.deinit();
    const rows = try stmt.all(Row, std.testing.allocator, .{}, .{});
    defer freeRows(std.testing.allocator, rows);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqualStrings("a", rows[0].label);
    try std.testing.expectEqualStrings("b", rows[1].label);
    try std.testing.expectEqualStrings("c", rows[2].label);
}

test "db: select from empty table" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try db.exec(create_items, .{}, .{});

    var stmt = try db.prepare("SELECT id, label FROM items");
    defer stmt.deinit();
    const rows = try stmt.all(Row, std.testing.allocator, .{}, .{});
    defer freeRows(std.testing.allocator, rows);
    try std.testing.expectEqual(@as(usize, 0), rows.len);
}

test "db: update row" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try db.exec(create_items, .{}, .{});
    try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "old" });

    try db.exec("UPDATE items SET label = ? WHERE id = ?", .{}, .{ .label = "new", .id = @as(i64, 1) });

    var stmt = try db.prepare("SELECT label FROM items WHERE id = ?");
    defer stmt.deinit();
    const row_opt = try stmt.oneAlloc(struct { label: []const u8 }, std.testing.allocator, .{}, .{ .id = @as(i64, 1) });
    if (row_opt) |row| {
        defer std.testing.allocator.free(row.label);
        try std.testing.expectEqualStrings("new", row.label);
    } else {
        try std.testing.expect(false);
    }
}

test "db: delete row" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try db.exec(create_items, .{}, .{});
    try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "temp" });

    try db.exec("DELETE FROM items WHERE id = ?", .{}, .{ .id = @as(i64, 1) });

    var stmt = try db.prepare("SELECT COUNT(*) as cnt FROM items");
    defer stmt.deinit();
    const row = try stmt.oneAlloc(struct { cnt: i64 }, std.testing.allocator, .{}, .{});
    try std.testing.expect(row != null);
    try std.testing.expectEqual(@as(i64, 0), row.?.cnt);
}

test "db: getLastInsertRowID" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try db.exec(create_items, .{}, .{});
    try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "first" });
    try std.testing.expectEqual(@as(i64, 1), db.getLastInsertRowID());
    try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "second" });
    try std.testing.expectEqual(@as(i64, 2), db.getLastInsertRowID());
}

test "db: multiple inserts and row IDs" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try db.exec(create_items, .{}, .{});
    var i: i64 = 1;
    while (i <= 10) : (i += 1) {
        try db.exec("INSERT INTO items (label) VALUES (?)", .{}, .{ .label = "x" });
        try std.testing.expectEqual(i, db.getLastInsertRowID());
    }
}

test "db: invalid SQL" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try std.testing.expectError(error.SQLiteError, db.exec("NOT VALID SQL", .{}, .{}));
}

test "db: duplicate primary key" {
    var db = try db_mod.initMemory();
    defer db.deinit();
    try db.exec("CREATE TABLE items (id INTEGER PRIMARY KEY, label TEXT NOT NULL)", .{}, .{});
    try db.exec("INSERT INTO items (id, label) VALUES (?, ?)", .{}, .{ .id = @as(i64, 1), .label = "a" });
    try std.testing.expectError(error.SQLiteConstraint, db.exec("INSERT INTO items (id, label) VALUES (?, ?)", .{}, .{ .id = @as(i64, 1), .label = "b" }));
}
