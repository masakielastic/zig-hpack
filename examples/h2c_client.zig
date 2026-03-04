const std = @import("std");
const hpack = @import("hpack");

const client_preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";

const settings_payload = [_]u8{
    0x00, 0x02, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x03, 0x00, 0x00, 0x00, 0x64,
};

const FrameType = enum(u8) {
    data = 0x0,
    headers = 0x1,
    priority = 0x2,
    rst_stream = 0x3,
    settings = 0x4,
    push_promise = 0x5,
    ping = 0x6,
    goaway = 0x7,
    window_update = 0x8,
    continuation = 0x9,
    _,
};

const FrameHeader = struct {
    length: usize,
    frame_type: FrameType,
    flags: u8,
    stream_id: u31,
};

const Frame = struct {
    header: FrameHeader,
    payload: []u8,
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const host = if (args.len > 1) args[1] else "localhost";
    const port: u16 = if (args.len > 2)
        try std.fmt.parseInt(u16, args[2], 10)
    else
        8080;

    std.debug.print("connecting to {s}:{d}\n", .{ host, port });
    const stream = try std.net.tcpConnectToHost(allocator, host, port);
    defer stream.close();

    var write_buffer: [4096]u8 = undefined;
    var writer = stream.writer(&write_buffer);

    var read_buffer: [4096]u8 = undefined;
    var reader = stream.reader(&read_buffer);

    try sendClientPrefaceAndSettings(&writer);
    try waitForServerSettings(allocator, &reader, &writer);
    try sendRequestHeaders(&writer, 1, host, 0x05);

    var body = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer body.deinit(allocator);

    try receiveResponse(allocator, &reader, &writer, &body);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    try stdout_writer.interface.writeAll(body.items);
    try stdout_writer.interface.flush();
}

fn requestHeaders(host: []const u8) [4]hpack.HeaderField {
    return .{
        .{ .name = ":method", .value = "GET" },
        .{ .name = ":path", .value = "/" },
        .{ .name = ":scheme", .value = "http" },
        .{ .name = ":authority", .value = host },
    };
}

fn sendRequestHeaders(
    writer: *std.net.Stream.Writer,
    stream_id: u31,
    host: []const u8,
    flags: u8,
) !void {
    const headers = requestHeaders(host);
    try sendHeadersLiteralWithoutIndexing(writer, stream_id, &headers, flags);
}

fn sendHeadersLiteralWithoutIndexing(
    writer: *std.net.Stream.Writer,
    stream_id: u31,
    headers: []const hpack.HeaderField,
    flags: u8,
) !void {
    const payload_len = hpack.encodedLenLiteralWithoutIndexing(headers);
    if (payload_len > 0x00ff_ffff) return error.FrameTooLarge;

    const header = encodeFrameHeader(.{
        .length = payload_len,
        .frame_type = .headers,
        .flags = flags,
        .stream_id = stream_id,
    });

    logFrame("send", .{
        .length = payload_len,
        .frame_type = .headers,
        .flags = flags,
        .stream_id = stream_id,
    });

    try writer.interface.writeAll(&header);
    try hpack.writeLiteralWithoutIndexing(writer, headers);
    try writer.interface.flush();
}

fn buildRequestHeadersPayload(allocator: std.mem.Allocator, host: []const u8) ![]u8 {
    const headers = requestHeaders(host);
    return hpack.encodeLiteralWithoutIndexing(allocator, &headers);
}

fn sendClientPrefaceAndSettings(writer: *std.net.Stream.Writer) !void {
    try writer.interface.writeAll(client_preface);
    try sendFrame(writer, .settings, 0x00, 0, settings_payload[0..]);
    std.debug.print("sent client preface and SETTINGS\n", .{});
}

fn waitForServerSettings(
    allocator: std.mem.Allocator,
    reader: *std.net.Stream.Reader,
    writer: *std.net.Stream.Writer,
) !void {
    var saw_server_settings = false;
    while (!saw_server_settings) {
        const frame = try readFrame(allocator, reader);
        defer allocator.free(frame.payload);

        logFrame("recv", frame.header);

        switch (frame.header.frame_type) {
            .settings => {
                if (frame.header.flags & 0x1 != 0) continue;
                saw_server_settings = true;
                try sendFrame(writer, .settings, 0x01, 0, &.{});
                std.debug.print("sent SETTINGS ack\n", .{});
            },
            .window_update => {},
            .ping => {
                if (frame.payload.len == 8 and frame.header.flags & 0x1 == 0) {
                    try sendFrame(writer, .ping, 0x01, 0, frame.payload);
                }
            },
            else => {
                return error.UnexpectedFrameBeforeSettings;
            },
        }
    }
}

