const std = @import("std");
const Context = @import("context.zig");
const Router = @import("router.zig");
const Server = @import("server.zig");
const http = std.http;

var integration_ready: bool = false;

test "integration: server lifecycle" {
    const allocator = std.testing.allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    try router.get("/hello", struct {
        fn h(ctx: *Context) !void {
            try ctx.text(.ok, "Hello, World!");
        }
    }.h);

    try router.get("/json", struct {
        fn h(ctx: *Context) !void {
            try ctx.json(.ok, "{\"msg\":\"ok\"}");
        }
    }.h);

    try router.get("/users/:id", struct {
        fn h(ctx: *Context) !void {
            const id = ctx.params.get("id") orelse "unknown";
            try ctx.json(.ok, "{s}");
        }
    }.h);

    try router.post("/echo", struct {
        fn h(ctx: *Context) !void {
            const body = try ctx.readBody(std.testing.allocator);
            defer std.testing.allocator.free(body);
            try ctx.json(.ok, body);
        }
    }.h);

    try router.get("/search", struct {
        fn h(ctx: *Context) !void {
            const q = ctx.query.get("q") orelse "";
            var buf = std.ArrayList(u8).empty;
            defer buf.deinit(std.testing.allocator);
            try std.fmt.format(buf.writer(std.testing.allocator), "{{\"q\":\"{s}\"}}", .{q});
            try ctx.json(.ok, buf.items);
        }
    }.h);

    const io = std.Io.Threaded.global_single_threaded.io();

    var server = Server.init(io, &router);

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(s: *Server) void {
            s.listen("127.0.0.1:9876") catch {};
        }
    }.run, .{&server});

    std.time.sleep(200 * std.time.ns_per_ms);

    defer {
        var dummy_conn = std.io.net.tcpConnectToHost(io, "127.0.0.1", 9876) catch return;
        dummy_conn.close(io);
        thread.detach();
    }

    var client: http.Client = .{
        .io = io,
        .allocator = allocator,
    };
    defer client.deinit();

    const Uri = std.Uri;

    {
        const uri = try Uri.parse("http://127.0.0.1:9876/hello");
        var buf: [1024]u8 = undefined;
        var fw = std.io.FixedBufferStream([]u8){ .buffer = &buf, .pos = 0 };
        const result = try client.fetch(.{
            .location = .{ .uri = uri },
            .method = .GET,
            .response_writer = &fw.writer().interface,
        });
        try std.testing.expectEqual(@intFromEnum(http.Status.ok), @intFromEnum(result.status));
        try std.testing.expectEqualStrings("Hello, World!", fw.getWritten());
    }

    {
        const uri = try Uri.parse("http://127.0.0.1:9876/json");
        var buf: [1024]u8 = undefined;
        var fw = std.io.FixedBufferStream([]u8){ .buffer = &buf, .pos = 0 };
        const result = try client.fetch(.{
            .location = .{ .uri = uri },
            .method = .GET,
            .response_writer = &fw.writer().interface,
        });
        try std.testing.expectEqual(@intFromEnum(http.Status.ok), @intFromEnum(result.status));
        try std.testing.expectEqualStrings("{\"msg\":\"ok\"}", fw.getWritten());
    }

    {
        const uri = try Uri.parse("http://127.0.0.1:9876/search?q=zig");
        var buf: [1024]u8 = undefined;
        var fw = std.io.FixedBufferStream([]u8){ .buffer = &buf, .pos = 0 };
        const result = try client.fetch(.{
            .location = .{ .uri = uri },
            .method = .GET,
            .response_writer = &fw.writer().interface,
        });
        try std.testing.expectEqual(@intFromEnum(http.Status.ok), @intFromEnum(result.status));
        try std.testing.expectEqualStrings("{\"q\":\"zig\"}", fw.getWritten());
    }

    {
        const uri = try Uri.parse("http://127.0.0.1:9876/notfound");
        var buf: [1024]u8 = undefined;
        var fw = std.io.FixedBufferStream([]u8){ .buffer = &buf, .pos = 0 };
        const result = try client.fetch(.{
            .location = .{ .uri = uri },
            .method = .GET,
            .response_writer = &fw.writer().interface,
        });
        try std.testing.expectEqual(@intFromEnum(http.Status.not_found), @intFromEnum(result.status));
    }
}
