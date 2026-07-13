const std = @import("std");

var env_map: ?std.StringHashMap([]const u8) = null;
var env_alloc: ?std.mem.Allocator = null;
var loaded: bool = false;

pub fn init(allocator: std.mem.Allocator) !void {
    env_alloc = allocator;
    env_map = std.StringHashMap([]const u8).init(allocator);
}

pub fn loadFile(path: []const u8) !void {
    const alloc = env_alloc orelse return;
    const file = std.fs.cwd().readFileAlloc(alloc, path, 1024 * 64) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer alloc.free(file);

    var lines = std.mem.splitScalar(u8, file, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq| {
            const key = std.mem.trim(u8, trimmed[0..eq], " ");
            const val = std.mem.trim(u8, trimmed[eq + 1 ..], " \"'");
            const key_owned = try alloc.dupe(u8, key);
            const val_owned = try alloc.dupe(u8, val);
            try env_map.?.put(key_owned, val_owned);
        }
    }
    loaded = true;
}

pub fn get(key: []const u8) ?[]const u8 {
    if (env_map) |m| {
        if (m.get(key)) |v| return v;
    }
    return std.os.getenv(key);
}
