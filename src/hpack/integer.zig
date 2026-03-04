const std = @import("std");
const writer = @import("writer.zig");

pub fn encodedLen(prefix_bits: u3, value: usize) usize {
    const max_prefix_value = (@as(usize, 1) << prefix_bits) - 1;
    if (value < max_prefix_value) return 1;

    var length: usize = 1;
    var remaining = value - max_prefix_value;
    while (remaining >= 128) {
        length += 1;
        remaining /= 128;
    }

    return length + 1;
}

pub fn append(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    prefix_bits: u3,
    first_byte_prefix: u8,
    value: usize,
) !void {
    var buffer: [16]u8 = undefined;
    const encoded = encode(&buffer, prefix_bits, first_byte_prefix, value);
    try payload.appendSlice(allocator, encoded);
}

pub fn write(
    out: anytype,
    prefix_bits: u3,
    first_byte_prefix: u8,
    value: usize,
) !void {
    var buffer: [16]u8 = undefined;
    const encoded = encode(&buffer, prefix_bits, first_byte_prefix, value);
    try writer.writeAll(out, encoded);
}

fn encode(
    buffer: *[16]u8,
    prefix_bits: u3,
    first_byte_prefix: u8,
    value: usize,
) []const u8 {
    const max_prefix_value = (@as(usize, 1) << prefix_bits) - 1;
    if (value < max_prefix_value) {
        buffer[0] = first_byte_prefix | @as(u8, @intCast(value));
        return buffer[0..1];
    }

    buffer[0] = first_byte_prefix | @as(u8, @intCast(max_prefix_value));

    var remaining = value - max_prefix_value;
    var index: usize = 1;
    while (remaining >= 128) {
        buffer[index] = (@as(u8, @intCast(remaining % 128))) | 0x80;
        index += 1;
        remaining /= 128;
    }

    buffer[index] = @as(u8, @intCast(remaining));
    return buffer[0 .. index + 1];
}

test "encodes values that fit in the prefix" {
    const allocator = std.testing.allocator;
    var payload = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer payload.deinit(allocator);

    try append(&payload, allocator, 4, 0x00, 10);

    try std.testing.expectEqualSlices(u8, &.{0x0a}, payload.items);
}

test "encodes values at the prefix boundary" {
    const allocator = std.testing.allocator;
    var payload = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer payload.deinit(allocator);

    try append(&payload, allocator, 4, 0x00, 15);

    try std.testing.expectEqualSlices(u8, &.{ 0x0f, 0x00 }, payload.items);
}

test "encodes values that require continuation bytes" {
    const allocator = std.testing.allocator;
    var payload = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer payload.deinit(allocator);

    try append(&payload, allocator, 7, 0x00, 130);

    try std.testing.expectEqualSlices(u8, &.{ 0x7f, 0x03 }, payload.items);
}

test "encodedLen matches the emitted byte count" {
    try std.testing.expectEqual(@as(usize, 1), encodedLen(4, 10));
    try std.testing.expectEqual(@as(usize, 2), encodedLen(4, 15));
    try std.testing.expectEqual(@as(usize, 2), encodedLen(7, 130));
}

test "write emits the same bytes as append" {
    const allocator = std.testing.allocator;
    var payload = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer payload.deinit(allocator);

    var out = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    try append(&payload, allocator, 7, 0x00, 130);
    try write(out.writer(allocator), 7, 0x00, 130);

    try std.testing.expectEqualSlices(u8, payload.items, out.items);
}
