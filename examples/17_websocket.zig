const std = @import("std");
const fw = @import("zig-server");

const H = struct {
    pub fn healthHandler(ctx: *fw.Context) !void {
        try ctx.json(.ok, "{\"status\":\"ok\"}");
    }

    pub fn wsHandler(ctx: *fw.Context) !void {
        var ws = ctx.upgradeToWebSocket() catch {
            try ctx.text(.bad_request, "WebSocket upgrade failed");
            return;
        };
        defer ws.deinit();

        ws.sendText("Welcome to zig-server WebSocket!") catch return;

        while (true) {
            const frame = ws.recv() catch break;
            switch (frame.opcode) {
                .text, .binary => {
                    ws.sendText(frame.payload) catch break;
                },
                .close => break,
                else => {},
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var router = fw.Router.init(allocator);
    defer router.deinit();

    try router.get("/health", H.healthHandler);
    try router.get("/ws", H.wsHandler);

    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try fw.Server.initPool(io, &router, 4);

    std.debug.print("\n", .{});
    std.debug.print("┌────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│ 17_websocket — WebSocket Echo Server                      │\n", .{});
    std.debug.print("├────────────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("│  GET /health -> {{status:ok}}                              │\n", .{});
    std.debug.print("│  WS  /ws      -> WebSocket echo (send -> recv)            │\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("│  websocat ws://localhost:8017/ws                          │\n", .{});
    std.debug.print("│                                                            │\n", .{});
    std.debug.print("└────────────────────────────────────────────────────────────┘\n", .{});

    try server.listen("0.0.0.0:8017");
}
