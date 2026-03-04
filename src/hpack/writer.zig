pub fn writeAll(writer: anytype, bytes: []const u8) !void {
    const WriterType = @TypeOf(writer);
    switch (@typeInfo(WriterType)) {
        .pointer => |pointer| {
            if (@hasField(pointer.child, "interface")) {
                return writer.interface.writeAll(bytes);
            }
            if (@hasDecl(pointer.child, "writeAll")) {
                return writer.writeAll(bytes);
            }
        },
        else => {
            if (@hasField(WriterType, "interface")) {
                return writer.interface.writeAll(bytes);
            }
            if (@hasDecl(WriterType, "writeAll")) {
                return writer.writeAll(bytes);
            }
        },
    }

    @compileError("writer must expose writeAll(bytes) or interface.writeAll(bytes)");
}
