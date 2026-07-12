const std = @import("std");
const Context = @import("../context.zig");
const Router = @import("../router.zig").Router;

var router: ?*Router = null;

pub fn init(r: *Router) void {
    router = r;
}

pub fn openapiHandler(ctx: *Context) !void {
    const r = router orelse {
        try ctx.text(.internal_server_error, "Swagger not initialized");
        return;
    };
    const json = r.openapiJson(ctx.allocator) catch {
        try ctx.text(.internal_server_error, "Failed to generate OpenAPI spec");
        return;
    };
    defer ctx.allocator.free(json);
    try ctx.json(.ok, json);
}

pub fn docsHandler(ctx: *Context) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\<meta charset="utf-8" />
        \\<meta name="viewport" content="width=device-width, initial-scale=1" />
        \\<title>API Docs</title>
        \\<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
        \\</head>
        \\<body>
        \\<div id="swagger-ui"></div>
        \\<script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js" crossorigin></script>
        \\<script>
        \\  SwaggerUIBundle({
        \\    url: '/openapi.json',
        \\    dom_id: '#swagger-ui',
        \\  });
        \\</script>
        \\</body>
        \\</html>
    ;
    try ctx.html(.ok, html);
}
