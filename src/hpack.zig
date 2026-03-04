const encoder = @import("hpack/encoder.zig");
const integer = @import("hpack/integer.zig");
const static_table = @import("hpack/static_table.zig");
const string_literal = @import("hpack/string_literal.zig");
const writer = @import("hpack/writer.zig");

pub const Encoder = encoder.Encoder;
pub const HeaderField = encoder.HeaderField;
pub const encodedLenLiteralWithoutIndexing = encoder.encodedLenLiteralWithoutIndexing;
pub const encodeLiteralWithoutIndexing = encoder.encodeLiteralWithoutIndexing;
pub const writeLiteralWithoutIndexing = encoder.writeLiteralWithoutIndexing;

pub const integerEncoding = integer;
pub const StaticEntry = static_table.StaticEntry;
pub const staticNameIndex = static_table.nameIndex;
pub const requestPseudoHeaders = static_table.request_pseudo_headers;
pub const stringLiteral = string_literal;
pub const writerCompat = writer;

test {
    _ = encoder;
    _ = integer;
    _ = static_table;
    _ = string_literal;
    _ = writer;
}
