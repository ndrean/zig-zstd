# z-std

![Zig support](https://img.shields.io/badge/Zig-0.15.1-color?logo=zig&color=%23f3ab20)

A Zig wrapper for the Zstandard (zstd) compression library, licensed under GPL2.

This module provides idiomatic Zig bindings to the zstd C library using the C ABI (`extern "c"`), offering both simple one-shot functions and advanced streaming/stateful APIs.

**Goal**: Build a standalone, well-documented library wrapping zstd functionality with Zig's memory safety and error handling.

## Architecture

This library uses:

- **C ABI interop**: Direct `extern "c"` function declarations to call zstd functions
- **Static linking**: Links against `libzstd.a` built from source
- **Zero-cost abstractions**: Thin Zig wrappers that add type safety and error handling without runtime overhead

## Module content

- **Stateless API**: One-shot compression and decompression functions
- **Stateful API**: Compression contexts for reusing memory, with fine control over compression parameters and memory usage
- **Streaming API**: Chunk-by-chunk compression for large files
- **Dictionary support**: Better compression for small files with repeated patterns
- **Compression recipes**: Optimized presets for different data types (text, JSON, binary)

## Examples

See the tests in main.zig for comprehensive usage examples of all APIs.

## Quick Start

```zig
// Simple compression
const compressed = try z.simple_compress(allocator, data, 3);
defer allocator.free(compressed);

// Auto-detecting decompression
const decompressed = try z.simple_auto_decompress(allocator, compressed);
defer allocator.free(decompressed);
```

## Building

### 1. Build the zstd static library

The project uses a static archive of zstd (`libzstd.a`). Build it from the vendored source:

```sh
make
```

This invokes the Makefile which builds `vendor/zstd/libzstd.a`.

### 2. Build the Zig wrapper

```sh
zig build
```

The `build.zig` file:

1. Runs `make` to ensure `libzstd.a` exists
2. Links the static library via C ABI
3. Produces `libz_zstd.a` (the Zig wrapper)

### 3. Run tests

```sh
zig build test
```

This runs all tests in `src/main.zig`, demonstrating each API.

## References

- [Zstandard API Documentation](https://facebook.github.io/zstd/doc/api_manual_latest.html)
- [Zstandard GitHub](https://github.com/facebook/zstd)
