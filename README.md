# Zig-std

Goal: build a standalone library that wraps most of the C library with advanced usage, mainly for learning.

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

## ZSTD documentation

- documentation link:

<https://facebook.github.io/zstd/doc/api_manual_latest.html#Chapter4>

## Build static archive of `zstd`

Build a static object `lib_zstd.a` with:

```sh
make
```
