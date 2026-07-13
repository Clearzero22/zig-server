const std = @import("std");
const http = std.http;

pub const Param = struct { key: []const u8, value: []const u8 };

pub const MAX_PARAMS: usize = 16;

pub const Params = struct {
    items: [MAX_PARAMS]Param = undefined,
    len: usize = 0,

    pub fn get(self: *const Params, key: []const u8) ?[]const u8 {
        for (self.items[0..self.len]) |p| {
            if (std.mem.eql(u8, p.key, key)) return p.value;
        }
        return null;
    }
};

pub const QueryParams = Params;
pub const FormParams = Params;
pub const MAX_FILES: usize = 8;

pub const CookieOptions = struct {
    http_only: bool = false,
    secure: bool = false,
    same_site: ?SameSite = null,
    path: ?[]const u8 = null,
    domain: ?[]const u8 = null,
    max_age: ?i64 = null,
};

pub const SameSite = enum { Strict, Lax, None };

pub const FormFile = struct {
    name: []const u8,
    filename: []const u8,
    content_type: []const u8,
    data: []const u8,
};

pub const FormData = struct {
    params: FormParams = .{},
    files: []const FormFile = &.{},
    _body: []const u8 = "",

    pub fn deinit(fd: *FormData, allocator: std.mem.Allocator) void {
        allocator.free(fd._body);
        if (fd.files.len > 0) allocator.free(fd.files);
    }
};

io: std.Io,
allocator: std.mem.Allocator,
request: *http.Server.Request,
params: Params = .{},
query: QueryParams = .{},
cors_origin: ?[]const u8 = null,
max_body_size: usize = 10 * 1024 * 1024,
db: ?*anyopaque = null,
extra_header_buf: [8]http.Header = undefined,
extra_header_count: usize = 0,
request_id: ?[]const u8 = null,
deadline: i64 = 0,

pub fn cookie(ctx: *@This(), name: []const u8) ?[]const u8 {
    var it = http.HeaderIterator.init(ctx.request.head_buffer);
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "cookie")) {
            var pairs = std.mem.splitScalar(u8, h.value, ';');
            while (pairs.next()) |pair| {
                const trimmed = std.mem.trim(u8, pair, " ");
                if (std.mem.indexOfScalar(u8, trimmed, '=')) |i| {
                    if (std.mem.eql(u8, trimmed[0..i], name)) return trimmed[i + 1..];
                }
            }
            return null;
        }
    }
    return null;
}

pub fn setCookie(ctx: *@This(), name: []const u8, value: []const u8) !void {
    try ctx.setCookieOpts(name, value, .{});
}

pub fn setCookieOpts(ctx: *@This(), name: []const u8, value: []const u8, opts: CookieOptions) !void {
    var list = std.ArrayList(u8).empty;
    try list.appendSlice(ctx.allocator, name);
    try list.append(ctx.allocator, '=');
    try list.appendSlice(ctx.allocator, value);
    if (opts.path) |p| {
        try list.appendSlice(ctx.allocator, "; Path=");
        try list.appendSlice(ctx.allocator, p);
    }
    if (opts.domain) |d| {
        try list.appendSlice(ctx.allocator, "; Domain=");
        try list.appendSlice(ctx.allocator, d);
    }
    if (opts.max_age) |ma| {
        try list.appendSlice(ctx.allocator, "; Max-Age=");
        var ma_buf: [32]u8 = undefined;
        const ma_str = std.fmt.bufPrint(&ma_buf, "{}", .{ma}) catch "0";
        try list.appendSlice(ctx.allocator, ma_str);
    }
    if (opts.http_only) try list.appendSlice(ctx.allocator, "; HttpOnly");
    if (opts.secure) try list.appendSlice(ctx.allocator, "; Secure");
    if (opts.same_site) |ss| {
        try list.appendSlice(ctx.allocator, "; SameSite=");
        try list.appendSlice(ctx.allocator, @tagName(ss));
    }
    try ctx.header("Set-Cookie", list.items);
}

