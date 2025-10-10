# z-std

![Zig support](https://img.shields.io/badge/Zig-0.15.1-color?logo=zig&color=%23f3ab20)

A Zig wrapper for the Zstandard (zstd) compression library, licensed under GPL2.

This module provides idiomatic Zig bindings to the zstd C library using the C ABI (`extern "c"`), offering a clean, simplified API with flexible configuration.

**Goal**: Build a standalone, well-documented library wrapping zstd functionality with Zig's memory safety and error handling.

## Architecture

This library uses:

- **C ABI interop**: Direct `extern "c"` function declarations to call zstd functions
- **Static linking**: Links against `libzstd.a` built from source
- **Zero-cost abstractions**: Thin Zig wrappers that add type safety and error handling without runtime overhead

## Features

- **Context-based API**: Simple compress/decompress with flexible configuration
- **Streaming API**: Chunk-by-chunk compression for large files with multiple modes (continue, flush, end)
- **Dictionary support**: Train dictionaries and use them for better compression of small similar files
- **Compression recipes**: Optimized presets for different data types (fast, balanced, maximum, text, structured_data, binary)
- **Memory control**: Optional memory limits for decompression contexts
- **Context reuse**: Efficient reset functions for compressing multiple independent frames

## Quick Start

```zig
const z = @import("z_std");

// Initialize contexts
const cctx = try z.init_compressor(.{}); // uses balanced defaults (level 3, dfast)
defer _ = z.free_compressor(cctx);

const dctx = try z.init_decompressor(.{}); // no memory limit
defer _ = z.free_decompressor(dctx);

// Compress and decompress
const compressed = try z.compress(allocator, cctx, data);
defer allocator.free(compressed);

const decompressed = try z.decompress(allocator, dctx, compressed); // auto-detects size
defer allocator.free(decompressed);
```

## Configuration Options

### Compression Context

Use `CompressionConfig` for flexible initialization:

```zig
// Use recipe defaults (recommended)
const cctx = try z.init_compressor(.{ .recipe = .text });
// → level 9 + btopt algorithm

// Override level while keeping recipe's algorithm
const cctx = try z.init_compressor(.{ .compression_level = 15, .recipe = .text });
// → level 15 + btopt algorithm

// Custom level with default algorithm
const cctx = try z.init_compressor(.{ .compression_level = 5 });
// → level 5 + dfast algorithm

// Use all defaults
const cctx = try z.init_compressor(.{});
// → level 3 + dfast algorithm (balanced)
```

### Compression Recipes

Each recipe provides optimized defaults for compression level and ZSTD algorithm:

- **`.fast`** - Fastest compression (level 1, fast algorithm)
- **`.balanced`** - Good balance (level 3, dfast algorithm, **default**)
- **`.maximum`** - Maximum compression (level 22, btultra2 algorithm)
- **`.text`** - Optimized for text/code (level 9, btopt algorithm)
- **`.structured_data`** - Optimized for JSON/XML (level 9, btultra algorithm)
- **`.binary`** - Optimized for binary data (level 6, lazy2 algorithm)

### Decompression Context

Use `DecompressionConfig` for optional memory limits:

```zig
// Use defaults (no memory limit)
const dctx = try z.init_decompressor(.{});

// Limit memory usage (window log 20 = 1MB window)
const dctx = try z.init_decompressor(.{ .max_window_log = 20 });
```

## Advanced Examples

### Context Reuse

Reuse contexts for better performance when compressing multiple items:

```zig
const cctx = try z.init_compressor(.{ .recipe = .text });
defer _ = z.free_compressor(cctx);

const dctx = try z.init_decompressor(.{});
defer _ = z.free_decompressor(dctx);

// Compress first item
const compressed1 = try z.compress(allocator, cctx, data1);
defer allocator.free(compressed1);

// Reset and reuse for next item
try z.reset_compressor_session(cctx);
const compressed2 = try z.compress(allocator, cctx, data2);
defer allocator.free(compressed2);
```

### Streaming Compression

For large files, use streaming API with different modes:

```zig
const cctx = try z.init_compressor(.{});
defer _ = z.free_compressor(cctx);

var compressed_buffer = try allocator.alloc(u8, output_size);
defer allocator.free(compressed_buffer);
var compressed_pos: usize = 0;

// Process chunks
while (reading_data) {
    var in_buf = z.ZSTD_inBuffer{
        .src = chunk.ptr,
        .size = chunk.len,
        .pos = 0,
    };

    const is_last = (no_more_data);
    const end_op = if (is_last) z.ZSTD_EndDirective.ZSTD_e_end else z.ZSTD_EndDirective.ZSTD_e_continue;

    while (in_buf.pos < in_buf.size or (is_last and end_op == .ZSTD_e_end)) {
        var out_buf = z.ZSTD_outBuffer{
            .dst = compressed_buffer.ptr + compressed_pos,
            .size = compressed_buffer.len - compressed_pos,
            .pos = 0,
        };

        const remaining = try z.compressStream(cctx, &out_buf, &in_buf, end_op);
        compressed_pos += out_buf.pos;

        if (is_last and remaining == 0) break;
    }
}
```

**EndDirective modes:**

- **`ZSTD_e_continue`** - Buffer data for better compression (may produce no output)
- **`ZSTD_e_flush`** - Force output for each chunk (for real-time streaming)
- **`ZSTD_e_end`** - Finalize frame with footer/checksum

### Dictionary Training and Usage

Train a dictionary from sample data for better compression of many small similar files:

```zig
// 1. Collect sample data
const samples = [_][]const u8{
    "{\"id\": 1, \"name\": \"Alice\", \"email\": \"alice@example.com\"}",
    "{\"id\": 2, \"name\": \"Bob\", \"email\": \"bob@example.com\"}",
    "{\"id\": 3, \"name\": \"Charlie\", \"email\": \"charlie@example.com\"}",
};

// 2. Train dictionary (100KB target size)
const dictionary = try z.train_dictionary(allocator, &samples, 100 * 1024);
defer allocator.free(dictionary);

// 3. Load dictionary into contexts for reuse
const cctx = try z.init_compressor(.{ .recipe = .structured_data });
defer _ = z.free_compressor(cctx);
try z.load_compression_dictionary(cctx, dictionary);

const dctx = try z.init_decompressor(.{});
defer _ = z.free_decompressor(dctx);
try z.load_decompression_dictionary(dctx, dictionary);

// 4. Compress/decompress with loaded dictionary (more efficient for multiple operations)
const compressed = try z.compress(allocator, cctx, new_data);
defer allocator.free(compressed);

const decompressed = try z.decompress(allocator, dctx, compressed);
defer allocator.free(decompressed);

// Alternative: One-shot compression with dictionary
const compressed_oneshot = try z.compress_with_dict(allocator, cctx, new_data, dictionary, 3);
defer allocator.free(compressed_oneshot);
```

## API Reference

### Initialization Functions

```zig
// Compression context
pub fn init_compressor(config: CompressionConfig) !*ZSTD_CCtx
pub fn free_compressor(ctx: *ZSTD_CCtx) usize

// Decompression context
pub fn init_decompressor(config: DecompressionConfig) !*ZSTD_DCtx
pub fn free_decompressor(ctx: *ZSTD_DCtx) usize
```

### Core Compression/Decompression

```zig
// One-shot operations
pub fn compress(allocator: Allocator, ctx: *ZSTD_CCtx, input: []const u8) ![]u8
pub fn decompress(allocator: Allocator, ctx: *ZSTD_DCtx, input: []const u8) ![]u8
```

### Context Management

```zig
pub fn reset_compressor_session(ctx: *ZSTD_CCtx) !void
pub fn reset_decompressor_session(ctx: *ZSTD_DCtx) !void
```

### Streaming API

```zig
pub fn compressStream(ctx: *ZSTD_CCtx, output: *ZSTD_outBuffer, input: *ZSTD_inBuffer, endOp: ZSTD_EndDirective) !usize
pub fn decompressStream(ctx: *ZSTD_DCtx, output: *ZSTD_outBuffer, input: *ZSTD_inBuffer) !usize

pub fn getStreamInSize() usize
pub fn getStreamOutSize() usize
pub fn getDecompressStreamInSize() usize
pub fn getDecompressStreamOutSize() usize
```

### Dictionary Support

```zig
// Train dictionary from samples
pub fn train_dictionary(allocator: Allocator, samples: []const []const u8, dict_size: usize) ![]u8

// Load dictionary into context (efficient for multiple operations)
pub fn load_compression_dictionary(ctx: *ZSTD_CCtx, dictionary: []const u8) !void
pub fn load_decompression_dictionary(ctx: *ZSTD_DCtx, dictionary: []const u8) !void

// One-shot compression/decompression with dictionary
pub fn compress_with_dict(allocator: Allocator, ctx: *ZSTD_CCtx, input: []const u8, dictionary: []const u8, level: i32) ![]u8
pub fn decompress_with_dict(allocator: Allocator, ctx: *ZSTD_DCtx, input: []const u8, dictionary: []const u8, output_size: usize) ![]u8
```

### Utilities

```zig
pub fn get_decompressed_size(compressed: []const u8) !usize
pub fn version() []const u8
```

## Testing

See `src/main.zig` for comprehensive usage examples of all APIs, including:
- Basic compression and decompression
- Context reuse with different data types
- Streaming compression and decompression
- Compression recipes comparison
- Dictionary training and usage
- Memory-limited decompression

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
