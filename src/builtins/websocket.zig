const std = @import("std");
const http = std.http;
const Context = @import("../context.zig");
const c = std.c;

pub const Opcode = enum(u4) {
    continuation = 0,
    text = 1,
    binary = 2,
    close = 8,
    ping = 9,
    pong = 10,
};

pub const CloseCode = enum(u16) {
    normal = 1000,
    going_away = 1001,
    protocol_error = 1002,
    unsupported_data = 1003,
    abnormal_close = 1006,
    invalid_frame = 1007,
    policy_violation = 1008,
    message_too_big = 1009,
    mandatory_ext = 1010,
    internal_error = 1011,
    service_restart = 1012,
    try_again_later = 1013,
    bad_gateway = 1014,
    tls_handshake = 1015,
};

pub const Frame = struct {
    fin: bool = true,
    opcode: Opcode = .text,
    mask: bool = false,
    masking_key: [4]u8 = undefined,
    payload: []const u8 = "",
};

const magic_string = "258EAFA5-E914-47DA-95CA-5AB5A0BD85B5";

pub const WebSocket = struct {
    conn: std.Io.net.Stream,
    io: std.Io,
    read_buf: [8192]u8,
    read_pos: usize = 0,
    read_end: usize = 0,
    closed: bool = false,

    pub fn deinit(self: *@This()) void {
        if (!self.closed) {
            self.sendClose(.normal, "") catch {};
        }
        self.conn.close(self.io);
        self.closed = true;
    }

    pub fn send(self: *@This(), frame: Frame) !void {
        var header: [14]u8 = undefined;
        var hdr_len: usize = 0;

        const opcode = @intFromEnum(frame.opcode);
        header[hdr_len] = (@as(u8, if (frame.fin) 1 else 0) << 7) | (@as(u8, @intCast(opcode)) & 0x0F);
        hdr_len += 1;

        const len = frame.payload.len;
        if (len < 126) {
            header[hdr_len] = @as(u8, @intCast(len));
            hdr_len += 1;
        } else if (len <= 0xFFFF) {
            header[hdr_len] = 126;
            hdr_len += 1;
            const be_len = std.mem.toBytes(@as(u16, @intCast(len)));
            @memcpy(header[hdr_len..][0..2], &be_len);
            hdr_len += 2;
        } else {
            header[hdr_len] = 127;
            hdr_len += 1;
            const be_len = std.mem.toBytes(@as(u64, @intCast(len)));
            @memcpy(header[hdr_len..][0..8], &be_len);
            hdr_len += 8;
        }

        const handle = self.conn.socket.handle;
        _ = c.write(handle, header[0..hdr_len].ptr, hdr_len);
        if (frame.payload.len > 0) {
            _ = c.write(handle, frame.payload.ptr, frame.payload.len);
        }
    }

    pub fn sendText(self: *@This(), data: []const u8) !void {
        try self.send(.{ .opcode = .text, .payload = data });
    }

    pub fn sendBinary(self: *@This(), data: []const u8) !void {
        try self.send(.{ .opcode = .binary, .payload = data });
    }

    pub fn sendClose(self: *@This(), code: CloseCode, reason: []const u8) !void {
        const code_val = @intFromEnum(code);
        var payload: [2]u8 = undefined;
        payload = std.mem.toBytes(@as(u16, @intCast(code_val)));
        var msg = std.ArrayList(u8).empty;
        defer msg.deinit(std.heap.page_allocator);
        try msg.appendSlice(std.heap.page_allocator, &payload);
        try msg.appendSlice(std.heap.page_allocator, reason);
        try self.send(.{ .opcode = .close, .payload = msg.items });
        self.closed = true;
    }

    pub fn sendPing(self: *@This(), data: []const u8) !void {
        try self.send(.{ .opcode = .ping, .payload = data });
    }

    pub fn sendPong(self: *@This(), data: []const u8) !void {
        try self.send(.{ .opcode = .pong, .payload = data });
    }

    pub fn recv(self: *@This()) !Frame {
        while (true) {
            const frame = try self.readFrame();
            switch (frame.opcode) {
                .ping => {
                    try self.sendPong(frame.payload);
                },
                .close => {
                    self.closed = true;
                    return frame;
                },
                else => return frame,
            }
        }
    }

    fn readFrame(self: *@This()) !Frame {
        const head = try self.readBytes(2);
        const fin = (head[0] >> 7) & 1 == 1;
        const opcode_val = head[0] & 0x0F;
        const mask = (head[1] >> 7) & 1 == 1;
        var len: u64 = head[1] & 0x7F;

        if (len == 126) {
            const ext = try self.readBytes(2);
            len = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(ext.ptr)), .big);
        } else if (len == 127) {
            const ext = try self.readBytes(8);
            len = std.mem.readInt(u64, @as(*const [8]u8, @ptrCast(ext.ptr)), .big);
        }

        var masking_key: [4]u8 = undefined;
        if (mask) {
            const key_bytes = try self.readBytes(4);
            @memcpy(&masking_key, key_bytes.ptr[0..4]);
        }

        const payload = if (len > 0) blk: {
            const data = try self.readBytes(@intCast(len));
            if (mask) {
                for (data, 0..) |*b, i| {
                    b.* ^= masking_key[i % 4];
                }
            }
            break :blk data;
        } else &.{};

        return .{
            .fin = fin,
            .opcode = @enumFromInt(opcode_val),
            .mask = mask,
            .masking_key = masking_key,
            .payload = payload,
        };
    }

    fn readBytes(self: *@This(), n: usize) ![]u8 {
        const handle = self.conn.socket.handle;
        while (self.read_end - self.read_pos < n) {
            if (self.read_end == self.read_buf.len) {
                std.mem.copyForwards(u8, self.read_buf[0..], self.read_buf[self.read_pos..self.read_end]);
                self.read_end -= self.read_pos;
                self.read_pos = 0;
            }
            const bytes_read = c.read(handle, self.read_buf[self.read_end..].ptr, self.read_buf.len - self.read_end);
            if (bytes_read <= 0) return error.ConnectionClosed;
            self.read_end += @as(usize, @intCast(bytes_read));
        }
        const result = self.read_buf[self.read_pos..][0..n];
        self.read_pos += n;
        return result;
    }
};

