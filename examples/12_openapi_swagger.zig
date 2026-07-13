const std = @import("std");
const fw = @import("zig-server");

const H = struct {
    pub fn listPosts(ctx: *fw.Context) !void { try ctx.json(.ok, "{\"posts\":[]}"); }
    pub fn getPost(ctx: *fw.Context) !void {
        const id = ctx.params.get("id") orelse "?";
        try ctx.json(.ok, try std.fmt.allocPrint(ctx.allocator, "{{\"post\":{{\"id\":{s}}}}}", .{id}));
    }
    pub fn createPost(ctx: *fw.Context) !void {
        const body = try ctx.readBody();
        defer ctx.allocator.free(body);
        try ctx.json(.created, try std.fmt.allocPrint(ctx.allocator, "{{\"created\":{s}}}", .{body}));
    }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.setOpenApiInfo("Blog API", "1.0.0", "A sample blog API");

    try router.getOpts("/posts", H.listPosts, .{
        .summary = "List all posts",
        .tags = "posts",
    });
    try router.getOpts("/posts/:id", H.getPost, .{
        .summary = "Get a single post",
        .tags = "posts",
        .response_type = "application/json",
    });
    try router.postOpts("/posts", H.createPost, .{
        .summary = "Create a post",
        .tags = "posts",
        .body_type = "application/json",
    });

    fw.swagger.init(&router);
    try router.get("/docs", fw.swagger.docsHandler);
    try router.get("/openapi.json", fw.swagger.openapiHandler);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌──────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 12_openapi_swagger — OpenAPI / Swagger 文档          │\n", .{});
    std.debug.print("├──────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("│  GET /openapi.json — OpenAPI 3.0 JSON schema         │\n", .{});
    std.debug.print("│  GET /docs          — Swagger UI 交互式文档           │\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("│  curl http://localhost:8012/openapi.json | jq .       │\n", .{});
    std.debug.print("│  open http://localhost:8012/docs  # 浏览器打开        │\n", .{});
    std.debug.print("│                                                      │\n", .{});
    std.debug.print("└──────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8012");
}
