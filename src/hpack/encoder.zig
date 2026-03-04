const std = @import("std");
const integer = @import("integer.zig");
const static_table = @import("static_table.zig");
const string_literal = @import("string_literal.zig");

pub const HeaderField = struct {
    name: []const u8,
    value: []const u8,
};

pub const Encoder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Encoder {
        return .{ .allocator = allocator };
    }

    pub fn encodeLiteralWithoutIndexing(
        self: Encoder,
        headers: []const HeaderField,
    ) ![]u8 {
        var payload = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        errdefer payload.deinit(self.allocator);

        for (headers) |header| {
            try appendLiteralWithoutIndexing(&payload, self.allocator, header);
        }

        return payload.toOwnedSlice(self.allocator);
    }
};

pub fn encodeLiteralWithoutIndexing(
    allocator: std.mem.Allocator,
    headers: []const HeaderField,
) ![]u8 {
    return Encoder.init(allocator).encodeLiteralWithoutIndexing(headers);
}

pub fn encodedLenLiteralWithoutIndexing(headers: []const HeaderField) usize {
    var total: usize = 0;
    for (headers) |header| {
        total += encodedLenForHeader(header);
    }
    return total;
}

pub fn writeLiteralWithoutIndexing(writer: anytype, headers: []const HeaderField) !void {
    for (headers) |header| {
        try writeHeaderLiteralWithoutIndexing(writer, header);
    }
}

fn appendLiteralWithoutIndexing(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    header: HeaderField,
) !void {
    if (static_table.nameIndex(header.name)) |name_index| {
        try integer.append(payload, allocator, 4, 0x00, name_index);
    } else {
        try integer.append(payload, allocator, 4, 0x00, 0);
        try string_literal.append(payload, allocator, header.name);
    }

    try string_literal.append(payload, allocator, header.value);
}

fn encodedLenForHeader(header: HeaderField) usize {
    const name_len = if (static_table.nameIndex(header.name)) |name_index|
        integer.encodedLen(4, name_index)
    else
        integer.encodedLen(4, 0) + string_literal.encodedLen(header.name);

    return name_len + string_literal.encodedLen(header.value);
}

fn writeHeaderLiteralWithoutIndexing(writer: anytype, header: HeaderField) !void {
    if (static_table.nameIndex(header.name)) |name_index| {
        try integer.write(writer, 4, 0x00, name_index);
    } else {
        try integer.write(writer, 4, 0x00, 0);
        try string_literal.write(writer, header.name);
    }

    try string_literal.write(writer, header.value);
}

test "empty header list encodes to an empty payload" {
    const allocator = std.testing.allocator;
    const payload = try encodeLiteralWithoutIndexing(allocator, &.{});
    defer allocator.free(payload);

    try std.testing.expectEqual(@as(usize, 0), payload.len);
}

test "encodes request pseudo headers with indexed names" {
    const allocator = std.testing.allocator;
    const headers = [_]HeaderField{
        .{ .name = ":method", .value = "GET" },
        .{ .name = ":path", .value = "/" },
        .{ .name = ":scheme", .value = "http" },
        .{ .name = ":authority", .value = "localhost" },
    };

    const payload = try encodeLiteralWithoutIndexing(allocator, &headers);
    defer allocator.free(payload);

    try std.testing.expectEqualSlices(u8, &.{
        0x02, 0x03, 'G', 'E', 'T',
        0x04, 0x01, '/',
        0x06, 0x04, 'h', 't', 't', 'p',
        0x01, 0x09, 'l', 'o', 'c', 'a', 'l', 'h', 'o', 's', 't',
    }, payload);
    try std.testing.expectEqual(payload.len, encodedLenLiteralWithoutIndexing(&headers));
}

test "encodes unknown names as literal names" {
    const allocator = std.testing.allocator;
    const headers = [_]HeaderField{
        .{ .name = "x-test", .value = "ok" },
    };

    const payload = try encodeLiteralWithoutIndexing(allocator, &headers);
    defer allocator.free(payload);

    try std.testing.expectEqualSlices(u8, &.{
        0x00,
        0x06, 'x', '-', 't', 'e', 's', 't',
        0x02, 'o', 'k',
    }, payload);
}

test "encodes larger string lengths with multi-byte integers" {
    const allocator = std.testing.allocator;
    const long_value = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const headers = [_]HeaderField{
        .{ .name = "x-test", .value = long_value },
    };

    const payload = try encodeLiteralWithoutIndexing(allocator, &headers);
    defer allocator.free(payload);

    try std.testing.expectEqual(@as(u8, 0x7f), payload[8]);
    try std.testing.expectEqual(@as(u8, 0x03), payload[9]);
}

test "writeLiteralWithoutIndexing matches the slice-based encoder" {
    const allocator = std.testing.allocator;
    const headers = [_]HeaderField{
        .{ .name = ":method", .value = "GET" },
        .{ .name = ":path", .value = "/" },
        .{ .name = ":scheme", .value = "http" },
        .{ .name = ":authority", .value = "localhost" },
    };

    const encoded = try encodeLiteralWithoutIndexing(allocator, &headers);
    defer allocator.free(encoded);

    var out = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    try writeLiteralWithoutIndexing(out.writer(allocator), &headers);

    try std.testing.expectEqualSlices(u8, encoded, out.items);
}