fn receiveResponse(
    allocator: std.mem.Allocator,
    reader: *std.net.Stream.Reader,
    writer: *std.net.Stream.Writer,
    body: *std.ArrayList(u8),
) !void {
    while (true) {
        const frame = try readFrame(allocator, reader);
        defer allocator.free(frame.payload);

        logFrame("recv", frame.header);

        switch (frame.header.frame_type) {
            .headers => {
                std.debug.print("response HEADERS payload ({d} bytes)\n", .{frame.payload.len});
            },
            .data => {
                const data = try stripPadding(frame.payload, frame.header.flags);
                try body.appendSlice(allocator, data);
                if (frame.header.flags & 0x1 != 0) return;
            },
            .settings => {
                if (frame.header.flags & 0x1 == 0) {
                    try sendFrame(writer, .settings, 0x01, 0, &.{});
                    std.debug.print("sent SETTINGS ack\n", .{});
                }
            },
            .ping => {
                if (frame.payload.len == 8 and frame.header.flags & 0x1 == 0) {
                    try sendFrame(writer, .ping, 0x01, 0, frame.payload);
                }
            },
            .window_update => {},
            .goaway => {
                logGoaway(frame.payload);
                return error.ServerSentGoaway;
            },
            .rst_stream => {
                logRstStream(frame.payload);
                return error.StreamReset;
            },
            else => {},
        }
    }
}

fn sendHeaders(
    writer: *std.net.Stream.Writer,
    stream_id: u31,
    payload: []const u8,
    flags: u8,
) !void {
    try sendFrame(writer, .headers, flags, stream_id, payload);
}

fn sendFrame(
    writer: *std.net.Stream.Writer,
    frame_type: FrameType,
    flags: u8,
    stream_id: u31,
    payload: []const u8,
) !void {
    if (payload.len > 0x00ff_ffff) return error.FrameTooLarge;

    const header = encodeFrameHeader(.{
        .length = payload.len,
        .frame_type = frame_type,
        .flags = flags,
        .stream_id = stream_id,
    });

    logFrame("send", .{
        .length = payload.len,
        .frame_type = frame_type,
        .flags = flags,
        .stream_id = stream_id,
    });

    try writer.interface.writeAll(&header);
    try writer.interface.writeAll(payload);
    try writer.interface.flush();
}

fn readFrame(allocator: std.mem.Allocator, reader: *std.net.Stream.Reader) !Frame {
    var header_bytes: [9]u8 = undefined;
    try reader.interface().readSliceAll(&header_bytes);
    const parsed = decodeFrameHeader(header_bytes);

    const payload = try allocator.alloc(u8, parsed.length);
    errdefer allocator.free(payload);
    try reader.interface().readSliceAll(payload);

    return .{
        .header = parsed,
        .payload = payload,
    };
}

fn encodeFrameHeader(header: FrameHeader) [9]u8 {
    var bytes: [9]u8 = undefined;
    bytes[0] = @intCast((header.length >> 16) & 0xff);
    bytes[1] = @intCast((header.length >> 8) & 0xff);
    bytes[2] = @intCast(header.length & 0xff);
    bytes[3] = @intFromEnum(header.frame_type);
    bytes[4] = header.flags;

    const stream_id_u32: u32 = header.stream_id;
    bytes[5] = @intCast((stream_id_u32 >> 24) & 0x7f);
    bytes[6] = @intCast((stream_id_u32 >> 16) & 0xff);
    bytes[7] = @intCast((stream_id_u32 >> 8) & 0xff);
    bytes[8] = @intCast(stream_id_u32 & 0xff);
    return bytes;
}

fn decodeFrameHeader(bytes: [9]u8) FrameHeader {
    const length = (@as(usize, bytes[0]) << 16) |
        (@as(usize, bytes[1]) << 8) |
        @as(usize, bytes[2]);
    const stream_id = (@as(u32, bytes[5] & 0x7f) << 24) |
        (@as(u32, bytes[6]) << 16) |
        (@as(u32, bytes[7]) << 8) |
        @as(u32, bytes[8]);

    return .{
        .length = length,
        .frame_type = @enumFromInt(bytes[3]),
        .flags = bytes[4],
        .stream_id = @intCast(stream_id),
    };
}

fn stripPadding(payload: []const u8, flags: u8) ![]const u8 {
    if (flags & 0x08 == 0) return payload;
    if (payload.len == 0) return error.InvalidPadding;

    const pad_length = payload[0];
    if (1 + pad_length > payload.len) return error.InvalidPadding;
    return payload[1 .. payload.len - pad_length];
}

