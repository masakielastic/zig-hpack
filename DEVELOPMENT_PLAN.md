# Zig HPACK Development Plan

## Purpose

This document is the engineering-facing plan for the repository.

Use this file for:

- current implementation status
- design constraints and tradeoffs
- remaining work
- milestone definition
- validation status

For installation, usage, and public API guidance, use `README.md`.

## Goal

Provide a minimal HPACK module in Zig `0.15.2` that is usable from a real HTTP/2 client.

The current scope is intentionally narrow:

- request-side HPACK only
- `Literal Header Field without Indexing` from RFC 7541 section 6.2.2
- no Huffman encoding
- no dynamic table

The first milestone goal, removing the fixed HEADERS payload from the example client and replacing it with module-driven encoding, is already complete.

## Current Status

### Implemented

- request-side HPACK encoder
- `Literal Header Field without Indexing`
- static-table lookup for:
  - `:authority`
  - `:method`
  - `:path`
  - `:scheme`
- integer encoding
- string literal encoding without Huffman
- slice-based encoding API:
  - `encodeLiteralWithoutIndexing`
- writer-based encoding API:
  - `encodedLenLiteralWithoutIndexing`
  - `writeLiteralWithoutIndexing`
- integration into `examples/h2c_client.zig`
- standalone consumer example in `examples/consumer-app`
- package metadata for GitHub/package-manager style consumption

### Not Implemented

- Huffman encoding
- HPACK decoder
- dynamic table support
- indexed header field representation
- literal header field with incremental indexing
- literal header field never indexed
- header table size update
- large header blocks that require `CONTINUATION` frames

## Repository Layout

```text
.
├── LICENSE
├── README.md
├── DEVELOPMENT_PLAN.md
├── build.zig
├── build.zig.zon
├── examples
│   ├── consumer-app
│   │   ├── README.md
│   │   ├── build.zig
│   │   ├── build.zig.zon
│   │   └── src
│   │       └── main.zig
│   └── h2c_client.zig
└── src
    ├── hpack.zig
    └── hpack
        ├── encoder.zig
        ├── integer.zig
        ├── static_table.zig
        ├── string_literal.zig
        └── writer.zig
```

## Public API Snapshot

The package entry point is `src/hpack.zig`.

Core API:

```zig
pub const HeaderField = struct {
    name: []const u8,
    value: []const u8,
};

pub fn encodeLiteralWithoutIndexing(
    allocator: std.mem.Allocator,
    headers: []const HeaderField,
) ![]u8;

pub fn encodedLenLiteralWithoutIndexing(
    headers: []const HeaderField,
) usize;

pub fn writeLiteralWithoutIndexing(
    writer: anytype,
    headers: []const HeaderField,
) !void;
```

Additional exported helpers:

- `integerEncoding`
- `stringLiteral`
- `staticNameIndex`
- `requestPseudoHeaders`
- `writerCompat`

## Document Split

The documentation split is intentional:

- `README.md`
  - user-facing
  - installation
  - build and run commands
  - public API overview
  - consumer package examples
- `DEVELOPMENT_PLAN.md`
  - engineering-facing
  - design direction
  - implementation status
  - validation record
  - remaining roadmap

If information appears in both places, `README.md` should stay concise and task-oriented, while this file should carry the deeper planning context.

## Design Constraints

### Encoder First

The immediate value of the project is to replace hand-written HEADERS payload bytes with a maintainable encoder.
That is why encoder work takes priority over decoder work.

### No Huffman in v0

Huffman support increases implementation and test surface significantly.
For the current goal, interoperability matters more than compression efficiency.

### No Dynamic Table in v0

`Literal Header Field without Indexing` works without dynamic table state.
Avoiding state keeps the API small and the integration straightforward.

### Keep Transport Logic Outside HPACK

The HPACK module is responsible for header block generation only.
HTTP/2 frame headers, socket I/O, SETTINGS handling, and response processing stay in the example client.

### Support Both Slice and Writer Paths

The slice-based API remains useful for tests, inspection, and reuse.
The writer-based path exists because HTTP/2 frame emission needs the payload length before streaming the header block.

## Validation Status

Verified at the repository level:

- `zig build test` succeeds
- `zig build example -- localhost 8080` succeeds

Verified against `nghttpd`:

- with `nghttpd --no-tls 8080`, the example client successfully receives `hello`

Verified as a consumer package:

- in `examples/consumer-app`, `zig build run` succeeds
- in `examples/consumer-app`, `zig build test` succeeds

Current observed HEADERS payload length for the example request is `25` bytes.
This is shorter than the original literal-name-only payload because pseudo-header names now use static-table indices.

## Remaining Work

### Phase A: Documentation and Packaging Polish

- keep `README.md` and this file synchronized with the implementation
- publish the first stable release under the planned tag `v0.1.0`
- add a changelog if release cadence starts to matter

### Phase B: API Hardening

- review public error surfaces
- document the exact intended scope of `writerCompat`
- decide whether helper exports should remain public:
  - `integerEncoding`
  - `stringLiteral`
  - `writerCompat`

### Phase C: Broader HPACK Coverage

- Huffman encoding
- wider static-table support
- design for response-header decoding
- support for additional literal representations

### Phase D: HTTP/2 Integration Expansion

- large header blocks split across `CONTINUATION` frames
- response HEADERS decoding
- broader request-header coverage beyond the current pseudo-header subset

## Risks

- Zig `0.15.2` I/O APIs are materially different from older Zig releases, so over-generalizing writer abstractions can increase maintenance cost
- limiting static-table support to a small subset is fine today, but broader request support will require revisiting lookup structure
- no Huffman support means worse compression efficiency
- no decoder means current value remains concentrated on outbound request generation

## Suggested Next Steps

1. Decide which current helper exports are meant to stay public long term.
2. Decide whether Huffman encoding is a real next milestone or a deliberate non-goal.
3. Draft a minimal decoder plan focused on response HEADERS.
4. Create the first commit and publish the initial `v0.1.0` tag so the tagged GitHub dependency URL becomes live.

## Definition of Done For the Current Milestone

- builds on Zig `0.15.2`
- supports request-side `Literal Header Field without Indexing`
- sends HEADERS from `examples/h2c_client.zig` through the `hpack` module
- successfully performs a GET against `nghttpd:8080`
- can be consumed from another Zig package via `b.dependency("zig_hpack", .{})`
- documents both direct usage and consumer-package usage clearly

## References

- RFC 7541, sections 5.1, 5.2, 6.2.2, appendix A
- Zig `0.15.x` I/O style as used in `examples/h2c_client.zig`
