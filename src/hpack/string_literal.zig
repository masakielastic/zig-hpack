const std = @import("std");
const integer = @import("integer.zig");
const writer = @import("writer.zig");

pub fn encodedLen(value: []const u8) usize {
    return integer.encodedLen(7, value.len) + value.len;
}

pub fn append(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: []const u8,
) !void {
    try integer.append(payload, allocator, 7, 0x00, value.len);
    try payload.appendSlice(allocator, value);
}

pub fn write(out: anytype, value: []const u8) !void {
    try integer.write(out, 7, 0x00, value.len);
    try writer.writeAll(out, value);
}

test "encodes an empty literal string" {
    const allocator = std.testing.allocator;
    var payload = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer payload.deinit(allocator);

    try append(&payload, allocator, "");

    try std.testing.expectEqualSlices(u8, &.{0x00}, payload.items);
}

test "encodes an ASCII literal string without Huffman" {
    const allocator = std.testing.allocator;
    var payload = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer payload.deinit(allocator);

    try append(&payload, allocator, "GET");

    try std.testing.expectEqualSlices(u8, &.{ 0x03, 'G', 'E', 'T' }, payload.items);
}

test "encodes long literal strings with integer continuation bytes" {
    const allocator = std.testing.allocator;
    var payload = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer payload.deinit(allocator);

    const long_value = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try append(&payload, allocator, long_value);

    try std.testing.expectEqual(@as(u8, 0x7f), payload.items[0]);
    try std.testing.expectEqual(@as(u8, 0x03), payload.items[1]);
}

test "encodedLen matches the emitted byte count" {
    try std.testing.expectEqual(@as(usize, 4), encodedLen("GET"));
}

test "write emits the same bytes as append" {
    const allocator = std.testing.allocator;
    var payload = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer payload.deinit(allocator);

    var out = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    try append(&payload, allocator, "GET");
    try write(out.writer(allocator), "GET");

    try std.testing.expectEqualSlices(u8, payload.items, out.items);
}