fn logFrame(direction: []const u8, header: FrameHeader) void {
    std.debug.print(
        "{s} frame type={s} len={d} flags=0x{x:0>2} stream={d}\n",
        .{ direction, frameTypeName(header.frame_type), header.length, header.flags, header.stream_id },
    );
}

fn frameTypeName(frame_type: FrameType) []const u8 {
    return switch (frame_type) {
        .data => "DATA",
        .headers => "HEADERS",
        .priority => "PRIORITY",
        .rst_stream => "RST_STREAM",
        .settings => "SETTINGS",
        .push_promise => "PUSH_PROMISE",
        .ping => "PING",
        .goaway => "GOAWAY",
        .window_update => "WINDOW_UPDATE",
        .continuation => "CONTINUATION",
        else => "UNKNOWN",
    };
}

fn logGoaway(payload: []const u8) void {
    if (payload.len < 8) {
        std.debug.print("GOAWAY payload too short ({d})\n", .{payload.len});
        return;
    }

    const last_stream_id = (@as(u32, payload[0] & 0x7f) << 24) |
        (@as(u32, payload[1]) << 16) |
        (@as(u32, payload[2]) << 8) |
        @as(u32, payload[3]);
    const error_code = std.mem.readInt(u32, payload[4..8], .big);
    std.debug.print("GOAWAY last_stream={d} error_code={d}\n", .{ last_stream_id, error_code });
}

fn logRstStream(payload: []const u8) void {
    if (payload.len < 4) {
        std.debug.print("RST_STREAM payload too short ({d})\n", .{payload.len});
        return;
    }

    const error_code = std.mem.readInt(u32, payload[0..4], .big);
    std.debug.print("RST_STREAM error_code={d}\n", .{error_code});
}

test "encodeFrameHeader and decodeFrameHeader round trip" {
    const original = FrameHeader{
        .length = 58,
        .frame_type = .headers,
        .flags = 0x05,
        .stream_id = 1,
    };

    const bytes = encodeFrameHeader(original);
    try std.testing.expectEqualSlices(u8, &.{
        0x00, 0x00, 0x3a,
        0x01,
        0x05,
        0x00, 0x00, 0x00, 0x01,
    }, &bytes);

    const decoded = decodeFrameHeader(bytes);
    try std.testing.expectEqual(original.length, decoded.length);
    try std.testing.expectEqual(original.frame_type, decoded.frame_type);
    try std.testing.expectEqual(original.flags, decoded.flags);
    try std.testing.expectEqual(original.stream_id, decoded.stream_id);
}

test "decodeFrameHeader masks reserved stream bit" {
    const decoded = decodeFrameHeader(.{
        0x00, 0x00, 0x00,
        0x04,
        0x01,
        0x80, 0x00, 0x00, 0x03,
    });

    try std.testing.expectEqual(@as(usize, 0), decoded.length);
    try std.testing.expectEqual(FrameType.settings, decoded.frame_type);
    try std.testing.expectEqual(@as(u8, 0x01), decoded.flags);
    try std.testing.expectEqual(@as(u31, 3), decoded.stream_id);
}

test "stripPadding returns unpadded payload" {
    const payload = [_]u8{ 0x02, 'o', 'k', 'x', 'x' };
    const stripped = try stripPadding(payload[0..], 0x08);
    try std.testing.expectEqualStrings("ok", stripped);
}

test "stripPadding rejects impossible padding" {
    const payload = [_]u8{ 0x05, 'o', 'k' };
    try std.testing.expectError(error.InvalidPadding, stripPadding(payload[0..], 0x08));
}

test "buildRequestHeadersPayload uses hpack module" {
    const allocator = std.testing.allocator;
    const payload = try buildRequestHeadersPayload(allocator, "localhost");
    defer allocator.free(payload);

    try std.testing.expectEqualSlices(u8, &.{
        0x02, 0x03, 'G', 'E', 'T',
        0x04, 0x01, '/',
        0x06, 0x04, 'h', 't', 't', 'p',
        0x01, 0x09, 'l', 'o', 'c', 'a', 'l', 'h', 'o', 's', 't',
    }, payload);
}

test "requestHeaders payload length matches writer-based encoder" {
    const allocator = std.testing.allocator;
    const headers = requestHeaders("localhost");
    const payload = try buildRequestHeadersPayload(allocator, "localhost");
    defer allocator.free(payload);

    try std.testing.expectEqual(payload.len, hpack.encodedLenLiteralWithoutIndexing(&headers));
}