pub fn upgrade(ctx: *Context) !WebSocket {
    var has_upgrade = false;
    var has_ws = false;
    var ws_key: ?[]const u8 = null;

    var it = ctx.request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "upgrade")) {
            if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, h.value, " "), "websocket")) {
                has_upgrade = true;
            }
        }
        if (std.ascii.eqlIgnoreCase(h.name, "connection")) {
            var parts = std.mem.splitScalar(u8, h.value, ',');
            while (parts.next()) |part| {
                if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, part, " "), "upgrade")) {
                    has_ws = true;
                }
            }
        }
        if (std.ascii.eqlIgnoreCase(h.name, "sec-websocket-key")) {
            ws_key = std.mem.trim(u8, h.value, " ");
        }
    }

    if (!has_upgrade or !has_ws or ws_key == null) {
        return error.NotWebSocketUpgrade;
    }

    var accept_buf: [128]u8 = undefined;
    const concat = try std.fmt.bufPrint(&accept_buf, "{s}{s}", .{ ws_key.?, magic_string });
    var hash_out: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(concat, &hash_out, .{});
    var b64_buf: [28]u8 = undefined;
    const accept = std.base64.standard.Encoder.encode(&b64_buf, &hash_out);

    try ctx.request.respond("", .{
        .status = .switching_protocols,
        .keep_alive = false,
        .extra_headers = &.{
            http.Header{ .name = "upgrade", .value = "websocket" },
            http.Header{ .name = "connection", .value = "upgrade" },
            http.Header{ .name = "sec-websocket-accept", .value = accept },
        },
    });

    ctx.conn_taken = true;

    return .{
        .conn = ctx._conn.?,
        .io = ctx.io,
        .read_buf = undefined,
    };
}