pub fn readForm(ctx: *@This()) !FormData {
    const ct = ctx.request.head.content_type orelse return error.MissingContentType;
    if (std.mem.indexOf(u8, ct, "application/x-www-form-urlencoded") != null) {
        return ctx.readUrlEncodedForm();
    }
    if (std.mem.indexOf(u8, ct, "multipart/form-data") != null) {
        return ctx.readMultipartForm(ct);
    }
    return error.UnsupportedContentType;
}

fn readUrlEncodedForm(ctx: *@This()) !FormData {
    const body = try ctx.readBody();
    var result: FormData = .{ ._body = body };
    parseUrlEncoded(body, &result.params);
    return result;
}

fn parseUrlEncoded(data: []const u8, params: *FormParams) void {
    var it = std.mem.splitScalar(u8, data, '&');
    while (it.next()) |pair| {
        if (pair.len == 0) continue;
        if (params.len >= MAX_PARAMS) return;
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
            params.items[params.len] = .{ .key = pair[0..eq], .value = pair[eq + 1 ..] };
            params.len += 1;
        } else {
            params.items[params.len] = .{ .key = pair, .value = "" };
            params.len += 1;
        }
    }
}

fn readMultipartForm(ctx: *@This(), content_type: []const u8) !FormData {
    const boundary = extractBoundary(content_type) orelse return error.MissingBoundary;
    const body = try ctx.readBody();
    var result: FormData = .{ ._body = body };
    var file_list = std.ArrayList(FormFile).empty;
    errdefer file_list.deinit(ctx.allocator);

    const dash_boundary = try std.fmt.allocPrint(ctx.allocator, "--{s}", .{boundary});
    defer ctx.allocator.free(dash_boundary);
    const crlf_boundary = try std.fmt.allocPrint(ctx.allocator, "\r\n--{s}", .{boundary});
    defer ctx.allocator.free(crlf_boundary);
    const end_marker = try std.fmt.allocPrint(ctx.allocator, "--{s}--", .{boundary});
    defer ctx.allocator.free(end_marker);

    parseMultipart(body, dash_boundary, crlf_boundary, end_marker, &result.params, &file_list, ctx.allocator);

    if (file_list.items.len > 0) {
        result.files = try file_list.toOwnedSlice(ctx.allocator);
    }
    return result;
}

fn extractBoundary(content_type: []const u8) ?[]const u8 {
    const marker = "boundary=";
    const idx = std.mem.indexOf(u8, content_type, marker) orelse return null;
    const start = idx + marker.len;
    var end = start;
    while (end < content_type.len and content_type[end] != ';' and content_type[end] != ' ') {
        end += 1;
    }
    const raw = content_type[start..end];
    if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') {
        return raw[1 .. raw.len - 1];
    }
    return raw;
}

fn eqIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ac, bc| {
        if (std.ascii.toLower(ac) != std.ascii.toLower(bc)) return false;
    }
    return true;
}

fn startsWithIgnoreCase(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    for (s[0..prefix.len], prefix) |sc, pc| {
        if (std.ascii.toLower(sc) != std.ascii.toLower(pc)) return false;
    }
    return true;
}

fn parseMultipart(body: []const u8, dash_boundary: []const u8, crlf_boundary: []const u8, end_marker: []const u8, params: *FormParams, files: *std.ArrayList(FormFile), allocator: std.mem.Allocator) void {
    const first_idx = std.mem.indexOf(u8, body, dash_boundary) orelse return;
    var pos = first_idx + dash_boundary.len;
    if (pos + 2 <= body.len and std.mem.eql(u8, body[pos..pos+2], "\r\n")) {
        pos += 2;
    } else if (pos + 2 <= body.len and std.mem.eql(u8, body[pos..pos+2], "--")) {
        return;
    } else if (pos < body.len and body[pos] == '\n') {
        pos += 1;
    }

    while (pos < body.len) {
        if (pos + end_marker.len <= body.len and std.mem.eql(u8, body[pos..pos + end_marker.len], end_marker)) {
            break;
        }
        if (std.mem.indexOf(u8, body[pos..], crlf_boundary)) |rel| {
            const part_end = pos + rel;
            const part_body = body[pos..part_end];
            if (part_body.len >= 2 and std.mem.eql(u8, part_body[part_body.len - 2 ..], "\r\n")) {
                parsePart(part_body[0 .. part_body.len - 2], params, files, allocator);
            } else {
                parsePart(part_body, params, files, allocator);
            }
            pos = part_end + crlf_boundary.len;
        } else {
            break;
        }
    }
}

