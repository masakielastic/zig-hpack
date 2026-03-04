const std = @import("std");

pub const StaticEntry = struct {
    index: usize,
    name: []const u8,
};

pub const request_pseudo_headers = [_]StaticEntry{
    .{ .index = 1, .name = ":authority" },
    .{ .index = 2, .name = ":method" },
    .{ .index = 4, .name = ":path" },
    .{ .index = 6, .name = ":scheme" },
};

pub fn nameIndex(name: []const u8) ?usize {
    for (request_pseudo_headers) |entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            return entry.index;
        }
    }

    return null;
}

test "nameIndex returns RFC static table indices for request pseudo headers" {
    try std.testing.expectEqual(@as(?usize, 2), nameIndex(":method"));
    try std.testing.expectEqual(@as(?usize, 4), nameIndex(":path"));
    try std.testing.expectEqual(@as(?usize, 6), nameIndex(":scheme"));
    try std.testing.expectEqual(@as(?usize, 1), nameIndex(":authority"));
}

test "nameIndex returns null for unknown names" {
    try std.testing.expectEqual(@as(?usize, null), nameIndex("content-type"));
}
