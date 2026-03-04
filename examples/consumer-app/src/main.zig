const std = @import("std");
const hpack = @import("hpack");

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buffer);

    const headers = [_]hpack.HeaderField{
        .{ .name = ":method", .value = "GET" },
        .{ .name = ":path", .value = "/" },
        .{ .name = ":scheme", .value = "http" },
        .{ .name = ":authority", .value = "example.com" },
    };

    const payload_len = hpack.encodedLenLiteralWithoutIndexing(&headers);
    try stdout.interface.print("encoded_len={d}\n", .{payload_len});

    var frame_header: [9]u8 = .{
        0x00,
        0x00,
        @as(u8, @intCast(payload_len)),
        0x01,
        0x05,
        0x00,
        0x00,
        0x00,
        0x01,
    };

    _ = &frame_header;

    const allocator = std.heap.page_allocator;
    const payload = try hpack.encodeLiteralWithoutIndexing(allocator, &headers);
    defer allocator.free(payload);

    try stdout.interface.print("payload=", .{});
    for (payload) |byte| {
        try stdout.interface.print("{x:0>2}", .{byte});
    }
    try stdout.interface.writeAll("\n");
    try stdout.interface.flush();
}

test "consumer can import hpack and encode headers" {
    const allocator = std.testing.allocator;
    const headers = [_]hpack.HeaderField{
        .{ .name = ":method", .value = "GET" },
        .{ .name = ":path", .value = "/" },
    };

    const payload = try hpack.encodeLiteralWithoutIndexing(allocator, &headers);
    defer allocator.free(payload);

    try std.testing.expectEqual(@as(usize, 8), payload.len);
    try std.testing.expectEqual(@as(usize, 8), hpack.encodedLenLiteralWithoutIndexing(&headers));
}
