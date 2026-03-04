# zig-hpack v0.1.0

Initial public release of `zig-hpack`.

This release provides a minimal HPACK encoder for Zig `0.15.2`, focused on HTTP/2 request generation with `Literal Header Field without Indexing`.

## Highlights

- supports request-side HPACK encoding
- implements `Literal Header Field without Indexing`
- uses static-table lookup for:
  - `:authority`
  - `:method`
  - `:path`
  - `:scheme`
- includes integer encoding
- includes string literal encoding without Huffman
- exposes both slice-based and writer-based APIs
- includes a working `h2c` example client
- includes a standalone consumer package example

## Included In This Release

- package entry point at `src/hpack.zig`
- top-level build targets:
  - `zig build test`
  - `zig build example -- localhost 8080`
- example client:
  - `examples/h2c_client.zig`
- consumer package example:
  - `examples/consumer-app`
- repository documentation:
  - `README.md`
  - `DEVELOPMENT_PLAN.md`

## Public API

Core exports:

- `hpack.HeaderField`
- `hpack.encodeLiteralWithoutIndexing`
- `hpack.encodedLenLiteralWithoutIndexing`
- `hpack.writeLiteralWithoutIndexing`

Supporting exports:

- `hpack.staticNameIndex`
- `hpack.requestPseudoHeaders`
- `hpack.integerEncoding`
- `hpack.stringLiteral`
- `hpack.writerCompat`

## Current Scope

This release is intentionally small.

Implemented:

- request-side HPACK
- literal header fields without indexing
- plain literal strings without Huffman
- static-table lookup for the current request pseudo-header subset

Not included:

- Huffman encoding
- HPACK decoding
- dynamic table support
- incremental indexing
- never-indexed literals
- header table size updates
- `CONTINUATION` frame support for very large header blocks

## Validation

Validated locally with Zig `0.15.2`:

- `zig build test`
- `zig build example -- localhost 8080`
- `examples/consumer-app`
  - `zig build run`
  - `zig build test`

The `h2c` example was also exercised against local `nghttpd --no-tls 8080` and successfully received `hello`.

## GitHub Dependency Example

Tagged release tarball:

```text
https://github.com/masakielastic/zig-hpack/archive/refs/tags/v0.1.0.tar.gz
```

## Notes

This is a minimal interoperability-first release, not a full HPACK implementation.
