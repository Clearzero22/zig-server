const std = @import("std");
const sqlite = @import("sqlite");

pub const Error = sqlite.Error;
pub const InitError = sqlite.Db.InitError || Error;
pub const Db = sqlite.Db;
pub const Statement = sqlite.Statement;
pub const ThreadingMode = sqlite.ThreadingMode;

pub const QueryOptions = sqlite.QueryOptions;

pub fn init(path: [:0]const u8) InitError!Db {
    return try Db.init(.{
        .mode = .{ .File = path },
        .open_flags = .{ .write = true, .create = true },
        .threading_mode = .MultiThread,
    });
}

pub fn initMemory() InitError!Db {
    return try Db.init(.{
        .mode = .{ .Memory = {} },
        .open_flags = .{ .write = true, .create = true },
        .threading_mode = .MultiThread,
    });
}

pub fn deinit(db: *Db) void {
    db.deinit();
}