pub fn callParsePart(data: []const u8, params: *FormParams, files: *std.ArrayList(FormFile), allocator: std.mem.Allocator) void {
    parsePart(data, params, files, allocator);
}

fn parsePart(data: []const u8, params: *FormParams, files: *std.ArrayList(FormFile), allocator: std.mem.Allocator) void {
    const sep = "\r\n\r\n";
    const header_end = std.mem.indexOf(u8, data, sep) orelse return;
    const header_section = data[0..header_end];
    const part_body = data[header_end + 4 ..];

    var disp_name: ?[]const u8 = null;
    var filename: ?[]const u8 = null;
    var content_type: ?[]const u8 = null;

    var line_it = std.mem.splitScalar(u8, header_section, '\n');
    while (line_it.next()) |line| {
        const trimmed = std.mem.trimEnd(u8, line, "\r");
        if (startsWithIgnoreCase(trimmed, "content-disposition:")) {
            if (std.mem.indexOf(u8, trimmed, "name=\"")) |ni| {
                const val_start = ni + 6;
                const rest = trimmed[val_start..];
                if (std.mem.indexOfScalar(u8, rest, '"')) |qi| {
                    disp_name = rest[0..qi];
                }
            }
            if (std.mem.indexOf(u8, trimmed, "filename=\"")) |fi| {
                const val_start = fi + 10;
                const rest = trimmed[val_start..];
                if (std.mem.indexOfScalar(u8, rest, '"')) |qi| {
                    filename = rest[0..qi];
                }
            }
        } else if (startsWithIgnoreCase(trimmed, "content-type:")) {
            if (std.mem.indexOfScalar(u8, trimmed, ':')) |ci| {
                content_type = std.mem.trim(u8, trimmed[ci + 1 ..], " \r");
            }
        }
    }

    const name = disp_name orelse return;

    if (filename) |fn_val| {
        if (files.items.len < MAX_FILES) {
            const mime = content_type orelse "application/octet-stream";
            files.append(allocator, .{
                .name = name,
                .filename = fn_val,
                .content_type = mime,
                .data = part_body,
            }) catch {};
        }
    } else if (params.len < MAX_PARAMS) {
        params.items[params.len] = .{ .key = name, .value = part_body };
        params.len += 1;
    }
}

pub fn json(ctx: *@This(), status: http.Status, data: []const u8) !void {
    try respondExtra(ctx, data, .{
        .status = status,
        .keep_alive = ctx.request.head.keep_alive,
    }, &.{
        http.Header{ .name = "content-type", .value = "application/json" },
    });
}

pub fn jsonTyped(ctx: *@This(), allocator: std.mem.Allocator, status: http.Status, value: anytype) !void {
    const data = try std.json.Stringify.valueAlloc(allocator, value, .{});
    defer allocator.free(data);
    try respondExtra(ctx, data, .{
        .status = status,
        .keep_alive = ctx.request.head.keep_alive,
    }, &.{
        http.Header{ .name = "content-type", .value = "application/json" },
    });
}

pub fn text(ctx: *@This(), status: http.Status, body: []const u8) !void {
    try respondExtra(ctx, body, .{
        .status = status,
        .keep_alive = ctx.request.head.keep_alive,
    }, &.{});
}

pub fn html(ctx: *@This(), status: http.Status, body: []const u8) !void {
    try respondExtra(ctx, body, .{
        .status = status,
        .keep_alive = ctx.request.head.keep_alive,
    }, &.{
        http.Header{ .name = "content-type", .value = "text/html; charset=utf-8" },
    });
}

pub fn internalError(ctx: *@This(), _: anyerror) !void {
    try respondExtra(ctx, "{\"error\":\"Internal Server Error\",\"status\":500}", .{
        .status = .internal_server_error,
        .keep_alive = ctx.request.head.keep_alive,
    }, &.{
        http.Header{ .name = "content-type", .value = "application/json" },
    });
}

