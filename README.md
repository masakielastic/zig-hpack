# zig-hpack

Minimal HPACK encoder experiments for Zig `0.15.2`.

`README.md` is the user-facing document for installation, usage, and public APIs.
`DEVELOPMENT_PLAN.md` is the engineering-facing document for implementation status, design constraints, and remaining roadmap.

This repository currently focuses on one narrow use case:

- HTTP/2 request header encoding
- HPACK `Literal Header Field without Indexing`
- plain string literals without Huffman encoding
- request pseudo-header names resolved through the static table when available

The repository also includes a working `examples/h2c_client.zig` example that talks to a local `nghttpd` instance on port `8080`.

## Status

Implemented:

- `Literal Header Field without Indexing`
- static table lookup for `:authority`, `:method`, `:path`, and `:scheme`
- integer encoding
- string literal encoding without Huffman
- slice-based and writer-based encoding APIs
- an HTTP/2 cleartext example client

Not implemented:

- Huffman encoding
- dynamic table support
- HPACK decoding
- incremental indexing
- never-indexed literals
- header table size updates
- large header blocks split across `CONTINUATION` frames

## Zig Version

This code targets Zig `0.15.2`.

The example and module APIs follow the newer Zig `0.15.x` I/O style, including `std.net.Stream.Writer` with `interface.writeAll(...)`.

## Repository Layout

```text
.
├── LICENSE
├── README.md
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

## Build And Test

Run all tests:

```sh
zig build test
```

Run the HTTP/2 cleartext example against a local server:

```sh
zig build example -- localhost 8080
```

Expected output from the example includes:

```text
connecting to localhost:8080
...
hello
```

## Running Against nghttpd

One simple setup is:

```sh
nghttpd --no-tls 8080
```

Then run:

```sh
zig build example -- localhost 8080
```

The example sends a single `GET /` request with these request pseudo-headers:

- `:method = GET`
- `:path = /`
- `:scheme = http`
- `:authority = <host argument>`

## Consumer Example Project

A minimal standalone consumer package lives at `examples/consumer-app`.

It shows the exact Zig `0.15.2` dependency flow for this repository:

```zig
const dep = b.dependency("zig_hpack", .{});
exe.root_module.addImport("hpack", dep.module("hpack"));
```

You can run it directly from its own directory:

```sh
cd examples/consumer-app
zig build run
zig build test
```

## Public API

The public module entry point is `src/hpack.zig`.

Current exports:

- `hpack.HeaderField`
- `hpack.encodeLiteralWithoutIndexing`
- `hpack.encodedLenLiteralWithoutIndexing`
- `hpack.writeLiteralWithoutIndexing`
- `hpack.staticNameIndex`
- `hpack.requestPseudoHeaders`
- `hpack.integerEncoding`
- `hpack.stringLiteral`
- `hpack.writerCompat`

| Symbol | Kind | Purpose |
| --- | --- | --- |
| `hpack.HeaderField` | type | Represents one logical header field with `name` and `value`. |
| `hpack.encodeLiteralWithoutIndexing` | function | Encodes a header list into an owned `[]u8` HPACK payload. |
| `hpack.encodedLenLiteralWithoutIndexing` | function | Computes the final encoded byte length without allocating the payload. |
| `hpack.writeLiteralWithoutIndexing` | function | Streams the encoded HPACK bytes directly into a writer. |
| `hpack.staticNameIndex` | function | Returns the RFC static-table index for the supported pseudo-header names. |
| `hpack.requestPseudoHeaders` | constant | Exposes the currently supported request pseudo-header subset and indices. |
| `hpack.integerEncoding` | module-like namespace | Helper functions for HPACK integer encoding. |
| `hpack.stringLiteral` | module-like namespace | Helper functions for literal string encoding without Huffman. |
| `hpack.writerCompat` | module-like namespace | Small compatibility layer for `writeAll(...)` versus `interface.writeAll(...)`. |

## Using This Module From Another Project

The package name in `build.zig.zon` is `zig_hpack`.

### Local Path Dependency

If you are developing against a local checkout, add this to your consuming project's `build.zig.zon`:

```zig
.dependencies = .{
    .zig_hpack = .{
        .path = "../zig-hpack",
    },
},
```

Then wire the module into your `build.zig`:

```zig
const dep = b.dependency("zig_hpack", .{});
exe.root_module.addImport("hpack", dep.module("hpack"));
```

After that, your Zig source can use:

```zig
const hpack = @import("hpack");
```

### GitHub Dependency

The public repository is:

```text
https://github.com/masakielastic/zig-hpack
```

The first planned release tag is `v0.1.0`.

You can add the dependency with Zig tooling:

```sh
zig fetch --save git+https://github.com/masakielastic/zig-hpack
```

That updates `build.zig.zon`. In the common case, Zig adds a dependency entry keyed by the package name:

```zig
.dependencies = .{
    .zig_hpack = .{
        .url = "git+https://github.com/masakielastic/zig-hpack",
        .hash = "<resolved-by-zig>",
    },
},
```

If you want a versioned dependency, update the saved entry to the `v0.1.0` release reference after fetching, or fetch a version-specific Git reference once you settle on that workflow.

After that, the consuming `build.zig` stays the same:

```zig
const dep = b.dependency("zig_hpack", .{});
exe.root_module.addImport("hpack", dep.module("hpack"));
```

### Slice-Based Encoding

Use this when you want the encoded header block as `[]u8`.
Choose this path when you want to keep, inspect, compare, or reuse the encoded payload after HPACK generation.

```zig
const std = @import("std");
const hpack = @import("hpack");

const headers = [_]hpack.HeaderField{
    .{ .name = ":method", .value = "GET" },
    .{ .name = ":path", .value = "/" },
    .{ .name = ":scheme", .value = "http" },
    .{ .name = ":authority", .value = "localhost" },
};

const payload = try hpack.encodeLiteralWithoutIndexing(allocator, &headers);
defer allocator.free(payload);
```

### Writer-Based Encoding

Use this when you already know where the bytes should go and want to avoid building an intermediate payload buffer.
Choose this path when you are about to write an HTTP/2 frame and already need the payload length up front.

```zig
const payload_len = hpack.encodedLenLiteralWithoutIndexing(&headers);
try writer.interface.writeAll(&frame_header);
try hpack.writeLiteralWithoutIndexing(&writer, &headers);
try writer.interface.flush();
```

The helper accepts writer values that expose either:

- `writeAll(bytes)`
- `interface.writeAll(bytes)`

That is enough for the current `std.net.Stream.Writer` example and for common in-memory writers used in tests.

## Encoding Notes

This implementation intentionally prefers narrow scope over completeness:

- Header names use static table indices only for the current request pseudo-header subset.
- Header values are always emitted as literal strings.
- The Huffman flag is always `0`.
- The writer-based API still requires the caller to know the final header block length before sending an HTTP/2 frame header. `encodedLenLiteralWithoutIndexing` exists for that purpose.

## Example Integration

The example client uses the writer-based API to send the HPACK block directly into the socket writer after the HTTP/2 frame header has been written.

The relevant flow is:

1. Build the logical header list.
2. Compute the HPACK payload length.
3. Write the HTTP/2 frame header.
4. Stream the HPACK bytes directly to the writer.
5. Flush the stream writer.

## Limitations

This is still a minimal development-stage module, not a general-purpose HPACK implementation.

In particular:

- only one literal representation is supported
- only a small static-table subset is recognized by name
- response header decoding is out of scope
- no optimization beyond basic static-name indexing is attempted

## License

This project is licensed under the `MIT` License. See `LICENSE`.
