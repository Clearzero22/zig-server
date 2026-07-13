const std = @import("std");
const compression = @import("compression.zig");
const testing = std.testing;

test "gzip compress produces valid gzip data" {
    const allocator = testing.allocator;
    const original = "Hello, World! This is a test of gzip compression in Zig.";

    const compressed = try compression.gzipCompress(allocator, original);
    defer allocator.free(compressed);

    try testing.expect(compressed.len > 0);
    try testing.expect(compressed[0] == 0x1F); // gzip magic byte 1
    try testing.expect(compressed[1] == 0x8B); // gzip magic byte 2
}

test "gzip compress empty data" {
    const allocator = testing.allocator;
    const compressed = try compression.gzipCompress(allocator, "");
    try testing.expectEqualSlices(u8, &.{}, compressed);
}

test "gzip compress large data is smaller" {
    const allocator = testing.allocator;
    var large = std.ArrayList(u8).empty;
    defer large.deinit(allocator);
    for (0..1000) |_| {
        try large.appendSlice(allocator, "The quick brown fox jumps over the lazy dog. ");
    }

    const compressed = try compression.gzipCompress(allocator, large.items);
    defer allocator.free(compressed);

    try testing.expect(compressed.len < large.items.len);
}
