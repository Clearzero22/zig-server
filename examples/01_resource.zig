const std = @import("std");
const fw = @import("zig-server");

const PostCtrl = struct {
    fn list(ctx: *fw.Context) !void {
        try ctx.json(.ok, "{\"action\":\"list\",\"resources\":[{\"id\":1,\"title\":\"Hello\"}]}");
    }
    fn show(ctx: *fw.Context) !void {
        const id = ctx.params.get("id") orelse "unknown";
        try ctx.json(.ok, try std.fmt.allocPrint(ctx.allocator, "{{\"action\":\"show\",\"id\":{s}}}", .{id}));
    }
    fn create(ctx: *fw.Context) !void {
        const body = try ctx.readBody();
        defer ctx.allocator.free(body);
        try ctx.json(.created, try std.fmt.allocPrint(ctx.allocator, "{{\"action\":\"create\",\"body\":{s}}}", .{body}));
    }
    fn update(ctx: *fw.Context) !void {
        const id = ctx.params.get("id") orelse "unknown";
        const body = try ctx.readBody();
        defer ctx.allocator.free(body);
        try ctx.json(.ok, try std.fmt.allocPrint(ctx.allocator, "{{\"action\":\"update\",\"id\":{s},\"body\":{s}}}", .{ id, body }));
    }
    fn destroy(ctx: *fw.Context) !void {
        const id = ctx.params.get("id") orelse "unknown";
        try ctx.json(.ok, try std.fmt.allocPrint(ctx.allocator, "{{\"action\":\"destroy\",\"id\":{s}}}", .{id}));
    }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.resource("/posts", .{
        .list    = PostCtrl.list,
        .show    = PostCtrl.show,
        .create  = PostCtrl.create,
        .update  = PostCtrl.update,
        .destroy = PostCtrl.destroy,
    });

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌─────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 01_resource — RESTful CRUD via resource │\n", .{});
    std.debug.print("├─────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                         │\n", .{});
    std.debug.print("│  GET    /posts        → list             │\n", .{});
    std.debug.print("│  POST   /posts        → create           │\n", .{});
    std.debug.print("│  GET    /posts/:id    → show             │\n", .{});
    std.debug.print("│  PUT    /posts/:id    → update           │\n", .{});
    std.debug.print("│  DELETE /posts/:id    → destroy          │\n", .{});
    std.debug.print("│                                         │\n", .{});
    std.debug.print("│ curl http://localhost:8001/posts         │\n", .{});
    std.debug.print("│ curl http://localhost:8001/posts/42      │\n", .{});
    std.debug.print("│ curl -X POST http://localhost:8001/posts \\│\n", .{});
    std.debug.print("│   -d '{{\"title\":\"hi\"}}'                    │\n", .{});
    std.debug.print("│ curl -X PUT http://localhost:8001/posts/1 \\│\n", .{});
    std.debug.print("│   -d '{{\"title\":\"upd\"}}'                   │\n", .{});
    std.debug.print("│ curl -X DELETE http://localhost:8001/posts/1│\n", .{});
    std.debug.print("│                                         │\n", .{});
    std.debug.print("└─────────────────────────────────────────┘\n", .{});
    std.debug.print("\n", .{});

    try server.listen("0.0.0.0:8001");
}