pub fn readBody(ctx: *@This()) ![]const u8 {
    const len = ctx.request.head.content_length orelse return error.BodyRequired;
    if (len > ctx.max_body_size) return error.BodyTooLarge;
    var transfer_buf: [8192]u8 = undefined;
    const body_reader = ctx.request.server.reader.bodyReader(
        &transfer_buf,
        ctx.request.head.transfer_encoding,
        len,
    );
    return try body_reader.readAlloc(ctx.allocator, len);
}

pub fn readJson(ctx: *@This(), comptime T: type) !T {
    const body = try ctx.readBody();
    defer ctx.allocator.free(body);
    return try std.json.parseFromSliceLeaky(T, ctx.allocator, body, .{});
}

pub fn redirect(ctx: *@This(), status: http.Status, url: []const u8) !void {
    try respondExtra(ctx, "", .{
        .status = status,
        .keep_alive = ctx.request.head.keep_alive,
    }, &.{
        http.Header{ .name = "location", .value = url },
    });
}

pub fn noContent(ctx: *@This()) !void {
    try respondExtra(ctx, "", .{
        .status = .no_content,
        .keep_alive = ctx.request.head.keep_alive,
    }, &.{});
}

pub fn sendFile(ctx: *@This(), path: []const u8) !void {
    const file = std.Io.Dir.openFile(.cwd(), ctx.io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ctx.text(.not_found, "Not Found"),
        else => return err,
    };
    defer file.close(ctx.io);

    const stat = try file.stat(ctx.io);
    if (stat.size > ctx.max_body_size) {
        const msg = "File too large";
        try respondExtra(ctx, msg, .{
            .status = .payload_too_large,
            .keep_alive = ctx.request.head.keep_alive,
        }, &.{});
        return;
    }
    const data = try ctx.allocator.alloc(u8, @as(usize, @intCast(stat.size)));
    defer ctx.allocator.free(data);
    _ = try file.readPositionalAll(ctx.io, data, 0);

    const mime = mimeType(std.fs.path.extension(path));

    try respondExtra(ctx, data, .{
        .status = .ok,
        .keep_alive = ctx.request.head.keep_alive,
    }, &.{
        http.Header{ .name = "content-type", .value = mime },
    });
}

fn mimeType(ext: []const u8) []const u8 {
    if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
    if (std.mem.eql(u8, ext, ".js")) return "application/javascript";
    if (std.mem.eql(u8, ext, ".json")) return "application/json";
    if (std.mem.eql(u8, ext, ".png")) return "image/png";
    if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, ".gif")) return "image/gif";
    if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, ".ico")) return "image/x-icon";
    if (std.mem.eql(u8, ext, ".woff2")) return "font/woff2";
    if (std.mem.eql(u8, ext, ".woff")) return "font/woff";
    if (std.mem.eql(u8, ext, ".ttf")) return "font/ttf";
    if (std.mem.eql(u8, ext, ".txt")) return "text/plain; charset=utf-8";
    if (std.mem.eql(u8, ext, ".xml")) return "application/xml";
    if (std.mem.eql(u8, ext, ".pdf")) return "application/pdf";
    if (std.mem.eql(u8, ext, ".wasm")) return "application/wasm";
    if (std.mem.eql(u8, ext, ".map")) return "application/json";
    return "application/octet-stream";
}

pub fn header(ctx: *@This(), name: []const u8, value: []const u8) !void {
    if (ctx.extra_header_count >= 8) return error.TooManyHeaders;
    ctx.extra_header_buf[ctx.extra_header_count] = .{ .name = name, .value = value };
    ctx.extra_header_count += 1;
}

fn respondExtra(ctx: *@This(), data: []const u8, opts: anytype, extra: []const http.Header) !void {
    const has_cors = ctx.cors_origin != null;
    var buf: [32]http.Header = undefined;
    var n: usize = 0;

    if (has_cors) {
        buf[n] = .{ .name = "access-control-allow-origin", .value = ctx.cors_origin.? };
        n += 1;
    }
    for (ctx.extra_header_buf[0..ctx.extra_header_count]) |h| {
        buf[n] = h;
        n += 1;
    }
    for (extra) |h| {
        buf[n] = h;
        n += 1;
    }

    try ctx.request.respond(data, .{
        .status = opts.status,
        .keep_alive = opts.keep_alive,
        .extra_headers = buf[0..n],
    });
}
