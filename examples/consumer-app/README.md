# consumer-app

Minimal standalone Zig package showing how to consume `zig_hpack` through:

```zig
const dep = b.dependency("zig_hpack", .{});
exe.root_module.addImport("hpack", dep.module("hpack"));
```

This example uses a local path dependency pointing at the repository root:

```zig
.zig_hpack = .{
    .path = "../..",
},
```

Run it from this directory with:

```sh
zig build run
```

Run its tests with:

```sh
zig build test
```
